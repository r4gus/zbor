# zbor - Zig CBOR

![GitHub](https://img.shields.io/github/license/r4gus/zbor?style=flat-square)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/r4gus/zbor/main.yml?style=flat-square)
![GitHub all releases](https://img.shields.io/github/downloads/r4gus/zbor/total?style=flat-square)
<noscript><a href="https://liberapay.com/r4gus/donate"><img alt="Donate using Liberapay" src="https://liberapay.com/assets/widgets/donate.svg"></a></noscript>

The Concise Binary Object Representation (CBOR) is a data format whose design 
goals include the possibility of extremely small code size, fairly small 
message size, and extensibility without the need for version negotiation
([RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#abstract)). It is used
in different protocols like the Client to Authenticator Protocol 
[CTAP2](https://fidoalliance.org/specs/fido-v2.0-ps-20190130/fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-canonical-cbor-encoding-form) 
which is a essential part of FIDO2 authenticators/ Passkeys.

I have utilized this library in several projects throughout the previous year, primarily in conjunction with my [FIDO2 library](https://github.com/r4gus/fido2). I'd consider it stable. 
With the introduction of [Zig version `0.11.0`](https://ziglang.org/download/), this library will remain aligned with the most recent stable release. If you have any problems or want
to share some ideas feel free to open an issue or write me a mail, but please be kind.

## Getting started

Versions
| Zig version | zbor version |
|:-----------:|:------------:|
| 0.13.0      | 0.15 |
| 0.14.x      | 0.16.x, 0.17.x, 0.18.x |
| 0.15.x      | 0.19.0, 0.20.0 |

First add this library as a dependency to your `build.zig.zon` file:

```bash
# Replace <VERSION TAG> with the version you want to use
zig fetch --save https://github.com/r4gus/zbor/archive/refs/tags/<VERSION TAG>.tar.gz
```

then within you `build.zig` add the following code:

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

This library lets you inspect and parse CBOR data without having to allocate
additional memory.

### Inspect CBOR data

To inspect CBOR data you must first create a new `DataItem`.

```zig
const cbor = @import("zbor");

const di = DataItem.new("\x1b\xff\xff\xff\xff\xff\xff\xff\xff") catch {
    // handle the case that the given data is malformed
};
```

`DataItem.new()` will check if the given data is well-formed before returning a `DataItem`. The data is well formed if it's syntactically correct. 

To check the type of the given `DataItem` use the `getType()` function.

```zig
std.debug.assert(di.getType() == .Int);
```

Possible types include `Int` (major type 0 and 1) `ByteString` (major type 2), `TextString` (major type 3), `Array` (major type 4), `Map` (major type 5), `Tagged` (major type 6) and `Float` (major type 7).

Based on the given type you can the access the underlying value.

```zig
std.debug.assert(di.int().? == 18446744073709551615);
```

All getter functions return either a value or `null`. You can use a pattern like `if (di.int()) |v| v else return error.Oops;` to access the value in a safe way. If you've used `DataItem.new()` and know the type of the data item, you should be safe to just do `di.int().?`.

The following getter functions are supported:
* `int` - returns `?i65`
* `string` - returns `?[]const u8`
* `array` - returns `?ArrayIterator`
* `map` - returns `?MapIterator`
* `simple` - returns `?u8`
* `float` - returns `?f64`
* `tagged` - returns `?Tag`
* `boolean` - returns `?bool`

#### Iterators

The functions `array` and `map` will return an iterator. Every time you
call `next()` you will either get a `DataItem`/ `Pair` or `null`.

```zig
const di = DataItem.new("\x98\x19\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19");

var iter = di.array().?;
while (iter.next()) |value| {
  _ = value;
  // doe something
}
```

### Encoding and decoding

#### Serialization

You can serialize Zig objects into CBOR using the `stringify()` function.

```zig
const allocator = std.testing.allocator;
var str = std.Io.Writer.Allocating.init(allocator);
defer str.deinit();

const Info = struct {
    versions: []const []const u8,
};

const i = Info{
    .versions = &.{"FIDO_2_0"},
};

try stringify(i, .{}, &str.writer);
```

> Note: Compile time floats are always encoded as single precision floats (f32). Please use `@floatCast`
> before passing a float to `stringify()`.

The `stringify()` function is convenient but also adds extra overhead. If you want full control
over the serialization process you can use the following functions defined in `zbor.build`: `writeInt`,
`writeByteString`, `writeTextString`, `writeTag`, `writeSimple`, `writeArray`, `writeMap`. For more
details check out the [manual serialization example](examples/manual_serialization.zig) and the
corresponding [source code](src/builder.zig).

##### Stringify Options

You can pass options to the `stringify` function to influence its behavior. Without passing any
options, `stringify` will behave as follows:

* Enums will be serialized to their textual representation
* `u8` slices will be serialized to byte strings
* For structs and unions:
    * `null` fields are skipped by default
    * fields of type `std.mem.Allocator` are always skipped.
    * the names of fields are serialized to text strings

You can modify that behavior by changing the default options, e.g.:

```zig
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

    pub fn new(k: EcdsaP256.PublicKey) @This() {                                                                                                                                         
        const xy = k.toUncompressedSec1();
        return .{
            .x = xy[1..33].*,
            .y = xy[33..65].*,
        };
    }
};

//...

try stringify(k, .{ .field_settings = &.{
    .{ .name = "kty", .field_options = .{ .alias = "1", .serialization_type = .Integer } },
    .{ .name = "alg", .field_options = .{ .alias = "3", .serialization_type = .Integer } },
    .{ .name = "crv", .field_options = .{ .alias = "-1", .serialization_type = .Integer } },
    .{ .name = "x", .field_options = .{ .alias = "-2", .serialization_type = .Integer } },
    .{ .name = "y", .field_options = .{ .alias = "-3", .serialization_type = .Integer } },
} }, &str.writer);
```

Here we define a alias for every field of the struct and tell `serialize` that it should treat
those aliases as integers instead of text strings.

__See `Options` and `FieldSettings` in `src/parse.zig` for all available options!__

#### Deserialization

You can deserialize CBOR data into Zig objects using the `parse()` function.

```zig
const e = [5]u8{ 1, 2, 3, 4, 5 };
const di = DataItem.new("\x85\x01\x02\x03\x04\x05");

const x = try parse([5]u8, di, .{});

try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
```

##### Parse Options

You can pass options to the `parse` function to influence its behaviour.

This includes:

* `allocator` - The allocator to be used. This is required if your data type has any pointers, slices, etc.
* `duplicate_field_behavior` - How to handle duplicate fields (`.UseFirst`, `.Error`).
    * `.UseFirst` - Use the first field.
    * `.Error` - Return an error if there are multiple fields with the same name.
* `ignore_unknown_fields` - Ignore unknown fields (default is `true`).
* `field_settings` - Lets you specify aliases for struct fields. Examples on how to use `field_settings` can be found in the _examples_ directory and within defined tests.
* `ignore_override` - Flag to break infinity loops. This has to be set to `true` if you override the behavior using `cborParse` or `cborStringify`.

#### Builder

You can also dynamically create CBOR data using the `Builder`.

```zig
const allocator = std.testing.allocator;

var b = try Builder.withType(allocator, .Map);
try b.pushTextString("a");
try b.pushInt(1);
try b.pushTextString("b");
try b.enter(.Array);
try b.pushInt(2);
try b.pushInt(3);
//try b.leave();            <-- you can leave out the return at the end
const x = try b.finish();
defer allocator.free(x);

// { "a": 1, "b": [2, 3] }
try std.testing.expectEqualSlices(u8, "\xa2\x61\x61\x01\x61\x62\x82\x02\x03", x);
```

##### Commands

- The `push*` functions append a data item
- The `enter` function takes a container type and pushes it on the builder stack
- The `leave` function leaves the current container. The container is appended to the wrapping container
- The `finish` function returns the CBOR data as owned slice

#### Overriding stringify

You can override the `stringify` function for structs and tagged unions by implementing `cborStringify`.

```zig
const Foo = struct {
    x: u32 = 1234,
    y: struct {
        a: []const u8 = "public-key",
        b: u64 = 0x1122334455667788,
    },

    pub fn cborStringify(self: *const @This(), options: Options, out: *std.Io.Writer) !void {

        // First stringify the 'y' struct
        const allocator = std.testing.allocator;
        var o = std.Io.Writer.Allocating.init(allocator);
        defer o.deinit();
        try stringify(self.y, options, &o.writer);

        // Then use the Builder to alter the CBOR output
        var b = try build.Builder.withType(allocator, .Map);
        try b.pushTextString("x");
        try b.pushInt(self.x);
        try b.pushTextString("y");
        try b.pushByteString(o.written());
        const x = try b.finish();
        defer allocator.free(x);

        try out.writeAll(x);
    }
};
```

The `StringifyOptions` can be used to indirectly pass an `Allocator` to the function.

Please make sure to set `ignore_override` to `true` when calling recursively into `stringify(self)` to prevent infinite loops.

#### Overriding parse

You can override the `parse` function for structs and tagged unions by implementing `cborParse`. This is helpful if you have aliases for your struct members.

```zig
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

    pub fn cborParse(item: DataItem, options: Options) !@This() {
        _ = options;
        return try parse(@This(), item, .{
            .ignore_override = true, // prevent infinite loops
            .field_settings = &.{
                .{ .name = "kty", .field_options = .{ .alias = "1" } },
                .{ .name = "alg", .field_options = .{ .alias = "3" } },
                .{ .name = "crv", .field_options = .{ .alias = "-1" } },
                .{ .name = "x", .field_options = .{ .alias = "-2" } },
                .{ .name = "y", .field_options = .{ .alias = "-3" } },
            },
        });
    }
};
```

The `Options` can be used to indirectly pass an `Allocator` to the function.

Please make sure to set `ignore_override` to `true` when calling recursively into `parse(self)` to prevent infinite loops.

#### Structs with fields of type `std.mem.Allocator`

If you have a struct with a field of type `std.mem.Allocator` you have to override the `stringify` 
funcation for that struct, e.g.:

```zig
pub fn cborStringify(self: *const @This(), options: cbor.StringifyOptions, out: *std.Io.Writer) !void {
    _ = options;

    try cbor.stringify(self, .{
        .ignore_override = true,
        .field_settings = &.{
            .{ .name = "allocator", .options = .{ .skip = true } },
        },
    }, out);
}
```

When using `parse` make sure you pass a allocator to the function. The passed allocator will be assigned
to the field of type `std.mem.Allocator`.

#### Indefinite-length Data Items

CBOR supports the serialization of many container types in two formats, definite and indefinite. For definite-length data items, the length is directly encoded into the data-items header. In contrast, indefinite-length data items are terminated by a break-byte `0xff`.

Zbor currently supports indefinite-length encoding for both arrays and maps. The default serialization type for both types remains definite to support backwards compatibility. One can control the serialization type for arrays and maps via the serialization options. The two fields in question are `array_serialization_type` and `map_serialization_type`.

##### Indefinite-length Arrays

This is an example for serializing a array as indefinite-length map:
```zig
const array = [_]u16{ 500, 2 };

var arr = std.Io.Writer.Allocating.init(allocator);
defer arr.deinit();

try stringify(
    array,
    .{
        .allocator = allocator,
        .array_serialization_type = .ArrayIndefinite,
    },
    &arr.writer,
);
```

For the de-serialization of indefinite-length arrays you don't have to do anything special. The `parse` function will automatically detect the encoding type for you.

##### Indefinite-length Maps

This is an example for serializing a struct as indefinite-length map:
```zig
const allocator = std.testing.allocator;

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

try stringify(
    s,
    .{
        .allocator = allocator,
        .map_serialization_type = .MapIndefinite,
    },
    &arr.writer,
);
```

For the de-serialization of indefinite-length maps you don't have to do anything special. The `parse` function will automatically detect the encoding type for you.

### ArrayBackedSlice

This library offers a convenient function named ArrayBackedSlice, which enables you to create a wrapper for an array of any size and type. This wrapper implements the cborStringify and cborParse methods, allowing it to seamlessly replace slices (e.g., []const u8) with an array.

```zig
test "ArrayBackedSlice test" {
    const allocator = std.testing.allocator;

    const S64B = ArrayBackedSlice(64, u8, .Byte);
    var x = S64B{};
    try x.set("\x01\x02\x03\x04");

    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try stringify(x, .{}, &str.writer);
    try std.testing.expectEqualSlices(u8, "\x44\x01\x02\x03\x04", str.written());

    const di = try DataItem.new(str.written());
    const y = try parse(S64B, di, .{});

    try std.testing.expectEqualSlices(u8, "\x01\x02\x03\x04", y.get());
}
```
