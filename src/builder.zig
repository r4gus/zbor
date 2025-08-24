const std = @import("std");
const cbor = @import("cbor.zig");

/// Serialize an integer into a CBOR integer (major type 0 or 1).
pub fn writeInt(writer: *std.Io.Writer, value: i65) !void {
    const h: u8 = if (value < 0) 0x20 else 0;
    const v: u64 = @as(u64, @intCast(if (value < 0) -(value + 1) else value));
    try encode(writer, h, v);
}

/// Serialize a slice to a CBOR byte string (major type 2).
pub fn writeByteString(writer: *std.Io.Writer, value: []const u8) !void {
    const h: u8 = 0x40;
    const v: u64 = @as(u64, @intCast(value.len));
    try encode(writer, h, v);
    try writer.writeAll(value);
}

/// Serialize a slice to a CBOR text string (major type 3).
pub fn writeTextString(writer: *std.Io.Writer, value: []const u8) !void {
    const h: u8 = 0x60;
    const v: u64 = @as(u64, @intCast(value.len));
    try encode(writer, h, v);
    try writer.writeAll(value);
}

/// Serialize a tag.
///
/// You MUST serialize another data item right after calling this function.
pub fn writeTag(writer: *std.Io.Writer, tag: u64) !void {
    const h: u8 = 0xc0;
    const v: u64 = tag;
    try encode(writer, h, v);
}

/// Serialize a simple value.
pub fn writeSimple(writer: *std.Io.Writer, simple: u8) !void {
    if (24 <= simple and simple <= 31) return error.ReservedValue;
    const h: u8 = 0xe0;
    const v: u64 = @as(u64, @intCast(simple));
    try encode(writer, h, v);
}

pub fn writeTrue(writer: *std.Io.Writer) !void {
    try writeSimple(writer, 21);
}

pub fn writeFalse(writer: *std.Io.Writer) !void {
    try writeSimple(writer, 20);
}

pub fn writeFloat(writer: *std.Io.Writer, f: anytype) !void {
    const T = @TypeOf(f);
    const TInf = @typeInfo(T);

    switch (TInf) {
        .float => |float| {
            switch (float.bits) {
                16 => try cbor.encode_2(writer, 0xe0, @as(u64, @intCast(@as(u16, @bitCast(f))))),
                32 => try cbor.encode_4(writer, 0xe0, @as(u64, @intCast(@as(u32, @bitCast(f))))),
                64 => try cbor.encode_8(writer, 0xe0, @as(u64, @intCast(@as(u64, @bitCast(f))))),
                else => @compileError("Float must be 16, 32 or 64 Bits wide"),
            }
        },
        else => return error.NotAFloat,
    }
}

/// Write the header of an array to `writer`.
///
/// You must write exactly `len` data items to `writer` afterwards.
pub inline fn writeArray(writer: *std.Io.Writer, len: u64) !void {
    try encode(writer, 0x80, len);
}

/// Write the header of a map to `writer`.
///
/// You must write exactly `len` key-value pairs (data items) to `writer` afterwards.
pub inline fn writeMap(writer: *std.Io.Writer, len: u64) !void {
    try encode(writer, 0xa0, len);
}

/// Type of a Builder container
pub const ContainerType = enum {
    Root,
    Array,
    Map,
};

const Entry = struct {
    t: ContainerType = .Root,
    cnt: u64 = 0,
    raw: std.Io.Writer.Allocating,

    pub fn new(allocator: std.mem.Allocator, t: ContainerType) @This() {
        return .{
            .t = t,
            .cnt = 0,
            .raw = .init(allocator),
        };
    }
};

