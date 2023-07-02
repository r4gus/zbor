const std = @import("std");
const cbor = @import("cbor.zig");

/// Type of a Builder container
pub const ContainerType = enum {
    Root,
    Array,
    Map,
};

const Entry = struct {
    t: ContainerType = .Root,
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

/// A Builder lets you dynamically generate CBOR data.
pub const Builder = struct {
    stack: std.ArrayList(Entry),
    allocator: std.mem.Allocator,

    /// Create a new builder.
    ///
    /// On error all allocated memory is freed.
    pub fn new(allocator: std.mem.Allocator) !@This() {
        return withType(allocator, .Root);
    }

    /// Create a new builder with the given container type.
    ///
    /// On error all allocated memory is freed.
    pub fn withType(allocator: std.mem.Allocator, t: ContainerType) !@This() {
        var b = @This(){
            .stack = std.ArrayList(Entry).init(allocator),
            .allocator = allocator,
        };

        // The stack has at least one element on it: the Root
        b.stack.append(Entry.new(allocator, .Root)) catch |e| {
            b.unwind();
            return e;
        };
        // If we want to use a container type just push another
        // entry onto the stack. The container will later be
        // merged into the root
        if (t != .Root) {
            b.stack.append(Entry.new(allocator, t)) catch |e| {
                b.unwind();
                return e;
            };
        }
        return b;
    }

    /// Serialize an integer.
    ///
    /// On error all allocated memory is freed. After this
    /// point one MUST NOT access the builder!
    pub fn pushInt(self: *@This(), value: i65) !void {
        const h: u8 = if (value < 0) 0x20 else 0;
        const v: u64 = @as(u64, @intCast(if (value < 0) -(value + 1) else value));
        encode(self.top().raw.writer(), h, v) catch |e| {
            self.unwind();
            return e;
        };
        self.top().cnt += 1;
    }

    /// Serialize a slice as byte string.
    ///
    /// On error all allocated memory is freed. After this
    /// point one MUST NOT access the builder!
    pub fn pushByteString(self: *@This(), value: []const u8) !void {
        const h: u8 = 0x40;
        const v: u64 = @as(u64, @intCast(value.len));
        encode(self.top().raw.writer(), h, v) catch |e| {
            self.unwind();
            return e;
        };
        self.top().raw.appendSlice(value) catch |e| {
            self.unwind();
            return e;
        };
        self.top().cnt += 1;
    }

    /// Serialize a slice as text string.
    ///
    /// On error all allocated memory is freed. After this
    /// point one MUST NOT access the builder!
    pub fn pushTextString(self: *@This(), value: []const u8) !void {
        const h: u8 = 0x60;
        const v: u64 = @as(u64, @intCast(value.len));
        encode(self.top().raw.writer(), h, v) catch |e| {
            self.unwind();
            return e;
        };
        self.top().raw.appendSlice(value) catch |e| {
            self.unwind();
            return e;
        };
        self.top().cnt += 1;
    }

    /// Serialize a tag.
    ///
    /// You MUST serialize another data item right after calling this function.
    ///
    /// On error all allocated memory is freed. After this
    /// point one MUST NOT access the builder!
    pub fn pushTag(self: *@This(), tag: u64) !void {
        const h: u8 = 0xc0;
        const v: u64 = tag;
        encode(self.top().raw.writer(), h, v) catch |e| {
            self.unwind();
            return e;
        };
    }

    /// Serialize a simple value.
    ///
    /// On error (except for ReservedValue) all allocated memory is freed.
    /// After this point one MUST NOT access the builder!
    pub fn pushSimple(self: *@This(), simple: u8) !void {
        if (24 <= simple and simple <= 31) return error.ReservedValue;

        const h: u8 = 0xf0;
        const v: u64 = @as(u64, @intCast(simple));
        encode(self.top().raw.writer(), h, v) catch |e| {
            self.unwind();
            return e;
        };
    }

    /// Add a chunk of CBOR.
    ///
    /// The given CBOR data is only added if its well formed.
    ///
    /// On error (except for MalformedCbor) all allocated memory is freed.
    /// After this point one MUST NOT access the builder!
    pub fn pushCbor(self: *@This(), input: []const u8) !void {
        // First check that the given cbor is well formed
        var i: usize = 0;
        if (!cbor.wellFormed(input, i, true)) return error.MalformedCbor;

        // Append the cbor data
        self.top().raw.appendSlice(input) catch |e| {
            self.unwind();
            return e;
        };
        self.top().cnt += 1;
    }

    /// Enter a data structure (Array or Map)
    ///
    /// On error (except for InvalidContainerType) all allocated memory is freed.
    /// After this point one MUST NOT access the builder!
    pub fn enter(self: *@This(), t: ContainerType) !void {
        if (t == .Root) return error.InvalidContainerType;

        self.stack.append(Entry.new(self.allocator, t)) catch |e| {
            self.unwind();
            return e;
        };
    }

    /// Leave the current data structure
    ///
    /// On error (except for EmptyStack and InvalidPairCount) all allocated
    /// memory is freed. After this point one MUST NOT access the builder!
    pub fn leave(self: *@This()) !void {
        if (self.stack.items.len < 2) return error.EmptyStack;
        if (self.top().t == .Map and self.top().cnt & 0x01 != 0)
            return error.InvalidPairCount;

        try self.moveUp();
    }

    /// Return the serialized data.
    ///
    /// The caller is responsible for freeing the data.
    ///
    /// On error (except for InvalidPairCount) all allocated
    /// memory is freed. After this point one MUST NOT access the builder!
    pub fn finish(self: *@This()) ![]u8 {
        if (self.top().t == .Map and self.top().cnt & 0x01 != 0)
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
            .Root => unreachable,
        };
        const v: u64 = if (e.t == .Map) e.cnt / 2 else e.cnt;
        encode(self.top().raw.writer(), h, v) catch |err| {
            self.unwind();
            return err;
        };
        self.top().raw.appendSlice(e.raw.items) catch |err| {
            self.unwind();
            return err;
        };
        self.top().cnt += 1;
    }

    /// Return a mutable reference to the element at the top of the stack.
    fn top(self: *@This()) *Entry {
        return &self.stack.items[self.stack.items.len - 1];
    }

    fn encode(out: anytype, head: u8, v: u64) !void {
        switch (v) {
            0x00...0x17 => {
                try out.writeByte(head | @as(u8, @intCast(v)));
            },
            0x18...0xff => {
                try out.writeByte(head | 24);
                try out.writeByte(@as(u8, @intCast(v)));
            },
            0x0100...0xffff => try cbor.encode_2(out, head, v),
            0x00010000...0xffffffff => try cbor.encode_4(out, head, v),
            0x0000000100000000...0xffffffffffffffff => try cbor.encode_8(out, head, v),
        }
    }

    /// Free all allocated memory on error. This is meant
    /// to prevent memory leaks if the builder throws an error.
    fn unwind(self: *@This()) void {
        while (self.stack.items.len > 0) {
            const e = self.stack.pop();
            e.raw.deinit();
        }
        self.stack.deinit();
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

test "stringify tag using builder 1" {
    const allocator = std.testing.allocator;
    var b = try Builder.new(allocator);
    try b.pushTag(0);
    try b.pushTextString("2013-03-21T20:04:00Z");
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\xc0\x74\x32\x30\x31\x33\x2d\x30\x33\x2d\x32\x31\x54\x32\x30\x3a\x30\x34\x3a\x30\x30\x5a", x);
}

test "stringify simple using builder 1" {
    const allocator = std.testing.allocator;
    var b = try Builder.new(allocator);
    try b.pushSimple(255);
    const x = try b.finish();
    defer allocator.free(x);

    try std.testing.expectEqualSlices(u8, "\xf8\xff", x);
}
