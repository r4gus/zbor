const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("core.zig");
const CborError = core.CborError;
const Pair = core.Pair;
const Tag = core.Tag;
const FloatTag = core.FloatTag;
const Float = core.Float;
const SimpleValue = core.SimpleValue;
const DataItemTag = core.DataItemTag;
const DataItem = core.DataItem;
const decode = @import("decoder.zig").decode;
const encoder = @import("encoder.zig");

pub const ParseError = error{
    UnexpectedItem,
    UnexpectedItemValue,
    InvalidKeyType,
    DuplicateCborField,
    UnknownField,
    MissingField,
    AllocatorRequired,
    Overflow,
    OutOfMemory,
};

pub const StringifyError = error{
    UnsupportedItem,
    OutOfMemory,
};

pub const ParseOptions = struct {
    allocator: ?Allocator = null,

    duplicate_field_behavior: enum {
        UseFirst,
        Error,
    } = .Error,

    ignore_unknown_fields: bool = true,
};

pub fn parse(comptime T: type, item: DataItem, options: ParseOptions) ParseError!T {
    switch (@typeInfo(T)) {
        .Bool => {
            switch (item) {
                .simple => |v| {
                    return switch (v) {
                        SimpleValue.True => true,
                        SimpleValue.False => false,
                        else => ParseError.UnexpectedItemValue,
                    };
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Float, .ComptimeFloat => {
            switch (item) {
                .float => |v| {
                    return switch (v) {
                        .float16 => |x| @floatCast(T, x),
                        .float32 => |x| @floatCast(T, x),
                        .float64 => |x| @floatCast(T, x),
                    };
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Int, .ComptimeInt => {
            switch (item) {
                .int => |v| {
                    if (v > std.math.maxInt(T) or v < std.math.minInt(T))
                        return ParseError.Overflow;

                    return @intCast(T, v);
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Optional => |optionalInfo| {
            switch (item) {
                .simple => |v| {
                    return if (v == SimpleValue.Null or v == SimpleValue.Undefined) null else try parse(optionalInfo.child, item, options);
                },
                else => return try parse(optionalInfo.child, item, options),
            }
        },
        .Struct => |structInfo| {
            switch (item) {
                .map => |v| {
                    var r: T = undefined;
                    var fields_seen = [_]bool{false} ** structInfo.fields.len;

                    for (v) |kv| {
                        var found = false;

                        if (!kv.key.isText() and !kv.key.isInt()) continue;

                        inline for (structInfo.fields) |field, i| {
                            var match: bool = false;

                            if (kv.key.isInt()) {
                                const allocator = options.allocator orelse return ParseError.AllocatorRequired;

                                const x = try std.fmt.allocPrint(allocator, "{d}", .{kv.key.int});
                                defer allocator.free(x);
                                match = std.mem.eql(u8, field.name, x);
                            } else {
                                match = std.mem.eql(u8, field.name, kv.key.text);
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

                                @field(r, field.name) = try parse(field.field_type, kv.value, options);

                                fields_seen[i] = true;
                                found = true;
                                break;
                            }
                        }

                        if (!found and !options.ignore_unknown_fields) {
                            return ParseError.UnknownField;
                        }
                    }

                    inline for (structInfo.fields) |field, i| {
                        if (!fields_seen[i]) {
                            switch (@typeInfo(field.field_type)) {
                                .Optional => @field(r, field.name) = null,
                                else => return ParseError.MissingField,
                            }
                        }
                    }

                    return r;
                },
                else => return ParseError.UnexpectedItem,
            }
        },
        .Array => |arrayInfo| {
            switch (item) {
                .array => |v| {
                    var r: T = undefined;
                    var i: usize = 0;

                    while (i < r.len) : (i += 1) {
                        r[i] = try parse(arrayInfo.child, v[i], options);
                    }

                    return r;
                },
                else => return ParseError.UnexpectedItem,
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
                    switch (item) {
                        .bytes, .text => |v| {
                            if (ptrInfo.child != u8) {
                                return ParseError.UnexpectedItem;
                            }

                            var r: []ptrInfo.child = try allocator.alloc(ptrInfo.child, v.len);
                            errdefer allocator.free(r);
                            std.mem.copy(ptrInfo.child, r[0..], v[0..]);
                            return r;
                        },
                        .array => |v| {
                            var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                            errdefer {
                                // TODO: take care of children
                                arraylist.deinit();
                            }

                            for (v) |elem| {
                                try arraylist.ensureUnusedCapacity(1);
                                const x = try parse(ptrInfo.child, elem, options);
                                arraylist.appendAssumeCapacity(x);
                            }

                            if (ptrInfo.sentinel) |some| {
                                const sentinel_value = @ptrCast(*align(1) const ptrInfo.child, some).*;
                                try arraylist.append(sentinel_value);
                                const output = arraylist.toOwnedSlice();
                                return output[0 .. output.len - 1 :sentinel_value];
                            }

                            return arraylist.toOwnedSlice();
                        },
                        else => return ParseError.UnexpectedItem,
                    }
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub const StringifyOptions = struct {
    skip_null_fields: bool = true,
    slice_as_text: bool = true,
};

pub fn stringify(
    value: anytype,
    options: StringifyOptions,
    out: anytype,
) StringifyError!void {
    const T = @TypeOf(value);
    var head: u8 = 0;
    switch (@typeInfo(T)) {
        .Int, .ComptimeInt => head = if (value < 0) 0x20 else 0,
        .Float, .ComptimeFloat, .Bool, .Null => head = 0xe0,
        .Array => head = 0x80,
        .Struct => head = 0xa0, // Struct becomes a Map.
        .Optional => {}, // <- This value will be ignored.
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .Slice => {
                if (ptr_info.child == u8) {
                    if (options.slice_as_text and std.unicode.utf8ValidateSlice(value)) {
                        head = 0x60;
                    } else {
                        head = 0x40;
                    }
                } else {
                    head = 0x80;
                }
            },
            .One => {
                try stringify(value.*, options, out);
                return;
            },
            else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
        },
        else => {
            return .UnsupportedItem;
        }, // TODO: add remaining options
    }

    var v: u64 = switch (@typeInfo(T)) {
        .Int, .ComptimeInt => @intCast(u64, if (value < 0) -(value + 1) else value),
        .Float, .ComptimeFloat => {
            // TODO: implement
            // TODO: Encode as small as possible!
            // TODO: Handle values that cant fit in u64 (->tagged)
            return;
        },
        .Bool => if (value) 21 else 20,
        .Null => 22,
        .Struct => |S| @intCast(u64, S.fields.len),
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
            .Slice => @intCast(u64, value.len),
            else => {},
        },
        else => unreachable, // caught by the first check
    };

    switch (v) {
        0x00...0x17 => {
            try out.writeByte(head | @intCast(u8, v));
        },
        0x18...0xff => {
            try out.writeByte(head | 24);
            try out.writeByte(@intCast(u8, v));
        },
        0x0100...0xffff => try encoder.encode_2(out, head, v),
        0x00010000...0xffffffff => try encoder.encode_4(out, head, v),
        0x0000000100000000...0xffffffffffffffff => try encoder.encode_8(out, head, v),
    }

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat, .Bool, .Null => {},
        .Struct => |S| {
            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.field_type == void) continue;

                // dont't include (optional) null fields
                if (@typeInfo(Field.field_type) == .Optional) {
                    if (options.skip_null_fields) {
                        if (@field(value, Field.name) == null) {
                            continue;
                        }
                    }
                }

                try stringify(Field.name, options, out); // key
                try stringify(@field(value, Field.name), options, out); // value
            }
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .Slice => {
                if (ptr_info.child == u8) {
                    try out.writeAll(value);
                } else {
                    for (value) |x| {
                        try stringify(x, options, out);
                    }
                }
            },
            else => {},
        },
        else => unreachable, // caught by the previous check
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
    const t = DataItem.True();
    const f = DataItem.False();
    const u = DataItem.Undefined();
    const i = DataItem.int(11);

    try std.testing.expectEqual(true, try parse(bool, t, .{}));
    try std.testing.expectEqual(false, try parse(bool, f, .{}));
    try std.testing.expectError(ParseError.UnexpectedItemValue, parse(bool, u, .{}));
    try std.testing.expectError(ParseError.UnexpectedItem, parse(bool, i, .{}));
}

test "parse float" {
    const f1 = DataItem.float16(1.1);
    const f2 = DataItem.float32(7.3511);
    const f3 = DataItem.float64(-12.06);

    try std.testing.expectApproxEqRel(try parse(f16, f1, .{}), 1.1, 0.01);
    try std.testing.expectApproxEqRel(try parse(f16, f2, .{}), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f2, .{}), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f3, .{}), -12.06, 0.01);
    try std.testing.expectApproxEqRel(try parse(f64, f3, .{}), -12.06, 0.01);
}

test "stringify float" {
    // TODO
}

test "parse int" {
    const i_1 = DataItem.int(255);
    const i_2 = DataItem.int(256);

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
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
        Pair.new(try DataItem.text("production", .{ .allocator = allocator }), DataItem.int(42)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const c = try parse(Config, di, .{});

    try std.testing.expectEqual(c.uptime, 9999);
    try std.testing.expectEqual(c.vals.testing, 1);
    try std.testing.expectEqual(c.vals.production, 42);
}

test "parse struct: 2 (optional missing field)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: ?u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const c = try parse(Config, di, .{});

    try std.testing.expectEqual(c.vals.production, null);
}

test "parse struct: 3 (missing field)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.MissingField, parse(Config, di, .{}));
}

test "parse struct: 4 (unknown field)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
        Pair.new(try DataItem.text("production", .{ .allocator = allocator }), DataItem.int(42)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.UnknownField, parse(Config, di, .{ .ignore_unknown_fields = false }));
}

test "parse struct: 5 (duplicate field use first)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
        Pair.new(try DataItem.text("production", .{ .allocator = allocator }), DataItem.int(42)),
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(7)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const c = try parse(Config, di, .{ .duplicate_field_behavior = .UseFirst });

    try std.testing.expectEqual(c.uptime, 9999);
    try std.testing.expectEqual(c.vals.testing, 1);
    try std.testing.expectEqual(c.vals.production, 42);
}

test "parse struct: 6 (duplicate field error)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(&.{ Pair.new(try DataItem.text("vals", .{ .allocator = allocator }), try DataItem.map(&.{
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(1)),
        Pair.new(try DataItem.text("production", .{ .allocator = allocator }), DataItem.int(42)),
        Pair.new(try DataItem.text("testing", .{ .allocator = allocator }), DataItem.int(7)),
    }, .{ .allocator = allocator })), Pair.new(try DataItem.text("uptime", .{ .allocator = allocator }), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.DuplicateCborField, parse(Config, di, .{}));
}

