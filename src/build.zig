const std = @import("std");
const cbor = @import("cbor.zig");

pub const ContainerType = enum {
    Leaf,
    Array,
    Map,
};

const Entry = struct {
    t: ContainerType = .Leaf,
    cnt: u64 = 0,
    raw: std.ArrayList(u8),

    pub fn new(allocator: std.mem.Allocator, t: ContainerType) @This() {
        return .{
            .t = t,
            .cnt = 0,
            .raw = std.ArrayList(u8).init(allocator),
        };
    }
};

pub const Builder = struct {
    stack: std.ArrayList(Entry),
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) !@This() {
        return withType(allocator, .Leaf);
    }

    pub fn withType(allocator: std.mem.Allocator, t: ContainerType) !@This() {
        var b = @This(){
            .stack = std.ArrayList(Entry).init(allocator),
            .allocator = allocator,
        };

        try b.stack.append(Entry.new(allocator, .Leaf));
        if (t != .Leaf) {
            try b.stack.append(Entry.new(allocator, t));
        }
        return b;
    }

    pub fn pushInt(self: *@This(), value: i65) !void {
        const h: u8 = if (value < 0) 0x20 else 0;
        const v: u64 = @intCast(u64, if (value < 0) -(value + 1) else value);
        try encode(self.last().raw.writer(), h, v);
        self.last().cnt += 1;
    }

    pub fn pushByteString(self: *@This(), value: []const u8) !void {
        const h: u8 = 0x40;
        const v: u64 = @intCast(u64, value.len);
        try encode(self.last().raw.writer(), h, v);
        try self.last().raw.appendSlice(value);
        self.last().cnt += 1;
    }

    pub fn pushTextString(self: *@This(), value: []const u8) !void {
        const h: u8 = 0x60;
        const v: u64 = @intCast(u64, value.len);
        try encode(self.last().raw.writer(), h, v);
        try self.last().raw.appendSlice(value);
        self.last().cnt += 1;
    }

    pub fn enter(self: *@This(), t: ContainerType) !void {
        if (t == .Leaf) return error.InvalidContainerType;

        try self.stack.append(Entry.new(self.allocator, t));
    }

    pub fn leave(self: *@This()) !void {
        if (self.stack.items.len < 2) return error.EmptyStack;
        if (self.last().t == .Map and self.last().cnt & 0x01 != 0)
            return error.InvalidPairCount;

        try self.moveUp();
    }

    pub fn finish(self: *@This()) ![]u8 {
        if (self.last().t == .Map and self.last().cnt & 0x01 != 0)
            return error.InvalidPairCount;

        // unwind the stack if neccessary
        while (self.stack.items.len > 1) {
            try self.moveUp();
        }

        var s = self.stack.items[0].raw.toOwnedSlice();
        self.stack.deinit();
        return s;
    }

    fn moveUp(self: *@This()) !void {
        const e = self.stack.pop();
        defer e.raw.deinit();

        const h: u8 = switch (e.t) {
            .Array => 0x80,
            .Map => 0xa0,
            .Leaf => unreachable,
        };
        const v: u64 = if (e.t == .Map) e.cnt / 2 else e.cnt;
        try encode(self.last().raw.writer(), h, v);
        try self.last().raw.appendSlice(e.raw.items);
        self.last().cnt += 1;
    }

    fn last(self: *@This()) *Entry {
        return &self.stack.items[self.stack.items.len - 1];
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
};

fn testInt(expected: []const u8, i: i65) !void {
    const allocator = std.testing.allocator;

    var b = try Builder.new(allocator);
    try b.pushInt(i);
    const x = try b.finish();
    defer allocator.free(x);
    try std.testing.expectEqualSlices(u8, expected, x);
}

fn testByteString(expected: []const u8, i: []const u8) !void {
    const allocator = std.testing.allocator;

    var b = try Builder.new(allocator);
    try b.pushByteString(i);
    const x = try b.finish();
    defer allocator.free(x);
    try std.testing.expectEqualSlices(u8, expected, x);
}

fn testTextString(expected: []const u8, i: []const u8) !void {
    const allocator = std.testing.allocator;

    var b = try Builder.new(allocator);
    try b.pushTextString(i);
    const x = try b.finish();
    defer allocator.free(x);
    try std.testing.expectEqualSlices(u8, expected, x);
}

test "stringify int with builder" {
    try testInt("\x1b\x00\x00\x00\x02\xdf\xdc\x1c\x34", 12345678900);
    try testInt("\x18\x7b", 123);

    try testInt("\x3a\x00\x0f\x3d\xdc", -998877);
    try testInt("\x3b\xff\xff\xff\xff\xff\xff\xff\xff", -18446744073709551616);
}

test "stringify string with builder" {
    try testByteString("\x45\x10\x11\x12\x13\x14", "\x10\x11\x12\x13\x14");

    try testTextString("\x64\x49\x45\x54\x46", "IETF");
    try testTextString("\x62\x22\x5c", "\"\\");
}

test "stringify array using builder 1" {
    const allocator = std.testing.allocator;
    var b = try Builder.withType(allocator, .Array);
    try b.pushInt(1);
    try b.enter(.Array); // array 1 start
    try b.pushInt(2);
    try b.pushInt(3);
    try b.leave(); // array 1 end
    try b.enter(.Array); // array 2 start
    try b.pushInt(4);
    try b.pushInt(5);
    try b.leave(); // array 2 end
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\x83\x01\x82\x02\x03\x82\x04\x05", x);
}

test "stringify array using builder 2" {
    const allocator = std.testing.allocator;
    var b = try Builder.withType(allocator, .Array);
    var i: i65 = 1;
    while (i < 26) : (i += 1) {
        try b.pushInt(i);
    }
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\x98\x19\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19", x);
}

test "stringify map using builder 1" {
    const allocator = std.testing.allocator;
    var b = try Builder.withType(allocator, .Map);
    try b.pushInt(1);
    try b.pushInt(2);
    try b.pushInt(3);
    try b.pushInt(4);
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\xa2\x01\x02\x03\x04", x);
}

test "stringify nested map using builder 1" {
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

    try std.testing.expectEqualSlices(u8, "\xa2\x61\x61\x01\x61\x62\x82\x02\x03", x);
}

test "stringify nested array using builder 1" {
    const allocator = std.testing.allocator;
    var b = try Builder.withType(allocator, .Array);
    try b.pushTextString("a");
    try b.enter(.Map);
    try b.pushTextString("b");
    try b.pushTextString("c");
    try b.leave();
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\x82\x61\x61\xa1\x61\x62\x61\x63", x);
}
