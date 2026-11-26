# zbor - Zig CBOR

The Concise Binary Object Representation (CBOR) is a data format whose design 
goals include the possibility of extremely small code size, fairly small 
message size, and extensibility without the need for version negotiation
([RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#abstract)). It is used
in different protocols like the Client to Authenticator Protocol 
[CTAP2](https://fidoalliance.org/specs/fido-v2.0-ps-20190130/fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-canonical-cbor-encoding-form) 
which is a essential part of FIDO2 authenticators/ Passkeys.

Versions
| Zig version | zbor version | fetch command |
|:-----------:|:------------:|:-------------:|
| 0.13.0      | 0.15 | |
| 0.14.x      | 0.16.x, 0.17.x, 0.18.x | |
| 0.15.x      | 0.19.0, 0.20.0 | |
| 0.16.x      | 0.21.x | `zig fetch --save https://codeberg.org/r4gus/zbor/archive/0.21.0.tar.gz` |
| 0.17.x      | 0.22.0, 0.23.0 | `zig fetch --save https://codeberg.org/r4gus/zbor/archive/0.23.0.tar.gz` |
| 0.17.x      | 1.0.0-alpha | |

## Getting started

To get started, first add this library as a dependency to your `build.zig.zon` file.
You can do this using the `zig fetch` command.

To fetch a specific release, use the following command. You can replace the
version (e.g., `0.23.0`) with the version you'd like to fetch. You can find 
a list of all available versions on the releases page.
```bash
zig fetch --save https://codeberg.org/r4gus/zbor/archive/0.23.0.tar.gz
```

Alternatively, you can also just fetch the current master using the following command.

```bash
zig fetch --save git+https://codeberg.org/r4gus/zbor
```

After you have fetched `zbor` as a dependency, add the following to your `build.zig`.

```zig
// First fetch the dependency...
const zbor_dep = b.dependency("zbor", .{
    .target = target,
    .optimize = optimize,
});
const zbor_module = zbor_dep.module("zbor");

// If you have a module that has zbor as a dependency...
const your_module = b.addModule("your-module", .{
    .root_source_file = .{ .path = "src/main.zig" },
    .imports = &.{
        .{ .name = "zbor", .module = zbor_module },
    },
});

// Or as a dependency for a executable...
exe.root_module.addImport("zbor", zbor_module);
```

## Usage

This package allows you to de-/serialize CBOR data items. The whole API is centered around Zigs `std.Io.Reader` and `std.Io.Writer`.

### Deserialization

Given a instance `r` of `std.Io.Reader`, you can start deserializing raw CBOR 
data by first calling `zbor.DataItem.new()` passing `r` as an argument.

```zig
const cbor = @import("zbor");

// ...
// assuming `r` of type `std.Io.Reader`

var di = try cbor.DataItem.new(&r);
```

This will return a new instance of type `DataItem`. By calling `DataItem.new()`, the
function will initially only read the head of the data item (up to 9 bytes) from the 
`Reader`. If not enough bytes are available, the function will return 
`error.EndOfStream`.

> All methods you call on a instance of `DataItem` will return `error.EndOfStream`
> if not enough data is available.

After you have created a new instance of `DataItem` by calling `new()`, you can
invoke a set of methods to inspect the data item. Some of them will advance
the reader if necessary, meaning read more data.

#### Deserialization Primitives

Overall, the following primitives are available to decode CBOR data items.

- `getMajorType()`: get the `DataItem.MajorType` (unsigned int, int, byte string, text string, array, map, tag, float/ simple value).
- `getHeaderLength()`: get the length of the header in bytes.
- `getType()`: get more detailed info (`DataItem.Type`) about the given data item. Types are:
    - `Int`
    - `ByteString`
    - `TextString`
    - `Array`
    - `ArrayIndef`
    - `Map`
    - `MapIndef`
    - `False`
    - `True`
    - `Null`
    - `Undefined`
    - `Simple`
    - `Tagged`
    - `Float`
    - `Break`
- `getAdditionalInformation()`: get the lower 5 bytes of the first byte of the head.
- `getArgumentValue()`: get the numeric value (`u64`) that follows the initial byte of the head.
- `getUInt()`: decode the given data item as `u64` (major type 0)
- `getInt()`: decode the given data item as `i65` (major type 1)
- `isF16`, `isF32`, `isF64`: check if the given data item is a IEEE 754 half-, single-, or double-precision float.
- `getF16()`, `getF32()`, `getF64()`: decode the given data item as half-, single-, or double-precision float.
- `isFloat()`: returns `true` if the given data item is a half-, single-, or double-precision float, `false` otherwise.
- `getFloat()`: decode the given data item as float, always returning a `f64`.
- `getStringSlice()`: decode a CBOR text or byte string into a `u8` slice. Use `getLength()` to obtain the length of the text or byte string.
- `getStringSliceStrict()`: decode a CBOR text or byte string into a `u8` slice. This method enforces that the buffer is completely filled. Returns `error.EndOfStream` if the actual length of the CBOR string is less than the size of the buffer.
- `getStringAlloc()`: decode a CBOR text or byte string into a `u8` slice. The caller owns the memory allocated for the returned slice.
- `isIndef()`: check if the given data item is indefinite.
- `isBreakCode()`: check if the given data item is a break marker for a indefinite data item.
- `next()`: read a new data item from the `Reader`
- `toOwnedSlice()`: write the current data item into a slice. The caller owns the slice returned by this method.

For example, to decode the number 1000 (CBOR: `\x19\x03\xe8`) into a `u64`, you
can use the following code snippet:

```zig
const std = @import("std");
const cbor = @import("zbor");

var reader = std.Io.Reader.fixed("\x19\x03\xe8");
var di = try cbor.DataItem.new(&reader);

const i = try di.getUInt();
```

To parse an array, you can use something like the following:

```zig
var reader = std.Io.Reader.fixed("\x85\x01\x02\x03\x04\x05");
var di = try Self.new(&reader);

// if (di.getMajorType() != .Array)
//     do something...

var x: [5]u8 = @splat(0);

var i: usize = 0;
while (i < 5) : (i += 1) {
    const child = try di.next();
    x[i] = @intCast(try child.getUInt());
}
```

The approach of using `next()` in a loop also works for parsing maps, with the only
difference that you have to call `next()` twice during each iteration. Once for the
key and once for the value. If you're working with indefinite length arrays and maps,
you can check for a break code using `isBreakCode()`.

There is also a convenience method `decode()` which makes is quite easy
to deserialize data items into instances of Zig data types. We're going
to look at `decode()` in the following subsection.

#### `decode()`

The method `decode()` is called on a instance of `DataItem`. It expects a
Zig data type as an argument and tries to deserialize the given CBOR data item
into a instance of the specified type.

For example, to decode the number -998877 (CBOR: `\x3a\x00\x0f\x3d\xdc`) into a `i65`, you can use the following code snippet:

```zig
const std = @import("std");
const cbor = @import("zbor");

var reader = std.Io.Reader.fixed("\x3a\x00\x0f\x3d\xdc");
var di = try cbor.DataItem.new(&reader);

const i = try di.decode(i65, .{})
```

As already said, the first argument to `decode()` is the type you want to decode
the data item to, which is a `i65` in the example given above. The second argument
are options of type `DecodeOptions`.

Via the options argument, you can pass a `std.mem.Allocator` to `decode()` and also 
configure the maximum recursion depth (128 by default). The allocator option is 
for example relevant if you want to decode a data item into a slice, as `decode()`
needs a way to dynamically allocate memory if necessary.

The `decode()` method comes in handy, if you need to deserialize more complex
types but don't want to write out the parsing logic yourself (we get to how to
configure `decode()` and also overwrite its behavior in a bit).

A little bit more complex example would be the following:

```zig
const std = @import("std");
const cbor = @import("zbor");
const allocator = std.testing.allocator;

const Info = struct {
    @"1": []const []const u8,
    @"2": []const []const u8,
    @"3": []const u8,
    @"4": struct {
        plat: bool,
        rk: bool,
        clientPin: ?bool,
        up: bool,
        uv: ?bool,
    },
    @"5": ?u64,
    @"6": ?[]const u64,
};

var reader = std.Io.Reader.fixed("\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4");
var di = try cbor.DataItem.new(&reader);

const i = try di.decode(Info, .{ .allocator = allocator });
// don't forget to free the allocated memory afterwards!
```

As you see, this time we pass an allocator to `deocde()` as `Info` contains multiple
slices which require allocating dynamic memory for decoding.

I encourage you to read through the test cases in `src/DataItem.zig` to get a better
understanding of how to use `decode()` for more complex scenarios.

##### Configuring the behavior of `decode()`

Sometimes, e.g., when working with the CTAP2 standard, you need more configuration
options regarding the correct serialization and deserialization of CBOR data. By
default, zbor supports different paths for deserializing data when using the 
`decode()` method. 

For example, when deserializing CBOR data into a `enum` value, `decode()` 
can automatically deserializes the data from either a numeric or string value.

One specific example where `decode()` needs more information to work with is, when
the field names of a `struct` don't match the keys of CBOR map, which has
to be decoded into a instance of that struct. For `struct`s you can pass those 
settings to `deocde()` by adding a function with the following signature to 
your `struct`: `pub fn cborSettings() Settings`

```zig
const std = @import("std");
const cbor = @import("zbor");

const EcdsaP256Key = struct {
    /// kty:
    kty: u8 = 2,
    /// alg:
    alg: i8 = -7,
    /// crv:
    crv: u8 = 1,
    /// x-coordinate
    x: [32]u8,
    /// y-coordinate
    y: [32]u8,

    pub fn cborSettings() Settings {
        return .{
            .field_settings = &.{
                .{ .name = "kty", .field_options = .{ .alias = "1", .serialization_type = .Integer } },
                .{ .name = "alg", .field_options = .{ .alias = "3", .serialization_type = .Integer } },
                .{ .name = "crv", .field_options = .{ .alias = "-1", .serialization_type = .Integer } },
                .{ .name = "x", .field_options = .{ .alias = "-2", .serialization_type = .Integer } },
                .{ .name = "y", .field_options = .{ .alias = "-3", .serialization_type = .Integer } },
            },
        };
    }
};

var r = std.Io.Reader.fixed("\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
var di = try cbor.DataItem.new(&r);

const x = try di.decode(EcdsaP256Key, .{});
```

Via `Settings` you can configure the behavior when de-/serializing instances
of `structs` from or into raw CBOR data. While this is mostly needed when
using `encode()`, one exception is, like already mentioned, to use different
keys (e.g., integers) instead of the default field names.

In the example given above, we assign aliases to field names and also tell 
`decode()` to de-/serialize those aliases from/ into integers. This way we
reduce the size of the raw CBOR data. For example, `kty` gets the alias `1`, `alg`
the alias `3` and so on.

Except for cases like this, you usually don't have to define `cborSettings()`
for decoding CBOR data using `decode()`.

If you're working with a `struct` and need full control over the deserialization but
also want to use the `decode()` method, you can overload `decode()`s behavior 
by defining a function `pub fn cborDecode(self: DataItem, options: DecodeOptions) T`, replacing `T` with the name of your `struct`. Please be aware that you're not allowed to
call `decode()` from within `cborDecode()`, otherwise you're going to create a
infinite loop.

Defining `cborDecode()` is for example relevant, if some CBOR map keys are overloaded and you need to decide, e.g., based on other already seen key-value pairs, how to decode the upcoming key-pairs.

### Serialization

Given a instance `w` of `std.Io.Writer`, you can start serializing Zig objects into 
CBOR data using the following functions: 

- `writeInt()`: serialize a `i65` integer into CBOR. This function will automatically use the smallest representation possible for the numeric value, serializing it either as major type 0 (unsigned integer) or major type 1 (signed integer).
- `writeByteString()`: serialize a `u8` slice as byte string (major type 2).
- `writeTextString()`: serialize a `u8` slice as text string (major type 3).
- `writeTag()`: serialize a [CBOR tag](https://www.rfc-editor.org/rfc/rfc8949.html#name-tagging-of-items). Calling this method has to be followed by another write call, serializing a additional data item enclosed by the tag.
- `writeSimple()`: serialize a simple value.
- `writeTrue()`: serialize `true`.
- `writeFalse()`: serialize `false`.
- `writeFloat()`: serialize a `f16`, `f32` or `f64`.
- `writeArray()`: start creating a CBOR array. After calling `writeArray` you have to serialize exactly `len` data items, where `len` is the length of the array you passed to `writeArray`.
- `writeArrayIndef()`: start creating a indefinite array. This has to be closed with a call to `writeIndefBreak()`.
- `writeMap()`: start creating a CBOR map. After calling `writeMap` you have to serialize exactly `2 * len` data items, where `len` is the length of the map you passed to `writeMap`.
- `writeMapIndef()`: start creating a indefinite map. This has to be closed with a call to `writeIndefBreak()`.

Alternatively, you can use the `encode()` function.

#### `encode()`

Encoding a Zig object is straight forward.

```zig
const S = struct {
    Fun: bool,
    Amt: i16,
};

const s = S{
    .Fun = true,
    .Amt = -2,
};

var arr = std.Io.Writer.Allocating.init(allocator);
defer arr.deinit();

try encode(
    &arr.writer,
    s,
    .{
        .map_serialization_type = .MapIndefinite,
    },
);
```

Encoding the object `s` will result in the following raw CBOR data: `\xbf\x63\x46\x75\x6e\xf5\x63\x41\x6d\x74\x21\xff`.

As with `decode()` you can also influence the behavior of `encode()` by defining the `cborSettings()` function.

You can also handle the encoding yourself, by defining `cborEncode()` (see one of the examples, e.g., in `src/cose.zig`). If you define `cborEncode()` for a struct or enum, `encode()` will hand of the encoding to the defined method.

