# zbor - Zig CBOR

![GitHub](https://img.shields.io/github/license/r4gus/zbor?style=flat-square)
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/r4gus/zbor/CI?style=flat-square)
![GitHub all releases](https://img.shields.io/github/downloads/r4gus/zbor/total?style=flat-square)

The Concise Binary Object Representation (CBOR) is a data format whose design 
goals include the possibility of extremely small code size, fairly small 
message size, and extensibility without the need for version negotiation
([RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#abstract)). It is used
in different protocols like [CTAP](https://fidoalliance.org/specs/fido-v2.0-ps-20190130/fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-canonical-cbor-encoding-form) 
and [WebAuthn](https://www.w3.org/TR/webauthn-2/#cbor) (FIDO2).

The project is split into a library and a command line application which can be
used to decode CBOR data.

* [Examples](#examples)
* [Serialization](#serialization)
* [Command line application](#command-line-application)
* [Supported Types](#project-status)

## Features

- CBOR decoder
- CBOR encoder
- CBOR to JSON serialization
- CBOR to Zig parser

A CBOR byte string is decoded into a (nested) `DataItem` data structure, which 
can be inspected and manipulated.

## Examples

Besides the examples below, you may want to check out the source code and tests.

### CBOR decoder

To simply decode a CBOR byte string, one can use the `decode()` function.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Open a binary file and read its content.
const attestationObject = try std.fs.cwd().openFile(
    "attestationObject.dat", 
    .{ .mode = .read_only}
);
defer attestationObject.close();
const bytes = try attestationObject.readToEndAlloc(allocator, 4096);
defer allocator.free(bytes);

// Decode the given CBOR byte string.
// This will return a DataItem on success or throw an error otherwise.
var data_item = try decode(allocator, bytes);
// decode() will allocate memory if neccessary. The caller is responsible for
// deallocation. deinit() will free the allocated memory of all DataItems recursively.
// Because DataItem doesn't store the used Allocator, it must be provided by the
// caller as argument.
defer data_item.deinit(allocator);
```

### CBOR encoder

The `encode` and `encodeAlloc` functions can be used to serialize 
a `DataItem` into a CBOR byte string. They work similar to
`std.json.stringify` and `std.json.stringifyAlloc`.

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Create a map-DataItem (major type 5)
var di = DataItem.map(allocator, &.{
    Pair.new(DataItem.int(1), DataItem.int(2)), // 1:2
    Pair.new(DataItem.int(3), DataItem.int(4))  // 3:4
});
defer di.deinit(allocator);

// Encode the CBOR map `{1:2,3:4}`. The function will return a byte slice on
// success or throw an CborError otherwise.
const cbor = try encodeAlloc(allocator, &di);
defer allocator.free(cbor);

try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, cbor);
```

### DataItem

A `DataItem` is the abstract representation of a single piece of CBOR data. It
is defined as a tagged union, i.e. one can use the `DataItemTag` enum to detect
which field is active (also see: [Type of a DataItem](#type-of-a-dataitem)).

Each field is associated with one of the major types 0-7:

* `int` - An integer in the range $-2^{64}..2^{64}-1$; defined as `i65` (represents both major types 0 and 1)
* `bytes`- A byte string; defined as `[]u8` (represents major type 2)
* `text`- A text string; defined as `[]u8` (represents major type 3)
* `array`- An array of `DataItem`s; defined as `[]DataItem`
* `map`- A map of (key, value) pairs; defined as `[]Pair`
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

Integers are represented by the major types 0 (unsigned, $0-2^{64}..1$) and 1 
(negative, $-2^{64}..-1$). The `.int` field of the tagged union `DataItem` 
represents both major types using `i128` as a type.

The following code defines a new int `DataItem` with the value `12345`:
```zig
const di = DataItem{ .int = 12345 };

// or just use a helper function
const di2 = DataItem.int(12345);
```
Note that because no extra memory is allocated, you're not required to call 
`deinit()` on `di`.

> Note: Integers are always encoded as small as possible.

#### bytes (major type 2)

The `.bytes` field of a `DataItem` is a `u8` slice.

The following code defines a new bytes `DataItem`:
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const di = try DataItem.bytes(allocator, &.{0x1, 0x2, 0x3, 0x4, 0x5});
// The DataItem doesn't store the used allocator so one must
// provide it to deinit().
defer di.deinit(allocator);
```

The passed data is copied instead of being referenced directly.

#### text (major type 3)

The `.text` field of a `DataItem` is a `u8` slice representing a utf-8 string.

A new text string can created using the following code:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const di = try DataItem.text(allocator, "IETF");
// The DataItem doesn't store the used allocator so one must
// provide it to deinit().
defer di.deinit(allocator);
```

The passed string is copied instead of being referenced directly.

> Note: The current implementation lacks any special UTF-8 support.

#### array (major type 4)

The `DataItem.array` field gives access to the underlying `DataItem` slice.

A new array can be created using the following code:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Create an array of two data items of type int (mt 0)
const di = try DataItem.array(allocator, &.{DataItem.int(1), DataItem.int(2)});
// The DataItem doesn't store the used allocator so one must
// provide it to deinit().
defer di.deinit(allocator);
```

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

The `DataItem.map` field gives access to the underlying `Pair` slice. A `Pair`
consists of a key and a value and is defined as:

```zig
pub const Pair = struct { key: DataItem, value: DataItem };
```

You can create a new pair using the `new()` function:
```zig
const p = Pair.new(try DataItem.text(allocator, "a"), DataItem.int(2)); // "a":2
```

A new map can be created using the following code:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Create an map: {1:2,3:4}
var di = try DataItem.map(allocator, &.{
    Pair.new(DataItem.int(1), DataItem.int(2)), // 1:2
    Pair.new(DataItem.int(3), DataItem.int(4))  // 3:4
});
// The DataItem doesn't store the used allocator so one must
// provide it to deinit().
defer di.deinit(allocator);
```

To access the value associated with a key one can use the `getValue()` and
`getValueByString()` functions. The first takes an arbitrary `DataItem` as
key while the second expects a string.

```zig
// CBOR decoder example ...
const fmt = data_item.getValueByString("fmt");

try std.testing.expect(fmt.?.isText());
try std.testing.expectEqualStrings("fido-u2f", fmt.?.text.items);
```

> Note: In general one can use any `DataItem` type as key. If you want to serialize
> a `DataItem` to JSON make sure that all keys are text strings.

#### tag (major type 6)

A tagged data item associates an integer in the range $0..2^{64}-1$ with a data
item. This can be used to give it some additional semantics, e.g. a tag value of 2
combined with a byte string could indicate an unsigned bignum.

See [RFC8949: Tagging of Items](https://www.rfc-editor.org/rfc/rfc8949.html#name-tagging-of-items)
for more information.


A new tagged data item can be created using the following code:
```zig
// Create the tagged data item 1(2)
const di = try DataItem.tagged(allocator, 1, DataItem.int(2));
defer di.deinit(allocator);

// Create bignum
const bignum = try DataItem.unsignedBignum(allocator, &.{ 0xf6, 0x53, 0xd8, 0xf5, 0x55, 0x8b, 0xf2, 0x49, 0x1d, 0x90, 0x96, 0x13, 0x44, 0x8d, 0xd1, 0xd3 });
defer bignum.deinit(allocator);
```

#### float (major type 7)

Representation of 16- (`DataItem.float.float16`), 32- (`DataItem.float.float32`), 
and 64-bit (`DataItem.float.float64`) floating-point numbers.

```zig
const float16 = DataItem.float16(5.960464477539063e-8);
const float32 = DataItem.float32(3.4028234663852886e+38);
const float64 = DataItem.float64(1.0e+300);
```

> Note: The representations of any floating-point values are not changed by the
> encoder.


#### simple (major type 7)

Currently supported are `False` (20), `True` (21), `Null` (22) and `Undefined` (23).

## Serialization

### DataItem to JSON

Because `DataItem` implements `jsonStringify()` one can serialize it to JSON.
The rules used for serialization are defined in 
[RFC8949 §6.1: Converting from CBOR to JSON](https://www.rfc-editor.org/rfc/rfc8949.html#name-converting-from-cbor-to-jso)

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const di = try DataItem.map(allocator, &.{ 
    Pair.new(try DataItem.text(allocator, "a"), DataItem.int(1)), 
    Pair.new(try DataItem.text(allocator, "b"), try DataItem.array(allocator, &.{ 
        DataItem.int(2), DataItem.int(3) 
    })) 
});
defer di.deinit(allocator);

var json = std.ArrayList(u8).init(allocator);
defer json.deinit();

// Serialize di into JSON
try std.json.stringify(di, .{}, json.writer());

try std.testing.expectEqualStrings("{\"a\":1,\"b\":[2,3]}", string.items);
```

### JSON to DataItem

Comming... when its done

### Dataitem to Zig

One can parse CBOR into a struct and other Zig types.

```zig
const cbor = @import("zbor");

// {
//   "vals": {
//     "testing": 1,
//     "production": 42,
//   },
//   "uptime": 9999
// }
const payload = "\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f";

const Config = struct {
    vals: struct { testing: u8, production: u8 },
    uptime: u64,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var data_item = try cbor.decode(allocator, payload);
defer data_item.deinit(allocator);

const config = try parse(Config, di, .{});
_ = config; // do something
```

If you have a CBOR map with integers as keys, you can use `@\"<nr>\"`, e.g.:

```zig
const Config = struct {
    @"1": struct { @"1": u8, @"2": u8 },
    @"2": u64,
};
```

Supported types are `bool`, `float`, `int`, `struct`, `array` and types are allowed to be optional.

## CTAP2 canonical CBOR encoding

This project tries to obey the CTAP2 canonical CBOR encoding rules as much
as possible.

* Integers are encoded as small as possible.
    * 0 to 23 and -1 to -24 must be expressed in the same byte as the major type;
    * 24 to 255 and -25 to -256 must be expressed only with an additional uint8\_t;
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

## Command line application

The command line application can decode a given CBOR byte string and print it
to stdout.

* Options:
    * `-h`, `--help` - Display a help message.
    * `-o`, `--output` - Specify the output format (only json at the moment).
    * `--hex <str>` - Provide the CBOR data as hex string.

```
$ ./zig-out/bin/zbor -o json --hex=c074323031332d30332d32315432303a30343a30305a
"2013-03-21T20:04:00Z"
```

```
$ ./zig-out/bin/zbor -o json data/WebAuthnCreate.dat 
{"fmt":"fido-u2f","attStmt":{"sig":"MEUCIQDxiq8pf_27Z2osKh-3EnKViLVnMvh5oSuUhhC1AtBb1wIgT-C4h13JDnutnjn1mR9JVfRlE0rXXoknYH5eI3jAqWc","x5c":["MIICvDCCAaSgAwIBAgIEA63wEjANBgkqhkiG9w0BAQsFADAuMSwwKgYDVQQDEyNZdWJpY28gVTJGIFJvb3QgQ0EgU2VyaWFsIDQ1NzIwMDYzMTAgFw0xNDA4MDEwMDAwMDBaGA8yMDUwMDkwNDAwMDAwMFowbTELMAkGA1UEBhMCU0UxEjAQBgNVBAoMCVl1YmljbyBBQjEiMCAGA1UECwwZQXV0aGVudGljYXRvciBBdHRlc3RhdGlvbjEmMCQGA1UEAwwdWXViaWNvIFUyRiBFRSBTZXJpYWwgNjE3MzA4MzQwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQZnoecFi233DnuSkKgRhalswn-ygkvdr4JSPltbpXK5MxlzVSgWc-9x8mzGysdbBhEecLAYfQYqpVLWWosHPoXo2wwajAiBgkrBgEEAYLECgIEFTEuMy42LjEuNC4xLjQxNDgyLjEuNzATBgsrBgEEAYLlHAIBAQQEAwIEMDAhBgsrBgEEAYLlHAEBBAQSBBD6K5ncnjlCV4-SSjDSPEEYMAwGA1UdEwEB_wQCMAAwDQYJKoZIhvcNAQELBQADggEBACjrs2f-0djw4onryp_22AdXxg6a5XyxcoybHDjKu72E2SN9qDGsIZSfDy38DDFr_bF1s25joiu7WA6tylKA0HmEDloeJXJiWjv7h2Az2_siqWnJOLic4XE1lAChJS2XAqkSk9VFGelg3SLOiifrBet-ebdQwAL-2QFrcR7JrXRQG9kUy76O2VcSgbdPROsHfOYeywarhalyVSZ-6OOYK_Q_DLIaOC0jXrnkzm2ymMQFQlBAIysrYeEM1wxiFbwDt-lAcbcOEtHEf5ZlWi75nUzlWn8bSx_5FO4TbZ5hIEcUiGRpiIBEMRZlOIm4ZIbZycn_vJOFRTVps0V0S4ygtDc"]},"authData":"IQkYX2k6AeoaJkH4LVL7ru4KT0fjN03--HCDjeSbDpdBAAAAAAAAAAAAAAAAAAAAAAAAAAAAQLP4zbGAIJF2-iAaUW0bQvgCqA2vSNA3iCGm-91S3ha37_YiJXJDjeWFfnD57wWA6TfjAK7Q3_E_tqM-w4uBytClAQIDJiABIVgg2fTCo1ITbxnJqV2ogkq1zcTVYx68_VvbsL__JTYJEp4iWCDvQEuIB2VXYAeIij7Wq_-0JXtxI1UzJdRQYTy1vJo6Ug"}
```
> Note: Byte strings are encoded in base64url without padding as defined by
> RFC8949 §6.1

```
$ ./zig-out/bin/zbor data/WebAuthnCreate.dat 
A3 # map(3)
  63 # text(3)
    666D74 # "fmt"
  68 # text(8)
    6669646F2D753266 # "fido-u2f"
  67 # text(7)
    61747453746D74 # "attStmt"
  A2 # map(2)
    63 # text(3)
      736967 # "sig"
    58 47 # bytes(71)

3045022100F18AAF297FFDBB676A2C2A1FB712729588B56732F879A12B948610B502D05BD702204
FE0B8875DC90E7BAD9E39F5991F4955F465134AD75E8927607E5E2378C0A967
    63 # text(3)
      783563 # "x5c"
    81 # array(1)
      59 2C0 # bytes(704)

308202BC308201A4A003020102020403ADF012300D06092A864886F70D01010B0500302E312C302
A0603550403132359756269636F2055324620526F6F742043412053657269616C20343537323030
3633313020170D3134303830313030303030305A180F32303530303930343030303030305A306D3
10B300906035504061302534531123010060355040A0C0959756269636F20414231223020060355
040B0C1941757468656E74696361746F72204174746573746174696F6E3126302406035504030C1
D59756269636F205532462045452053657269616C2036313733303833343059301306072A8648CE
3D020106082A8648CE3D03010703420004199E879C162DB7DC39EE4A42A04616A5B309FECA092F7
6BE0948F96D6E95CAE4CC65CD54A059CFBDC7C9B31B2B1D6C184479C2C061F418AA954B596A2C1C
FA17A36C306A302206092B0601040182C40A020415312E332E362E312E342E312E34313438322E3
12E373013060B2B0601040182E51C0201010404030204303021060B2B0601040182E51C01010404
120410FA2B99DC9E3942578F924A30D23C4118300C0603551D130101FF04023000300D06092A864
886F70D01010B0500038201010028EBB367FED1D8F0E289EBCA9FF6D80757C60E9AE57CB1728C9B
1C38CABBBD84D9237DA831AC21949F0F2DFC0C316BFDB175B36E63A22BBB580EADCA5280D079840
E5A1E2572625A3BFB876033DBFB22A969C938B89CE171359400A1252D9702A91293D54519E960DD
22CE8A27EB05EB7E79B750C002FED9016B711EC9AD74501BD914CBBE8ED9571281B74F44EB077CE
61ECB06AB85A97255267EE8E3982BF43F0CB21A382D235EB9E4CE6DB298C405425040232B2B61E1
0CD70C6215BC03B7E94071B70E12D1C47F96655A2EF99D4CE55A7F1B4B1FF914EE136D9E6120471
48864698880443116653889B86486D9C9C9FFBC9385453569B345744B8CA0B437
  68 # text(8)
    6175746844617461 # "authData"
  58 C4 # bytes(196)

2109185F693A01EA1A2641F82D52FBAEEE0A4F47E3374DFEF870838DE49B0E97410000000000000
0000000000000000000000000000040B3F8CDB180209176FA201A516D1B42F802A80DAF48D03788
21A6FBDD52DE16B7EFF6222572438DE5857E70F9EF0580E937E300AED0DFF13FB6A33EC38B81CAD
0A5010203262001215820D9F4C2A352136F19C9A95DA8824AB5CDC4D5631EBCFD5BDBB0BFFF2536
09129E225820EF404B880765576007888A3ED6ABFFB4257B7123553325D450613CB5BC9A3A52
```

## Supported types

### Supported types by decoder

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

### Supported types by encoder

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
