const std = @import("std");
const Allocator = std.mem.Allocator;

const cbor = @import("cbor.zig");
const Error = cbor.Error;
const Type = cbor.Type;
const DataItem = cbor.DataItem;
const Tag = cbor.Tag;
const Pair = cbor.Pair;
const MapIterator = cbor.MapIterator;
const ArrayIterator = cbor.ArrayIterator;
const unsigned_16 = cbor.unsigned_16;
const unsigned_32 = cbor.unsigned_32;
const unsigned_64 = cbor.unsigned_64;
const encode_2 = cbor.encode_2;
const encode_4 = cbor.encode_4;
const encode_8 = cbor.encode_8;

pub const ParseError = error{
    UnsupportedType,
    UnexpectedItem,
    UnexpectedItemValue,
    InvalidKeyType,
    InvalidEnumTag,
    DuplicateCborField,
    UnknownField,
    MissingField,
    AllocatorRequired,
    Overflow,
    OutOfMemory,
    Malformed,
    NoUnionMemberMatched,
};

pub const StringifyError = error{
    UnsupportedItem,
    OutOfMemory,
    InvalidPairCount,
};

/// Options for deserializing CBOR data
pub const ParseOptions = struct {
    /// An allocator required if `parse` needs to allocate memory
    /// for slices and pointers
    allocator: ?Allocator = null,

    /// How to behave if a CBOR map has two or more keys with
    /// the same value
    duplicate_field_behavior: enum {
        /// Use the first one
        UseFirst,
        /// Don't allow duplicates
        Error,
    } = .Error,

    /// Ignore CBOR map keys that were not expected
    ignore_unknown_fields: bool = true,

    /// Settings for specific fields that override the default options.
    /// For `parse`, only the alias option is relevant.
    field_settings: []const FieldSettings = &.{},
    from_cborParse: bool = false,
};

