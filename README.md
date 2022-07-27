# zbor

The Concise Binary Object Representation (CBOR) is a data format whose design 
goals include the possibility of extremely small code size, fairly small 
message size, and extensibility without the need for version negotiation
([RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#abstract)). It is used
in different protocols like [CTAP](https://fidoalliance.org/specs/fido-v2.0-ps-20190130/fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-canonical-cbor-encoding-form) 
and [WebAuthn](https://www.w3.org/TR/webauthn-2/#cbor) (FIDO2).

## Supported types by decoder

- [x] Unsigned integers in the range $[0, 2^{64}-1]$ (major type 0).
- [x] Negative integers in the range $[-2^{64}, -1]$ (major type 1).
- [x] Byte strings (major type 2).
- [x] Text strings (major type 3) without UTF-8 support (for now).
- [x] Array of data items (major type 4).
- [x] Map of pairs of data items (major type 5).
- [x] Tagged data item whose tag number is in the range $[0, 2^{64}-1]$ (major type 6).
- [x] Floating-point numbers (major type 7).
- [x] simple values (major type 7). 
- [ ] "break" stop code (major type 7).

## Supported types by encoder

- [x] Unsigned integers in the range $[0, 2^{64}-1]$ (major type 0).
- [x] Negative integers in the range $[-2^{64}, -1]$ (major type 1).
- [x] Byte strings (major type 2).
- [x] Text strings (major type 3) without UTF-8 support (for now).
- [x] Array of data items (major type 4).
- [x] Map of pairs of data items (major type 5).
- [x] Tagged data item whose tag number is in the range $[0, 2^{64}-1]$ (major type 6).
- [x] Floating-point numbers (major type 7).
- [x] simple values (major type 7). 
- [ ] "break" stop code (major type 7).

## Examples

Besides the examples below, you may want to check out the source code and tests.

### CBOR decoder

To simply decode a CBOR byte string, one can use the `decode()` function.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Open a binary file and read its content.
const attestationObject = try std.fs.cwd().openFile(
    "attestationObject.dat", 
    .{ mode = .read_only}
);
defer attestationObject.close();
const bytes = try attestationObject.readToEndAlloc(gpa, 4096);
defer gpa.free(bytes);

// Decode the given CBOR byte string.
// This will return a DataItem on success or throw an error otherwise.
var data_item = try decode(bytes, gpa);
// decode() will allocate memory if neccessary. The caller is responsible for
// deallocation. deinit() will free the allocated memory of all DataItems recursively.
defer data_item.deinit();
```

### CBOR encoder

The `encode()` function can be used to serialize a `DataItem` into a CBOR
byte string.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Create a map-DataItem (major type 5)
var di = DataItem{ .map = std.ArrayList(Pair).init(gpa) };
try di.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
try di.map.append(Pair{ .key = DataItem{ .int = 3 }, .value = DataItem{ .int = 4 } });
defer di.deinit();

// Encode the CBOR map `{1:2,3:4}`. The function will return a ArrayList on
// success or throw an CborError otherwise.
const cbor = try encode(gpa, &di);
defer cbor.deinit();

try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, cbor.items);
```

### DataItem

A `DataItem` is the abstract representation of a single piece of CBOR data. It
is defined as a tagged union, i.e. one can use the `DataItemTag` enum to detect
which field is active (also see: [Type of a DataItem](#type-of-a-dataitem)).

Each field is associated with one of the major types 0-7:

* `int` - An integer in the range $-2^{64}..2^{64}-1$; defined as `i128` (represents both major types 0 and 1)
* `bytes`- A byte string; defined as `std.ArrayList(u8)` (represents major type 2)
* `text`- A text string; defined as `std.ArrayList(u8)` (represents major type 3)
* `array`- An array of `DataItem`s; defined as `std.ArrayList(DataItem)`
* `map`- A map of (key, value) pairs; defined as `std.ArrayList(Pair)`
* `tag` - A tagged data item; defined as `Tag`
* `float` - A 16-, 32- or 64-bit floating-point value; defined as `Float`
* `simple` - A simple value; defined as `SimpleValue`
    * `False`
    * `True`
    * `Null`
    * `Undefined`

#### Type of a DataItem

One can use the `isInt`, `isBytes`, `isText`, `isArray`, `isMap`, `isTagged`,
`isFloat` and `isSimple` function to check the given `DataItem`'s type.

#### int (major type 0 and 1)

Both major type 0 and 1 are decoded to and encoded from the `DataItem.int` field.

> Note: Integers are always encoded as small as possible.

#### bytes (major type 2)

The `DataItem.bytes` field gives access to the underlying `ArrayList(u8)` which
can be manipulated as usual.

#### text (major type 3)

The `DataItem.text` field gives access to the underlying `ArrayList(u8)` which
can be manipulated as usual.

> Note: The current implementation lacks any special UTF-8 support.

#### array (major type 4)

The `DataItem.array` field gives access to the underlying `ArrayList(DataItem)` which
can be manipulated as usual.

The `get()` function can be used to access the element of an array at a specified
index. The function will return `null` if the `DataItem` is not an array or if
the index is out of bounds.

```zig
// CBOR decoder example...
const attStmt = data_item.getValueByString("attStmt");
const x5c = attStmt.?.getValueByString("x5c");

// Access the DataItem at index 0
const x5c_stmt = x5c.?.get(0);

try std.testing.expect(x5c_stmt.?.isBytes());
try std.testing.expectEqual(@as(usize, 704), x5c_stmt.?.bytes.items.len);
```

#### map (major type 5)

To access the value associated with a key one can use the `getValue()` and
`getValueByString()` functions. The first takes an arbitrary `DataItem` as
key while the second expects a string.

```zig
// CBOR decoder example ...
const fmt = data_item.getValueByString("fmt");

try std.testing.expect(fmt.?.isText());
try std.testing.expectEqualStrings("fido-u2f", fmt.?.text.items);
```

#### tag (major type 6)

A tagged data item associates an integer in the range $0..2^{64}-1$ with a data
item. This can be used to give it some additional semantics, e.g. a tag value of 2
combined with a byte string could indicate an unsigned bignum.

See [RFC8949: Tagging of Items](https://www.rfc-editor.org/rfc/rfc8949.html#name-tagging-of-items)
for more information.

#### float (major type 7)

Representation of 16- (`DataItem.float.float16`), 32- (`DataItem.float.float32`), 
and 64-bit (`DataItem.float.float64`) floating-point numbers.

> Note: The representations of any floating-point values are not changed by the
> encoder.


#### simple (major type 7)

Currently supported are `False` (20), `True` (21), `Null` (22) and `Undefined` (23).

## CTAP2 canonical CBOR encoding

This project tries to obey the CTAP2 canonical CBOR encoding rules as much
as possible.

* Integers are encoded as small as possible.
    * 0 to 23 and -1 to -24 must be expressed in the same byte as the major type;
    * 24 to 255 and -25 to -256 must be expressed only with an additional uint8_t;
    * 256 to 65535 and -257 to -65536 must be expressed only with an additional uint16\_t;
    * 65536 to 4294967295 and -65537 to -4294967296 must be expressed only with an additional uint32\_t.
* The representations of any floating-point values are not changed.
* The expression of lengths in major types 2 through 5 are as short as possible. 
  The rules for these lengths follow the above rule for integers.
* The keys in every map are sorted lowest value to highest. The sorting rules are:
    * If the major types are different, the one with the lower value in numerical order sorts earlier.
    * If two keys have different lengths, the shorter one sorts earlier;
    * If two keys have the same length, the one with the lower value in (byte-wise) lexical order sorts earlier.

> Note: These rules are equivalent to a lexicographical comparison of the 
> canonical encoding of keys for major types 0-3 and 7 (integers, strings, 
> and simple values). Keys with major types 4-6 are sorted by only taking the major
> type into account. It is up to the user to make sure that majort types 4-6
> are not used as key.

## Project Status

| Task | Todo | In progress | Done |
|:----:|:----:|:-----------:|:----:|
| Decoder | | x | |
| Encoder | | x | |
| CBOR to JSON | | x | |
| JSON to CBOR | x | | |
