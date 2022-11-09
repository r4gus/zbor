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

test "parse int" {
    const i_1 = DataItem.int(255);
    const i_2 = DataItem.int(256);

    try std.testing.expectEqual(try parse(u8, i_1, .{}), 255);
    try std.testing.expectError(ParseError.Overflow, parse(u8, i_2, .{}));
}

test "parse struct: 1" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
        Pair.new(try DataItem.text(allocator, "production"), DataItem.int(42)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
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

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
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

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.MissingField, parse(Config, di, .{}));
}

test "parse struct: 4 (unknown field)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
        Pair.new(try DataItem.text(allocator, "production"), DataItem.int(42)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.UnknownField, parse(Config, di, .{ .ignore_unknown_fields = false }));
}

test "parse struct: 5 (duplicate field use first)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
        Pair.new(try DataItem.text(allocator, "production"), DataItem.int(42)),
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(7)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
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

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "vals"), try DataItem.map(allocator, &.{
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(1)),
        Pair.new(try DataItem.text(allocator, "production"), DataItem.int(42)),
        Pair.new(try DataItem.text(allocator, "testing"), DataItem.int(7)),
    })), Pair.new(try DataItem.text(allocator, "uptime"), DataItem.int(9999)) });
    defer di.deinit(allocator);

    try std.testing.expectError(ParseError.DuplicateCborField, parse(Config, di, .{}));
}

test "parse struct: 7" {
    const allocator = std.testing.allocator;

    const Config = struct {
        @"1": struct { @"1": u8, @"2": u8 },
        @"2": u64,
    };

    const di = try DataItem.map(allocator, &.{ Pair.new(DataItem.int(1), try DataItem.map(allocator, &.{
        Pair.new(DataItem.int(1), DataItem.int(1)),
        Pair.new(DataItem.int(2), DataItem.int(42)),
    })), Pair.new(DataItem.int(2), DataItem.int(9999)) });
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

test "parse array: 1" {
    const allocator = std.testing.allocator;

    const e = [5]u8{ 1, 2, 3, 4, 5 };
    const di = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5) });
    defer di.deinit(allocator);

    const x = try parse([5]u8, di, .{});

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "parse array: 2" {
    const allocator = std.testing.allocator;

    const e = [5]?u8{ 1, null, 3, null, 5 };
    const di = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.Null(), DataItem.int(3), DataItem.Null(), DataItem.int(5) });
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
    const di1 = try DataItem.bytes(allocator, &.{ 1, 2, 3, 4, 5 });
    defer di1.deinit(allocator);
    const c1 = try parse([]const u8, di1, .{ .allocator = allocator });
    defer allocator.free(c1);
    try std.testing.expectEqualSlices(u8, e1, c1);

    var e2: []const u8 = &.{ 1, 2, 3, 4, 5 };
    const di2 = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5) });
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
