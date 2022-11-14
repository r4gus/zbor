const std = @import("std");

pub const Error = error{
    Malformed,
    TypeMismatch,
};

pub const Type = enum {
    Unsigned,
    Undefined,

    pub fn fromByte(b: u8) @This() {
        return switch (b) {
            0x00...0x1b => .Unsigned,
            else => .Undefined,
        };
    }
};

pub const DataItem = struct {
    data: []const u8,

    pub fn new(data: []const u8) @This() {
        return .{ .data = data };
    }

    pub fn getType(self: @This()) Type {
        return Type.fromByte(self.data[0]);
    }

    pub fn unsigned(self: @This()) !u64 {
        return switch (self.data[0]) {
            0x00...0x17 => @intCast(u64, self.data[0]),
            0x18 => @intCast(u64, self.data[1]),
            0x19 => @intCast(u64, unsigned_16(self.data[1..3])),
            0x1a => @intCast(u64, unsigned_32(self.data[1..5])),
            0x1b => @intCast(u64, unsigned_64(self.data[1..9])),
            else => Error.TypeMismatch,
        };
    }
};

fn unsigned_16(data: []const u8) u16 {
    return @intCast(u16, data[0]) << 8 | @intCast(u16, data[1]);
}

fn unsigned_32(data: []const u8) u32 {
    return @intCast(u32, data[0]) << 24 | @intCast(u32, data[1]) << 16 | @intCast(u32, data[2]) << 8 | @intCast(u32, data[3]);
}

fn unsigned_64(data: []const u8) u64 {
    return @intCast(u64, data[0]) << 56 | @intCast(u64, data[1]) << 48 | @intCast(u64, data[2]) << 40 | @intCast(u64, data[3]) << 32 | @intCast(u64, data[4]) << 24 | @intCast(u64, data[5]) << 16 | @intCast(u64, data[6]) << 8 | @intCast(u64, data[7]);
}

test "deserialize unsigned" {
    const di1 = DataItem.new("\x00");
    try std.testing.expectEqual(Type.Unsigned, di1.getType());
    try std.testing.expectEqual(di1.unsigned(), 0);

    const di2 = DataItem.new("\x01");
    try std.testing.expectEqual(Type.Unsigned, di2.getType());
    try std.testing.expectEqual(di2.unsigned(), 1);

    const di3 = DataItem.new("\x17");
    try std.testing.expectEqual(Type.Unsigned, di3.getType());
    try std.testing.expectEqual(di3.unsigned(), 23);

    const di4 = DataItem.new("\x18\x18");
    try std.testing.expectEqual(Type.Unsigned, di4.getType());
    try std.testing.expectEqual(di4.unsigned(), 24);
}