/// Deserialize a CBOR data item into a Zig data structure
pub fn parse(
    /// The type to deserialize to
    comptime T: type,
    /// The data item to deserialize
    item: DataItem,
    /// Options to effect the behaviour of this function
    options: ParseOptions,
) ParseError!T {
    switch (@typeInfo(T)) {
        .Bool => {
            return switch (item.getType()) {
                .False => false,
                .True => true,
                else => ParseError.UnexpectedItem,
            };
        },
        .Float, .ComptimeFloat => {
            return switch (item.getType()) {
                .Float => if (item.float()) |x| @floatCast(T, x) else return ParseError.Malformed,
                else => ParseError.UnexpectedItem,
            };
        },
        .Int, .ComptimeInt => {
            switch (item.getType()) {
                .Int => {
                    const v = if (item.int()) |x| x else return ParseError.Malformed;
                    if (v > std.math.maxInt(T) or v < std.math.minInt(T))
                        return ParseError.Overflow;

                    return @intCast(T, v);
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Optional => |optionalInfo| {
            return switch (item.getType()) {
                .Null, .Undefined => null,
                else => try parse(optionalInfo.child, item, options),
            };
        },
        .Enum => |enumInfo| {
            switch (item.getType()) {
                .Int => {
                    const v = if (item.int()) |x| x else return ParseError.Malformed;
                    return try std.meta.intToEnum(T, v);
                },
                .TextString => {
                    const v = if (item.string()) |x| x else return ParseError.Malformed;
                    inline for (enumInfo.fields) |field| {
                        if (cmp(field.name, v)) {
                            return @field(T, field.name);
                        }
                    }
                    return ParseError.InvalidEnumTag;
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Struct => |structInfo| {
            // Custom parse function overrides default behaviour
            const has_parse = comptime std.meta.trait.hasFn("cborParse")(T);
            if (has_parse and !options.from_cborParse) {
                return T.cborParse(item, options);
            }

            switch (item.getType()) {
                .Map => {
                    var r: T = undefined;
                    var fields_seen = [_]bool{false} ** structInfo.fields.len;

                    var v = if (item.map()) |x| x else return ParseError.Malformed;
                    while (v.next()) |kv| {
                        var found = false;

                        if (kv.key.getType() != .TextString and kv.key.getType() != .Int) continue;

                        inline for (structInfo.fields, 0..) |field, i| {
                            var match: bool = false;
                            var name: []const u8 = field.name;

                            // Is there an alias specified?
                            for (options.field_settings) |fs| {
                                if (std.mem.eql(u8, field.name, fs.name)) {
                                    if (fs.alias) |alias| {
                                        name = alias;
                                    }
                                }
                            }

                            switch (kv.key.getType()) {
                                .Int => {
                                    const x = if (kv.key.int()) |y| y else return ParseError.Malformed;
                                    const y = s2n(name);
                                    match = x == y;
                                },
                                else => {
                                    match = std.mem.eql(u8, name, if (kv.key.string()) |x| x else return ParseError.Malformed);
                                },
                            }

                            if (match) {
                                if (fields_seen[i]) {
                                    switch (options.duplicate_field_behavior) {
                                        .UseFirst => {
                                            found = true;
                                            break;
                                        },
                                        .Error => return ParseError.DuplicateCborField,
                                    }
                                }

                                var child_options = options;
                                child_options.from_cborParse = false;
                                @field(r, field.name) = try parse(
                                    field.type,
                                    kv.value,
                                    child_options,
                                );
                                errdefer {
                                    // TODO: add error defer to free memory
                                    const I = @typeInfo(@TypeOf(@field(r, field.name)));

                                    switch (I) {
                                        .Pointer => |ptrInfo| {
                                            _ = ptrInfo;
                                        },
                                        else => {},
                                    }
                                }

                                fields_seen[i] = true;
                                found = true;
                                break;
                            }
                        }

                        if (!found and !options.ignore_unknown_fields) {
                            return ParseError.UnknownField;
                        }
                    }

                    inline for (structInfo.fields, 0..) |field, i| {
                        if (!fields_seen[i]) {
                            switch (@typeInfo(field.type)) {
                                .Optional => @field(r, field.name) = null,
                                else => {
                                    if (field.default_value) |default_ptr| {
                                        if (!field.is_comptime) {
                                            const default = @ptrCast(*align(1) const field.type, default_ptr).*;
                                            @field(r, field.name) = default;
                                        }
                                    } else {
                                        return ParseError.MissingField;
                                    }
                                },
                            }
                        }
                    }

                    return r;
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Array => |arrayInfo| {
            switch (item.getType()) {
                .Array => {
                    var v = if (item.array()) |x| x else return ParseError.Malformed;
                    var r: T = undefined;
                    var i: usize = 0;

                    while (i < r.len) : (i += 1) {
                        r[i] = try parse(arrayInfo.child, if (v.next()) |x| x else return ParseError.Malformed, options);
                    }

                    return r;
                },
                .ByteString, .TextString => {
                    if (arrayInfo.child != u8) return ParseError.UnexpectedItem;

                    var v = if (item.string()) |x| x else return ParseError.Malformed;
                    var r: T = undefined;

                    if (v.len > r[0..].len) return ParseError.Overflow;
                    std.mem.copy(u8, r[0..v.len], v);

                    return r;
                },
                else => {
                    return ParseError.UnexpectedItem;
                },
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse return ParseError.AllocatorRequired;

            switch (ptrInfo.size) {
                .One => {
                    // We use *ptrInfo.child instead of T to allow const and non-const types
                    const r: *ptrInfo.child = try allocator.create(ptrInfo.child);
                    errdefer allocator.destroy(r);
                    r.* = try parse(ptrInfo.child, item, options);
                    return r;
                },
                .Slice => {
                    switch (item.getType()) {
                        .ByteString, .TextString => {
                            const v = if (item.string()) |x| x else return ParseError.Malformed;
                            if (ptrInfo.child != u8) {
                                return ParseError.UnexpectedItem;
                            }

                            var sentinel: usize = 0;
                            if (ptrInfo.sentinel != null) {
                                sentinel += 1;
                            }

                            var r: []ptrInfo.child = try allocator.alloc(ptrInfo.child, v.len + sentinel);
                            errdefer allocator.free(r);
                            std.mem.copy(ptrInfo.child, r[0..], v[0..]);
                            if (ptrInfo.sentinel) |some| {
                                const sentinel_value = @ptrCast(*align(1) const ptrInfo.child, some).*;
                                r[r.len - 1] = sentinel_value;
                                return r[0 .. r.len - 1 :sentinel_value];
                            }

                            return r;
                        },
                        .Array => {
                            var v = if (item.array()) |x| x else return ParseError.Malformed;
                            var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                            errdefer {
                                // TODO: take care of children
                                arraylist.deinit();
                            }

                            while (v.next()) |elem| {
                                try arraylist.ensureUnusedCapacity(1);
                                const x = try parse(ptrInfo.child, elem, options);
                                arraylist.appendAssumeCapacity(x);
                            }

                            if (ptrInfo.sentinel) |some| {
                                const sentinel_value = @ptrCast(*align(1) const ptrInfo.child, some).*;
                                try arraylist.append(sentinel_value);
                                const output = try arraylist.toOwnedSlice();
                                return output[0 .. output.len - 1 :sentinel_value];
                            }

                            return arraylist.toOwnedSlice();
                        },
                        else => return ParseError.UnexpectedItem,
                    }
                },
                else => return Error.UnsupportedType,
            }
        },
        .Union => |unionInfo| {
            // Custom parse function overrides default behaviour
            const has_parse = comptime std.meta.trait.hasFn("cborParse")(T);
            if (has_parse and !options.from_cborParse) {
                return T.cborParse(item, options);
            }

            if (unionInfo.tag_type) |_| {
                // try each union field until we find one that matches
                inline for (unionInfo.fields) |u_field| {
                    if (parse(u_field.type, item, options)) |value| {
                        return @unionInit(T, u_field.name, value);
                    } else |err| {
                        // Bubble up error.OutOfMemory
                        // Parsing some types won't have OutOfMemory in their
                        // error-sets, for the condition to be valid, merge it in.
                        if (@as(@TypeOf(err) || error{OutOfMemory}, err) == error.OutOfMemory) return err;
                        // Bubble up AllocatorRequired, as it indicates missing option
                        if (@as(@TypeOf(err) || error{AllocatorRequired}, err) == error.AllocatorRequired) return err;
                        // otherwise continue through the `inline for`
                    }
                }
                return ParseError.NoUnionMemberMatched;
            } else {
                @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        else => return Error.UnsupportedType,
    }
}

/// Options to influence the behavior of the stringify function
pub const StringifyOptions = struct {
    /// Struct fields that are null will not be included in the CBOR map.
    skip_null_fields: bool = true,
    /// Convert an u8 slice into a CBOR text string.
    slice_as_text: bool = false,
    /// Use the field name instead of the numerical value to represent a enum.
    enum_as_text: bool = true,
    /// Pass an optional allocator. This might be useful when implementing
    /// a own cborStringify method for a struct or union.
    allocator: ?std.mem.Allocator = null,
    /// Settings for specific fields that override the default options
    field_settings: []const FieldSettings = &.{},
    /// Stringfiy called from cborStringify. This falg is used to prevent infinite recursion:
    /// stringify -> cborStringify -> stringify -> cborStringify -> stringify ...
    from_cborStringify: bool = false,
};

/// Options for a specific field specified by `name`
pub const FieldSettings = struct {
    /// The name of the field
    name: []const u8,
    /// The alternative name of the field
    alias: ?[]const u8 = null,
    /// Options specific for the given field
    options: struct {
        /// Don't serialize the given filed if it's null
        skip_if_null: bool = true,
        /// Convert the field into a CBOR text string (only if u8 slice)
        slice_as_text: bool = false,
        /// Use the field name instead of its numerical value (only if enum)
        enum_as_text: bool = true,
    } = .{},
};

/// Serialize the given value to CBOR
pub fn stringify(
    /// The value to serialize
    value: anytype,
    /// Options to influence the functions behaviour
    options: StringifyOptions,
    /// A writer
    out: anytype,
) StringifyError!void {
    const T = @TypeOf(value);
    const TInf = @typeInfo(T);
    var head: u8 = 0;
    var v: u64 = 0;

    switch (TInf) {
        .Int, .ComptimeInt => {
            head = if (value < 0) 0x20 else 0;
            v = @intCast(u64, if (value < 0) -(value + 1) else value);
            try encode(out, head, v);
            return;
        },
        .Float, .ComptimeFloat => {
            head = 0xe0;
            switch (TInf) {
                .Float => |float| {
                    switch (float.bits) {
                        16 => try encode_2(out, head, @intCast(u64, @bitCast(u16, value))),
                        32 => try encode_4(out, head, @intCast(u64, @bitCast(u32, value))),
                        64 => try encode_8(out, head, @intCast(u64, @bitCast(u64, value))),
                        else => @compileError("Float must be 16, 32 or 64 Bits wide"),
                    }
                    return;
                },
                .ComptimeFloat => {
                    // Comptime floats are always encoded as single precision floats
                    try encode_4(out, head, @intCast(u64, @bitCast(u32, @floatCast(f32, value))));
                    return;
                },
                else => unreachable,
            }
        },
        .Bool, .Null => {
            head = 0xe0;
            v = switch (TInf) {
                .Bool => if (value) 21 else 20,
                .Null => 22,
                else => unreachable,
            };
            try encode(out, head, v);
            return;
        },
        .Array => |arrayInfo| {
            if (arrayInfo.child == u8) {
                const valid_utf8 = std.unicode.utf8ValidateSlice(value[0..]);
                head = if (options.slice_as_text and valid_utf8) 0x60 else 0x40;
            } else {
                head = 0x80;
            }
            v = @intCast(u64, value.len);
            try encode(out, head, v);

            if (arrayInfo.child == u8) {
                try out.writeAll(value[0..]);
            } else {
                for (value) |x| {
                    try stringify(x, options, out);
                }
            }
            return;
        },
        .Struct => |S| {
            // Custom stringify function overrides default behaviour
            const has_stringify = comptime std.meta.trait.hasFn("cborStringify")(T);
            if (has_stringify and !options.from_cborStringify) {
                return value.cborStringify(options, out);
            }

            head = 0xa0; // Struct becomes a Map.

            // Count the number of fields that should be serialized
            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.type == void) continue;

                // dont't include (optional) null fields
                var emit_field = true;
                if (@typeInfo(Field.type) == .Optional) {
                    if (options.skip_null_fields) {
                        if (@field(value, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    v += 1;
                }
            }

            try encode(out, head, v);

            // Now serialize the actual fields
            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.type == void) continue;

                // dont't include (optional) null fields
                var emit_field = true;
                if (@typeInfo(Field.type) == .Optional) {
                    if (options.skip_null_fields) {
                        if (@field(value, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    var child_options = options;
                    // the flag shouldn't have an effect on the children.
                    // It's only purpose is to prevent an infinite loop on the same level.
                    child_options.from_cborStringify = false;
                    var name: []const u8 = Field.name[0..];

                    for (options.field_settings) |fs| {
                        if (std.mem.eql(u8, Field.name, fs.name)) {
                            // We found settings for the given field
                            child_options.skip_null_fields = fs.options.skip_if_null;
                            child_options.slice_as_text = fs.options.slice_as_text;
                            child_options.enum_as_text = fs.options.enum_as_text;

                            if (fs.alias) |alias| {
                                name = alias;
                            }
                        }
                    }

                    if (s2n(name)) |nr| { // int key
                        try stringify(nr, child_options, out); // key
                    } else { // str key
                        child_options.slice_as_text = true;
                        try stringify(name, child_options, out); // key
                    }

                    try stringify(@field(value, Field.name), child_options, out); // value
                }
            }
            return;
        },
        .Optional => {
            if (value) |payload| {
                try stringify(payload, options, out);
                return;
            } else {
                try stringify(null, options, out);
                return;
            }
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .Slice => {
                if (ptr_info.child == u8) {
                    const is_sentinel = ptr_info.sentinel != null;
                    const valid_utf8 = std.unicode.utf8ValidateSlice(value);
                    head = if ((is_sentinel or options.slice_as_text) and valid_utf8) 0x60 else 0x40;
                } else {
                    head = 0x80;
                }

                v = @intCast(u64, value.len);
                try encode(out, head, v);

                if (ptr_info.child == u8) {
                    try out.writeAll(value);
                } else {
                    for (value) |x| {
                        try stringify(x, options, out);
                    }
                }
                return;
            },
            .One => {
                try stringify(value.*, options, out);
                return;
            },
            else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
        },
        .Enum => |enumInfo| {
            head = if (options.enum_as_text) 0x60 else 0;

            if (options.enum_as_text) {
                const tmp = @enumToInt(value);
                inline for (enumInfo.fields) |field| {
                    if (field.value == tmp) {
                        v = @intCast(u64, field.name.len);
                        try encode(out, head, v);
                        try out.writeAll(field.name);
                        return;
                    }
                }
            } else {
                const tmp = @enumToInt(value);
                if (tmp < 0) head = 0x20;
                v = @intCast(u64, if (tmp < 0) -(tmp + 1) else tmp);
                try encode(out, head, v);
                return;
            }
        },
        .Union => {
            const has_stringify = comptime std.meta.trait.hasFn("cborStringify")(T);
            if (has_stringify and !options.from_cborStringify) {
                return value.cborStringify(options, out);
            }

            const info = @typeInfo(T).Union;
            if (info.tag_type) |UnionTagType| {
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try stringify(@field(value, u_field.name), options, out);
                        break;
                    }
                }
                return;
            } else {
                @compileError("Unable to stringify untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        else => {
            return .UnsupportedItem;
        }, // TODO: add remaining options
    }
}

fn s2n(s: []const u8) ?i65 {
    if (s.len < 1) return null;
    const start: usize = if (s[0] == '-') 1 else 0;

    var x: i64 = 0;

    for (s[start..]) |c| {
        if (c > 57 or c < 48) return null;
        x *= 10;
        x += @intCast(i64, c - 48);
    }

    return if (start == 1) -x else x;
}

fn cmp(l: []const u8, r: []const u8) bool {
    if (l.len != r.len) return false;

    var i: usize = 0;
    while (i < l.len) : (i += 1) {
        if (l[i] != r[i]) return false;
    }
    return true;
}

fn encode(out: anytype, head: u8, v: u64) !void {
    switch (v) {
        0x00...0x17 => {
            try out.writeByte(head | @intCast(u8, v));
        },
        0x18...0xff => {
            try out.writeByte(head | 24);
            try out.writeByte(@intCast(u8, v));
        },
        0x0100...0xffff => try cbor.encode_2(out, head, v),
        0x00010000...0xffffffff => try cbor.encode_4(out, head, v),
        0x0000000100000000...0xffffffffffffffff => try cbor.encode_8(out, head, v),
    }
}

fn testStringify(e: []const u8, v: anytype, o: StringifyOptions) !void {
    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try stringify(v, o, str.writer());
    try std.testing.expectEqualSlices(u8, e, str.items);
}

test "parse boolean" {
    const t = try DataItem.new("\xf5");
    const f = try DataItem.new("\xf4");
    const u = try DataItem.new("\xf7");
    const i = try DataItem.new("\x0b");

    try std.testing.expectEqual(true, try parse(bool, t, .{}));
    try std.testing.expectEqual(false, try parse(bool, f, .{}));
    try std.testing.expectError(ParseError.UnexpectedItem, parse(bool, u, .{}));
    try std.testing.expectError(ParseError.UnexpectedItem, parse(bool, i, .{}));
}

test "parse float" {
    const f1 = try DataItem.new("\xfb\x3f\xf1\x99\x99\x99\x99\x99\x9a");
    const f2 = try DataItem.new("\xFB\x40\x1D\x67\x86\xC2\x26\x80\x9D");
    const f3 = try DataItem.new("\xFB\xC0\x28\x1E\xB8\x51\xEB\x85\x1F");

    try std.testing.expectApproxEqRel(try parse(f16, f1, .{}), 1.1, 0.01);
    try std.testing.expectApproxEqRel(try parse(f16, f2, .{}), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f2, .{}), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f3, .{}), -12.06, 0.01);
    try std.testing.expectApproxEqRel(try parse(f64, f3, .{}), -12.06, 0.01);
}

test "stringify float" {
    try testStringify("\xf9\x00\x00", @floatCast(f16, 0.0), .{});
    try testStringify("\xf9\x80\x00", @floatCast(f16, -0.0), .{});
    try testStringify("\xf9\x3c\x00", @floatCast(f16, 1.0), .{});
    try testStringify("\xf9\x3e\x00", @floatCast(f16, 1.5), .{});
    try testStringify("\xf9\x7b\xff", @floatCast(f16, 65504.0), .{});
    try testStringify("\xfa\x47\xc3\x50\x00", @floatCast(f32, 100000.0), .{});
    try testStringify("\xfa\x7f\x7f\xff\xff", @floatCast(f32, 3.4028234663852886e+38), .{});
    try testStringify("\xfb\x7e\x37\xe4\x3c\x88\x00\x75\x9c", @floatCast(f64, 1.0e+300), .{});
    try testStringify("\xfb\xc0\x10\x66\x66\x66\x66\x66\x66", @floatCast(f64, -4.1), .{});

    try testStringify("\xfa\x47\xc3\x50\x00", 100000.0, .{});
}

test "parse int" {
    const i_1 = try DataItem.new("\x18\xff");
    const i_2 = try DataItem.new("\x19\x01\x00");

    try std.testing.expectEqual(try parse(u8, i_1, .{}), 255);
    try std.testing.expectError(ParseError.Overflow, parse(u8, i_2, .{}));
}

test "stringify int" {
    try testStringify("\x00", 0, .{});
    try testStringify("\x01", 1, .{});
    try testStringify("\x0a", 10, .{});
    try testStringify("\x17", 23, .{});
    try testStringify("\x18\x18", 24, .{});
    try testStringify("\x18\x19", 25, .{});
    try testStringify("\x18\x64", 100, .{});
    try testStringify("\x18\x7b", 123, .{});
    try testStringify("\x19\x03\xe8", 1000, .{});
    try testStringify("\x19\x04\xd2", 1234, .{});
    try testStringify("\x1a\x00\x01\xe2\x40", 123456, .{});
    try testStringify("\x1a\x00\x0f\x42\x40", 1000000, .{});
    try testStringify("\x1b\x00\x00\x00\x02\xdf\xdc\x1c\x34", 12345678900, .{});
    try testStringify("\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00", 1000000000000, .{});
    try testStringify("\x1b\xff\xff\xff\xff\xff\xff\xff\xff", 18446744073709551615, .{});

    try testStringify("\x20", -1, .{});
    try testStringify("\x22", -3, .{});
    try testStringify("\x38\x63", -100, .{});
    try testStringify("\x39\x01\xf3", -500, .{});
    try testStringify("\x39\x03\xe7", -1000, .{});
    try testStringify("\x3a\x00\x0f\x3d\xdc", -998877, .{});
    try testStringify("\x3b\x00\x00\x00\x02\x53\x60\xa2\xce", -9988776655, .{});
    try testStringify("\x3b\xff\xff\xff\xff\xff\xff\xff\xff", -18446744073709551616, .{});
}

test "parse struct: 1" {
    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.new("\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");

    const c = try parse(Config, di, .{});

    try std.testing.expectEqual(c.uptime, 9999);
    try std.testing.expectEqual(c.vals.testing, 1);
    try std.testing.expectEqual(c.vals.production, 42);
}

test "parse struct: 2 (optional missing field)" {
    const Config = struct {
        vals: struct { testing: u8, production: ?u8 },
        uptime: u64,
    };

    const di = try DataItem.new("\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");

    const c = try parse(Config, di, .{});

    try std.testing.expectEqual(c.vals.production, null);
}

test "parse struct: 3 (missing field)" {
    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.new("\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");

    try std.testing.expectError(ParseError.MissingField, parse(Config, di, .{}));
}

test "parse struct: 4 (unknown field)" {
    const Config = struct {
        vals: struct { testing: u8 },
        uptime: u64,
    };

    const di = try DataItem.new("\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");

    try std.testing.expectError(ParseError.UnknownField, parse(Config, di, .{ .ignore_unknown_fields = false }));
}

test "parse struct: 7" {
    const allocator = std.testing.allocator;

    const Config = struct {
        @"1": struct { @"1": u8, @"2": u8 },
        @"2": u64,
    };

    const di = try DataItem.new("\xA2\x01\xA2\x01\x01\x02\x18\x2A\x02\x19\x27\x0F");

    const c = try parse(Config, di, .{ .allocator = allocator });

    try std.testing.expectEqual(c.@"2", 9999);
    try std.testing.expectEqual(c.@"1".@"1", 1);
    try std.testing.expectEqual(c.@"1".@"2", 42);
}

test "parse optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try std.testing.expectEqual(e1, try parse(?u32, try DataItem.new("\x19\x04\xD2"), .{}));
    try std.testing.expectEqual(e2, try parse(?u32, try DataItem.new("\xf6"), .{}));
    try std.testing.expectEqual(e2, try parse(?u32, try DataItem.new("\xf7"), .{}));
}

test "stringify optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try testStringify("\xf6", e2, .{});
    try testStringify("\x19\x04\xd2", e1, .{});
}

test "parse array: 1" {
    const e = [5]u8{ 1, 2, 3, 4, 5 };
    const di = try DataItem.new("\x85\x01\x02\x03\x04\x05");

    const x = try parse([5]u8, di, .{});

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "parse array: 2" {
    const e = [5]?u8{ 1, null, 3, null, 5 };
    const di = try DataItem.new("\x85\x01\xF6\x03\xF6\x05");

    const x = try parse([5]?u8, di, .{});

    try std.testing.expectEqualSlices(?u8, e[0..], x[0..]);
}

test "parse pointer" {
    const allocator = std.testing.allocator;

    const e1_1: u32 = 1234;
    const e1: *const u32 = &e1_1;
    const di1 = try DataItem.new("\x19\x04\xD2");
    const c1 = try parse(*const u32, di1, .{ .allocator = allocator });
    defer allocator.destroy(c1);
    try std.testing.expectEqual(e1.*, c1.*);

    var e2_1: u32 = 1234;
    const e2: *u32 = &e2_1;
    const di2 = try DataItem.new("\x19\x04\xD2");
    const c2 = try parse(*u32, di2, .{ .allocator = allocator });
    defer allocator.destroy(c2);
    try std.testing.expectEqual(e2.*, c2.*);
}

test "parse slice" {
    const allocator = std.testing.allocator;

    var e1: []const u8 = &.{ 1, 2, 3, 4, 5 };
    const di1 = try DataItem.new("\x45\x01\x02\x03\x04\x05");
    const c1 = try parse([]const u8, di1, .{ .allocator = allocator });
    defer allocator.free(c1);
    try std.testing.expectEqualSlices(u8, e1, c1);

    var e2 = [5]u8{ 1, 2, 3, 4, 5 };
    const di2 = try DataItem.new("\x45\x01\x02\x03\x04\x05");
    const c2 = try parse([]u8, di2, .{ .allocator = allocator });
    defer allocator.free(c2);
    try std.testing.expectEqualSlices(u8, e2[0..], c2);
}

test "stringify simple value" {
    try testStringify("\xf4", false, .{});
    try testStringify("\xf5", true, .{});
    try testStringify("\xf6", null, .{});
}

test "stringify pointer" {
    const x1: u32 = 1234;
    const x1p: *const u32 = &x1;
    const x2 = -18446744073709551616;
    const x2p = &x2;

    try testStringify("\x19\x04\xd2", x1p, .{});
    try testStringify("\x3b\xff\xff\xff\xff\xff\xff\xff\xff", x2p, .{});
}

test "stringify slice" {
    const s1: [:0]const u8 = "a";
    try testStringify("\x61\x61", s1, .{});

    const s2: [:0]const u8 = "IETF";
    try testStringify("\x64\x49\x45\x54\x46", s2, .{});

    const s3: [:0]const u8 = "\"\\";
    try testStringify("\x62\x22\x5c", s3, .{});

    const b1: []const u8 = &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 };
    try testStringify(&.{ 0x58, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 }, b1, .{ .slice_as_text = false });

    const b2: []const u8 = "\x10\x11\x12\x13\x14";
    try testStringify("\x45\x10\x11\x12\x13\x14", b2, .{ .slice_as_text = false });
}

test "stringify struct: 1" {
    const Info = struct {
        versions: []const [:0]const u8,
    };

    const i = Info{
        .versions = &.{"FIDO_2_0"},
    };

    try testStringify("\xa1\x68\x76\x65\x72\x73\x69\x6f\x6e\x73\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
}

test "stringify struct: 2" {
    const Info = struct {
        @"1": []const [:0]const u8,
    };

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
    };

    try testStringify("\xa1\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
}

test "stringify struct: 3" {
    const Info = struct {
        @"1": []const [:0]const u8,
        @"2": []const [:0]const u8,
        @"3": []const u8,
    };

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
        .@"2" = &.{},
        .@"3" = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    };

    try testStringify("\xa3\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f", i, .{});
}

test "stringify struct: 4" {
    const Info = struct {
        @"1": []const [:0]const u8,
        @"2": []const [:0]const u8,
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

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
        .@"2" = &.{},
        .@"3" = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
        .@"4" = .{
            .plat = true,
            .rk = true,
            .clientPin = null,
            .up = true,
            .uv = false,
        },
        .@"5" = null,
        .@"6" = null,
    };

    try testStringify("\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4", i, .{});
}

test "stringify struct: 5" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const Info = struct {
        x: Level,
        y: Level,
    };

    const x = Info{
        .x = Level.high,
        .y = Level.low,
    };

    try testStringify("\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B", x, .{ .field_settings = &.{.{ .name = "y", .options = .{ .enum_as_text = false } }} });
}

test "parse struct: 5" {
    const allocator = std.testing.allocator;

    const di = try DataItem.new("\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4");

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

    const i = try parse(Info, di, .{ .allocator = allocator });
    defer {
        allocator.free(i.@"1"[0]);
        allocator.free(i.@"1");
        allocator.free(i.@"2");
        allocator.free(i.@"3");
    }

    try std.testing.expectEqualStrings("FIDO_2_0", i.@"1"[0]);
}

test "parse struct: 8" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const Info = struct {
        x: Level,
        y: Level,
    };

    const di = try DataItem.new("\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B");
    const x = try parse(Info, di, .{});

    try std.testing.expectEqual(x.x, Level.high);
    try std.testing.expectEqual(x.y, Level.low);
}

test "stringify enum: 1" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    const high = Level.high;
    const low = Level.low;

    try testStringify("\x07", high, .{ .enum_as_text = false });
    try testStringify("\x0b", low, .{ .enum_as_text = false });
}

test "stringify enum: 2" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try testStringify("\x64\x68\x69\x67\x68", Level.high, .{});
    try testStringify("\x63\x6C\x6F\x77", Level.low, .{});
}

test "stringify enum: 4" {
    const Level = enum(i8) {
        high = -7,
        low = -11,
    };

    try testStringify("\x26", Level.high, .{ .enum_as_text = false });
    try testStringify("\x2a", Level.low, .{ .enum_as_text = false });
}

test "parse enum: 1" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const di1 = try DataItem.new("\x64\x68\x69\x67\x68");
    const di2 = try DataItem.new("\x63\x6C\x6F\x77");

    const x1 = try parse(Level, di1, .{});
    const x2 = try parse(Level, di2, .{});

    try std.testing.expectEqual(Level.high, x1);
    try std.testing.expectEqual(Level.low, x2);
}

test "parse enum: 2" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const di1 = try DataItem.new("\x07");
    const di2 = try DataItem.new("\x0b");

    const x1 = try parse(Level, di1, .{});
    const x2 = try parse(Level, di2, .{});

    try std.testing.expectEqual(Level.high, x1);
    try std.testing.expectEqual(Level.low, x2);
}

test "parse enum: 3" {
    const Level = enum(i8) {
        high = -7,
        low = -11,
    };

    const di1 = try DataItem.new("\x26");
    const di2 = try DataItem.new("\x2a");

    const x1 = try parse(Level, di1, .{});
    const x2 = try parse(Level, di2, .{});

    try std.testing.expectEqual(Level.high, x1);
    try std.testing.expectEqual(Level.low, x2);
}

test "serialize EcdsaP256Key" {
    const EcdsaP256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

    const EcdsaP256Key = struct {
        /// kty:
        @"1": u8 = 2,
        /// alg:
        @"3": i8 = -7,
        /// crv:
        @"-1": u8 = 1,
        /// x-coordinate
        @"-2": [32]u8,
        /// y-coordinate
        @"-3": [32]u8,

        pub fn new(k: EcdsaP256.PublicKey) @This() {
            const xy = k.toUncompressedSec1();
            return .{
                .@"-2" = xy[1..33].*,
                .@"-3" = xy[33..65].*,
            };
        }
    };

    const k = EcdsaP256Key.new(try EcdsaP256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52"));

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try stringify(k, .{}, str.writer());

    try std.testing.expectEqualSlices(u8, "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.items);
}

test "serialize EcdsP256Key using alias" {
    const EcdsaP256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

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

    const k = EcdsaP256Key.new(try EcdsaP256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52"));

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try stringify(k, .{ .field_settings = &.{
        .{ .name = "kty", .alias = "1" },
        .{ .name = "alg", .alias = "3" },
        .{ .name = "crv", .alias = "-1" },
        .{ .name = "x", .alias = "-2" },
        .{ .name = "y", .alias = "-3" },
    } }, str.writer());

    try std.testing.expectEqualSlices(u8, "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.items);
}

test "deserialize EcdsP256Key using alias" {
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
    };

    const di = try DataItem.new("\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");

    const x = try parse(EcdsaP256Key, di, .{ .field_settings = &.{
        .{ .name = "kty", .alias = "1" },
        .{ .name = "alg", .alias = "3" },
        .{ .name = "crv", .alias = "-1" },
        .{ .name = "x", .alias = "-2" },
        .{ .name = "y", .alias = "-3" },
    } });

    try std.testing.expectEqual(@intCast(u8, 2), x.kty);
    try std.testing.expectEqual(@intCast(i8, -7), x.alg);
    try std.testing.expectEqual(@intCast(u8, 1), x.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", &x.x);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", &x.y);
}

test "deserialize EcdsP256Key using alias 2" {
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

    const di = try DataItem.new("\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");

    const x = try parse(EcdsaP256Key, di, .{});

    try std.testing.expectEqual(@intCast(u8, 2), x.kty);
    try std.testing.expectEqual(@intCast(i8, -7), x.alg);
    try std.testing.expectEqual(@intCast(u8, 1), x.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", &x.x);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", &x.y);
}

test "serialize tagged union: 1" {
    const AttStmtTag = enum { none };
    const AttStmt = union(AttStmtTag) {
        none: struct {},
    };

    const a = AttStmt{ .none = .{} };

    try testStringify("\xa0", a, .{});
}

const build = @import("build.zig");

test "overload struct 1" {
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

    const x = Foo{ .y = .{} };
    try testStringify("\xa2\x61\x78\x19\x04\xd2\x61\x79\x58\x19\xa2\x61\x61\x6a\x70\x75\x62\x6c\x69\x63\x2d\x6b\x65\x79\x61\x62\x1b\x11\x22\x33\x44\x55\x66\x77\x88", x, .{});
}

test "parse get assertion request 1" {
    const GetAssertionParam = struct {
        rpId: [:0]const u8,
        clientDataHash: []const u8,
        allowList: ?[]const struct {
            id: []const u8,
            type: [:0]const u8,
            transports: ?[]const [:0]const u8 = null,
        } = null,
        options: ?struct {
            up: bool = true,
            rk: bool = true,
            uv: bool = false,
        } = null,
        pinUvAuthParam: ?[32]u8 = null,
        pinUvAuthProtocol: ?u8 = null,

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.rpId);
            allocator.free(self.clientDataHash);
            if (self.allowList) |pkcds| {
                for (pkcds) |pkcd| {
                    allocator.free(pkcd.id);
                    allocator.free(pkcd.type);
                    if (pkcd.transports) |trans| {
                        for (trans) |t| {
                            allocator.free(t);
                        }
                        allocator.free(trans);
                    }
                }
                allocator.free(pkcds);
            }
        }
    };

    const allocator = std.testing.allocator;

    const payload = "\xa6\x01\x6b\x77\x65\x62\x61\x75\x74\x68\x6e\x2e\x69\x6f\x02\x58\x20\x6e\x0c\xb5\xf9\x7c\xae\xb8\xbf\x79\x7a\x62\x14\xc7\x19\x1c\x80\x8f\xe5\xa5\x50\x21\xf9\xfb\x76\x6e\x81\x83\xcd\x8a\x0d\x55\x0b\x03\x81\xa2\x62\x69\x64\x58\x40\xf9\xff\xff\xff\x95\xea\x72\x74\x2f\xa6\x03\xc3\x51\x9f\x9c\x17\xc0\xff\x81\xc4\x5d\xbb\x46\xe2\x3c\xff\x6f\xc1\xd0\xd5\xb3\x64\x6d\x49\x5c\xb1\x1b\x80\xe5\x78\x88\xbf\xba\xe3\x89\x8d\x69\x85\xfc\x19\x6c\x43\xfd\xfc\x2e\x80\x18\xac\x2d\x5b\xb3\x79\xa1\xf0\x64\x74\x79\x70\x65\x6a\x70\x75\x62\x6c\x69\x63\x2d\x6b\x65\x79\x05\xa1\x62\x75\x70\xf4\x06\x58\x20\x30\x5b\x38\x2d\x1c\xd9\xb9\x71\x4d\x51\x98\x30\xe5\xb0\x02\xcb\x6c\x38\x25\xbc\x05\xf8\x7e\xf1\xbc\xda\x36\x4d\x2d\x4d\xb9\x10\x07\x02";

    const di = try DataItem.new(payload);

    const get_assertion_param = try parse(
        GetAssertionParam,
        di,
        .{
            .allocator = allocator,
            .field_settings = &.{
                .{ .name = "rpId", .alias = "1", .options = .{} },
                .{ .name = "clientDataHash", .alias = "2", .options = .{} },
                .{ .name = "allowList", .alias = "3", .options = .{} },
                .{ .name = "options", .alias = "5", .options = .{} },
                .{ .name = "pinUvAuthParam", .alias = "6", .options = .{} },
                .{ .name = "pinUvAuthProtocol", .alias = "7", .options = .{} },
            },
        },
    );
    defer get_assertion_param.deinit(allocator);

    try std.testing.expectEqual(false, get_assertion_param.options.?.up);
}