test "parse struct: 7" {
    const allocator = std.testing.allocator;

    const Config = struct {
        @"1": struct { @"1": u8, @"2": u8 },
        @"2": u64,
    };

    const di = try DataItem.map(&.{ Pair.new(DataItem.int(1), try DataItem.map(&.{
        Pair.new(DataItem.int(1), DataItem.int(1)),
        Pair.new(DataItem.int(2), DataItem.int(42)),
    }, .{ .allocator = allocator })), Pair.new(DataItem.int(2), DataItem.int(9999)) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const c = try parse(Config, di, .{ .allocator = allocator });

    try std.testing.expectEqual(c.@"2", 9999);
    try std.testing.expectEqual(c.@"1".@"1", 1);
    try std.testing.expectEqual(c.@"1".@"2", 42);
}

test "parse optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try std.testing.expectEqual(e1, try parse(?u32, DataItem.int(1234), .{}));
    try std.testing.expectEqual(e2, try parse(?u32, DataItem.Null(), .{}));
    try std.testing.expectEqual(e2, try parse(?u32, DataItem.Undefined(), .{}));
}

test "stringify optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try testStringify("\xf6", e2, .{});
    try testStringify("\x19\x04\xd2", e1, .{});
}

test "parse array: 1" {
    const allocator = std.testing.allocator;

    const e = [5]u8{ 1, 2, 3, 4, 5 };
    const di = try DataItem.array(&.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const x = try parse([5]u8, di, .{});

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "parse array: 2" {
    const allocator = std.testing.allocator;

    const e = [5]?u8{ 1, null, 3, null, 5 };
    const di = try DataItem.array(&.{ DataItem.int(1), DataItem.Null(), DataItem.int(3), DataItem.Null(), DataItem.int(5) }, .{ .allocator = allocator });
    defer di.deinit(allocator);

    const x = try parse([5]?u8, di, .{});

    try std.testing.expectEqualSlices(?u8, e[0..], x[0..]);
}

test "parse pointer" {
    const allocator = std.testing.allocator;

    const e1_1: u32 = 1234;
    const e1: *const u32 = &e1_1;
    const di1 = DataItem.int(1234);
    const c1 = try parse(*const u32, di1, .{ .allocator = allocator });
    defer allocator.destroy(c1);
    try std.testing.expectEqual(e1.*, c1.*);

    var e2_1: u32 = 1234;
    const e2: *u32 = &e2_1;
    const di2 = DataItem.int(1234);
    const c2 = try parse(*u32, di2, .{ .allocator = allocator });
    defer allocator.destroy(c2);
    try std.testing.expectEqual(e2.*, c2.*);
}

test "parse slice" {
    const allocator = std.testing.allocator;

    var e1: []const u8 = &.{ 1, 2, 3, 4, 5 };
    const di1 = try DataItem.bytes(&.{ 1, 2, 3, 4, 5 }, .{ .allocator = allocator });
    defer di1.deinit(allocator);
    const c1 = try parse([]const u8, di1, .{ .allocator = allocator });
    defer allocator.free(c1);
    try std.testing.expectEqualSlices(u8, e1, c1);

    var e2: []const u8 = &.{ 1, 2, 3, 4, 5 };
    const di2 = try DataItem.array(&.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5) }, .{ .allocator = allocator });
    defer di2.deinit(allocator);
    const c2 = try parse([]const u8, di2, .{ .allocator = allocator });
    defer allocator.free(c2);
    try std.testing.expectEqualSlices(u8, e2, c2);
}

