# zbor - Zig CBOR

![GitHub](https://img.shields.io/github/license/r4gus/zbor?style=flat-square)
![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/r4gus/zbor/main.yml?style=flat-square)
![GitHub all releases](https://img.shields.io/github/downloads/r4gus/zbor/total?style=flat-square)

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

To use this library you can either add it directly as a module or use the
Zig package manager to fetchi it as dependency.

### Zig package manager

First add this library as dependency to your `build.zig.zon` file:

```zon
.{
    .name = "your-project",
    .version = 0.0.1,

    .dependencies = .{
        .zbor = .{
            .url = "https://github.com/r4gus/zbor/archive/master.tar.gz",
            .hash = "1220bfd0526e76937238e2268ea69e97de6b79744d934e4fabd98e0d6e7a8d8e4740",
        }
    },
}
```

then within you `build.zig` add the following code:

```zig
const zbor_dep = b.dependency("zbor", .{
    .target = target,
    .optimize = optimize,
});
const zbor_module = zbor_dep.module("zbor");

// If you have a module that has zbor as a dependency:
const your_module = b.addModule("your-module", .{
    .source_file = .{ .path = "src/main.zig" },
    .dependencies = &.{
        .{ .name = "zbor", .module = zbor_module },
    },
});

// Or as a dependency for a executable:
exe.addModule("zbor", zbor_module);
```

#### Hash

The easiest way to get the required hash is to use a wrong one and then copy the correct one
from the error message.

### As a module

First add the library to your project, e.g., as a submodule:

```
your-project$ mkdir libs
your-project$ git submodule add https://github.com/r4gus/zbor.git libs/zbor
```

Then add the following line to your `build.zig` file.

```zig
// Create a new module
var zbor_module = b.createModule(.{
    .source_file = .{ .path = "libs/zbor/src/main.zig" },
});

// create your exe ...

// Add the module to your exe/ lib
exe.addModule("zbor", zbor_module);
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
var str = std.ArrayList(u8).init(allocator);
defer str.deinit();

const Info = struct {
    versions: []const []const u8,
};

const i = Info{
    .versions = &.{"FIDO_2_0"},
};

try stringify(i, .{}, str.writer());
```

> Note: Compile time floats are always encoded as single precision floats (f32). Please use `@floatCast`
> before passing a float to `stringify()`.

`u8`slices with sentinel terminator (e.g. `const x: [:0] = "FIDO_2_0"`) are treated as text strings and
`u8` slices without sentinel terminator as byte strings.

##### Stringify Options

You can pass options to the `stringify` function to influence its behaviour.

This includes:

* `allocator` - The allocator to be used (if necessary)
* `skip_null_fields` - Struct fields that are null will not be included in the CBOR map (default is `true`)
* `slice_as_text` - Convert an u8 slice into a CBOR text string (default is `false`)
* `enum_as_text`- Use the field name instead of the numerical value to represent a enum (default is `true`)
* `field_settings` - Lets you influence how `stringify` treats specific fileds. The settings set using `field_settings` override the default settings.
* `from_cborStringify` - Flag to break infinity loops (see Overriding stringfy)

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
* `duplicate_field_behavior` - How to handle duplicate fields (`.UseFirst`, `.Error`)
* `ignore_unknown_fields` - Ignore unknown fields (default is `true`)
* `field_settings` - Lets you specify aliases for struct fields
* `from_cborParse` - Flag to break infinity loops (see Overriding parse)

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

    pub fn cborStringify(self: *const @This(), options: StringifyOptions, out: anytype) !void {

        // First stringify the 'y' struct
        const allocator = std.testing.allocator;
        var o = std.ArrayList(u8).init(allocator);
        defer o.deinit();
        try stringify(self.y, options, o.writer());

        // Then use the Builder to alter the CBOR output
        var b = try build.Builder.withType(allocator, .Map);
        try b.pushTextString("x");
        try b.pushInt(self.x);
        try b.pushTextString("y");
        try b.pushByteString(o.items);
        const x = try b.finish();
        defer allocator.free(x);

        try out.writeAll(x);
    }
};
```

The `StringifyOptions` can be used to indirectly pass an `Allocator` to the function.

Please make sure to set `from_cborStringify` to `true` when calling recursively into `stringify(self)` to prevent infinite loops.

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

    pub fn cborParse(item: DataItem, options: ParseOptions) !@This() {
        _ = options;
        return try parse(@This(), item, .{
            .from_cborParse = true, // prevent infinite loops
            .field_settings = &.{
                .{ .name = "kty", .alias = "1" },
                .{ .name = "alg", .alias = "3" },
                .{ .name = "crv", .alias = "-1" },
                .{ .name = "x", .alias = "-2" },
                .{ .name = "y", .alias = "-3" },
            },
        });
    }
};
```

The `ParseOptions` can be used to indirectly pass an `Allocator` to the function.

Please make sure to set `from_cborParse` to `true` when calling recursively into `parse(self)` to prevent infinite loops.

#### Structs with fields of type `std.mem.Allocator`

If you have a struct with a field of type `std.mem.Allocator` you have to override the `stringify` 
funcation for that struct, e.g.:

```zig
pub fn cborStringify(self: *const @This(), options: cbor.StringifyOptions, out: anytype) !void {
    _ = options;

    try cbor.stringify(self, .{
        .from_cborStringify = true,
        .field_settings = &.{
            .{ .name = "allocator", .options = .{ .skip = true } },
        },
    }, out);
}
```

When using `parse` make sure you pass a allocator to the function. The passed allocator will be assigned
to the field of type `std.mem.Allocator`.
