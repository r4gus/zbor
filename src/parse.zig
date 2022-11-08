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

pub const ParseError = error{
    UnexpectedItem,
    UnexpectedItemValue,
    InvalidKeyType,
    DuplicateCborField,
    UnknownField,
    MissingField,
    Overflow,
};

pub fn parse(comptime T: type, item: DataItem) ParseError!T {
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
                    return if (v == SimpleValue.Null or v == SimpleValue.Undefined) null else try parse(optionalInfo.child, item);
                },
                else => return try parse(optionalInfo.child, item),
            }
        },
        .Struct => |structInfo| {
            switch (item) {
                .map => |v| {
                    var r: T = undefined;
                    var fields_seen = [_]bool{false} ** structInfo.fields.len;

                    for (v) |kv| {
                        var found = false;

                        if (!kv.key.isText()) continue;

                        inline for (structInfo.fields) |field, i| {
                            if (std.mem.eql(u8, field.name, kv.key.text)) {
                                if (fields_seen[i]) {
                                    return ParseError.DuplicateCborField;
                                }

                                @field(r, field.name) = try parse(field.field_type, kv.value);

                                fields_seen[i] = true;
                                found = true;
                                break;
                            }
                        }

                        if (!found) {
                            // ignore
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
                        r[i] = try parse(arrayInfo.child, v[i]);
                    }

                    return r;
                },
                else => return ParseError.UnexpectedItem,
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

    try std.testing.expectEqual(true, try parse(bool, t));
    try std.testing.expectEqual(false, try parse(bool, f));
    try std.testing.expectError(ParseError.UnexpectedItemValue, parse(bool, u));
    try std.testing.expectError(ParseError.UnexpectedItem, parse(bool, i));
}

test "parse float" {
    const f1 = DataItem.float16(1.1);
    const f2 = DataItem.float32(7.3511);
    const f3 = DataItem.float64(-12.06);

    try std.testing.expectApproxEqRel(try parse(f16, f1), 1.1, 0.01);
    try std.testing.expectApproxEqRel(try parse(f16, f2), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f2), 7.3511, 0.01);
    try std.testing.expectApproxEqRel(try parse(f32, f3), -12.06, 0.01);
    try std.testing.expectApproxEqRel(try parse(f64, f3), -12.06, 0.01);
}

test "parse int" {
    const i_1 = DataItem.int(255);
    const i_2 = DataItem.int(256);

    try std.testing.expectEqual(try parse(u8, i_1), 255);
    try std.testing.expectError(ParseError.Overflow, parse(u8, i_2));
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

    const c = try parse(Config, di);

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

    const c = try parse(Config, di);

    try std.testing.expectEqual(c.vals.production, null);
}

test "parse optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try std.testing.expectEqual(e1, try parse(?u32, DataItem.int(1234)));
    try std.testing.expectEqual(e2, try parse(?u32, DataItem.Null()));
    try std.testing.expectEqual(e2, try parse(?u32, DataItem.Undefined()));
}

test "parse array: 1" {
    const allocator = std.testing.allocator;

    const e = [5]u8{ 1, 2, 3, 4, 5 };
    const di = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5) });
    defer di.deinit(allocator);

    const x = try parse([5]u8, di);

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "parse array: 2" {
    const allocator = std.testing.allocator;

    const e = [5]?u8{ 1, null, 3, null, 5 };
    const di = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.Null(), DataItem.int(3), DataItem.Null(), DataItem.int(5) });
    defer di.deinit(allocator);

    const x = try parse([5]?u8, di);

    try std.testing.expectEqualSlices(?u8, e[0..], x[0..]);
}