test "parse from payload" {
    const allocator = std.testing.allocator;

    const payload = "\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f";

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    var data_item = try decode(allocator, payload);
    defer data_item.deinit(allocator);

    const config = try parse(Config, data_item, .{});

    try std.testing.expectEqual(config.uptime, 9999);
    try std.testing.expectEqual(config.vals.testing, 1);
    try std.testing.expectEqual(config.vals.production, 42);
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
    const s1: []const u8 = "a";
    try testStringify("\x61\x61", s1, .{});

    const s2: []const u8 = "IETF";
    try testStringify("\x64\x49\x45\x54\x46", s2, .{});

    const s3: []const u8 = "\"\\";
    try testStringify("\x62\x22\x5c", s3, .{});

    const b1: []const u8 = &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 };
    try testStringify(&.{ 0x58, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 }, b1, .{ .slice_as_text = false });

    const b2: []const u8 = "\x10\x11\x12\x13\x14";
    try testStringify("\x45\x10\x11\x12\x13\x14", b2, .{ .slice_as_text = false });
}

test "stringify struct: 1" {
    const Info = struct {
        versions: []const []const u8,
    };

    const i = Info{
        .versions = &.{"FIDO_2_0"},
    };

    try testStringify("\xa1\x68\x76\x65\x72\x73\x69\x6f\x6e\x73\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
}

//test "stringify struct: 2" {
//    const Info = struct {
//        @"1": []const []const u8,
//        @"2": []const []const u8,
//        @"3": []const u8,
//    };
//
//    const i = Info{
//        .@"1" = &.{"FIDO_2_0"},
//        .@"2" = &.{},
//        .@"3" = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
//    };
//
//    try testStringify("\xa1\x68\x76\x65\x72\x73\x69\x6f\x6e\x73\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
//}