/// A Builder lets you dynamically generate CBOR data.
pub const Builder = struct {
    stack: std.ArrayListUnmanaged(Entry),
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
            .stack = .{},
            .allocator = allocator,
        };

        // The stack has at least one element on it: the Root
        b.stack.append(b.allocator, Entry.new(allocator, .Root)) catch |e| {
            b.unwind();
            return e;
        };
        // If we want to use a container type just push another
        // entry onto the stack. The container will later be
        // merged into the root
        if (t != .Root) {
            b.stack.append(b.allocator, Entry.new(allocator, t)) catch |e| {
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
        writeInt(&self.top().raw.writer, value) catch |e| {
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
        writeByteString(&self.top().raw.writer, value) catch |e| {
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
        writeTextString(&self.top().raw.writer, value) catch |e| {
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
        writeTag(&self.top().raw.writer, tag) catch |e| {
            self.unwind();
            return e;
        };
    }

    /// Serialize a simple value.
    ///
    /// On error (except for ReservedValue) all allocated memory is freed.
    /// After this point one MUST NOT access the builder!
    pub fn pushSimple(self: *@This(), simple: u8) !void {
        writeSimple(&self.top().raw.writer, simple) catch |e| {
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
        if (!cbor.validate(input, &i, true)) return error.MalformedCbor;

        // Append the cbor data
        self.top().raw.writer.writeAll(input) catch |e| {
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

        self.stack.append(self.allocator, Entry.new(self.allocator, t)) catch |e| {
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

        const s = self.stack.items[0].raw.toOwnedSlice();
        self.stack.deinit(self.allocator);
        return s;
    }

    fn moveUp(self: *@This()) !void {
        var e = self.stack.pop().?;
        defer e.raw.deinit();

        switch (e.t) {
            .Array => writeArray(&self.top().raw.writer, e.cnt) catch |err| {
                self.unwind();
                return err;
            },
            .Map => writeMap(&self.top().raw.writer, e.cnt / 2) catch |err| {
                self.unwind();
                return err;
            },
            .Root => unreachable,
        }
        self.top().raw.writer.writeAll(e.raw.written()) catch |err| {
            self.unwind();
            return err;
        };
        self.top().cnt += 1;
    }

    /// Return a mutable reference to the element at the top of the stack.
    fn top(self: *@This()) *Entry {
        return &self.stack.items[self.stack.items.len - 1];
    }

    /// Free all allocated memory on error. This is meant
    /// to prevent memory leaks if the builder throws an error.
    fn unwind(self: *@This()) void {
        while (self.stack.items.len > 0) {
            var e = self.stack.pop().?;
            e.raw.deinit();
        }
        self.stack.deinit(self.allocator);
    }
};

fn encode(out: *std.Io.Writer, head: u8, v: u64) !void {
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

test "write true false" {
    const allocator = std.testing.allocator;

    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try writeTrue(&arr.writer);
    try writeFalse(&arr.writer);

    try std.testing.expectEqual(@as(u8, 0xf5), arr.written()[0]);
    try std.testing.expectEqual(@as(u8, 0xf4), arr.written()[1]);
}

test "write float #1" {
    const allocator = std.testing.allocator;
    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try writeFloat(&arr.writer, @as(f16, @floatCast(0.0)));

    try std.testing.expectEqualSlices(u8, "\xf9\x00\x00", arr.written());
}

test "write float #2" {
    const allocator = std.testing.allocator;
    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try writeFloat(&arr.writer, @as(f16, @floatCast(-0.0)));

    try std.testing.expectEqualSlices(u8, "\xf9\x80\x00", arr.written());
}

test "write float #3" {
    const allocator = std.testing.allocator;
    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try writeFloat(&arr.writer, @as(f32, @floatCast(3.4028234663852886e+38)));

    try std.testing.expectEqualSlices(u8, "\xfa\x7f\x7f\xff\xff", arr.written());
}

test "write float #4" {
    const allocator = std.testing.allocator;
    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try writeFloat(&arr.writer, @as(f64, @floatCast(-4.1)));

    try std.testing.expectEqualSlices(u8, "\xfb\xc0\x10\x66\x66\x66\x66\x66\x66", arr.written());
}
