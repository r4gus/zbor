const std = @import("std");

pub const Error = error{
    Malformed,
    TypeMismatch,
};

pub const Type = enum {
    Unsigned,
    Negative,
    ByteString,
    TextString,
    Array,
    Map,
    False,
    True,
    Null,
    Simple,
    Undefined,
    UnsignedBignum,
    Unknown,

    pub fn fromByte(b: u8) @This() {
        return switch (b) {
            0x00...0x1b => .Unsigned,
            0x20...0x3b => .Negative,
            0x40...0x5b => .ByteString,
            0x60...0x7b => .TextString,
            0x80...0x9b => .Array,
            0xa0...0xbb => .Map,
            0xf4 => .False,
            0xf5 => .True,
            0xf6 => .Null,
            0xf7 => .Undefined,
            0xe0...0xf3, 0xf8 => .Simple,
            0xc2 => .UnsignedBignum, // TODO: implement
            else => .Unknown,
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

    pub fn unsigned(self: @This()) ?u64 {
        if (self.data[0] > 0x1b) return null;

        return additionalInfo(self.data, null);
    }

    pub fn negative(self: @This()) ?i65 {
        if (self.data[0] > 0x3b or self.data[0] < 0x20) return null;

        return switch (self.data[0]) {
            0x20...0x3b => -@intCast(i65, additionalInfo(self.data, null).?) - 1,
            else => null,
        };
    }

    pub fn byteString(self: @This()) ?[]const u8 {
        if (self.data[0] > 0x5b or self.data[0] < 0x40) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @intCast(usize, v) else return null;
        return self.data[begin .. begin + len];
    }

    pub fn textString(self: @This()) ?[]const u8 {
        if (self.data[0] > 0x7b or self.data[0] < 0x60) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @intCast(usize, v) else return null;
        return self.data[begin .. begin + len];
    }

    pub fn array(self: @This()) ?ArrayIterator {
        if (self.data[0] > 0x9b or self.data[0] < 0x80) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @intCast(usize, v) else return null;

        return ArrayIterator{
            .data = self.data[begin..],
            .len = len,
            .count = 0,
            .i = 0,
        };
    }

    pub fn map(self: @This()) ?MapIterator {
        if (self.data[0] > 0xbb or self.data[0] < 0xa0) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @intCast(usize, v) else return null;

        return MapIterator{
            .data = self.data[begin..],
            .len = len,
            .count = 0,
            .i = 0,
        };
    }

    pub fn simple(self: @This()) ?u8 {
        return switch (self.data[0]) {
            0xe0...0xf3 => self.data[0] & 0x1f,
            0xf8 => self.data[1],
            else => null,
        };
    }
};

pub const Pair = struct {
    key: DataItem,
    value: DataItem,
};

pub const MapIterator = struct {
    data: []const u8,
    len: usize,
    count: usize,
    i: usize,

    pub fn next(self: *@This()) ?Pair {
        if (self.count >= self.len) return null;
        var new_i: usize = self.i;

        if (burn(self.data, &new_i) == null) return null;
        const k = DataItem.new(self.data[self.i..new_i]);
        self.i = new_i;

        if (burn(self.data, &new_i) == null) return null;
        const v = DataItem.new(self.data[self.i..new_i]);
        self.i = new_i;

        self.count += 1;
        return Pair{ .key = k, .value = v };
    }
};

pub const ArrayIterator = struct {
    data: []const u8,
    len: usize,
    count: usize,
    i: usize,

    pub fn next(self: *@This()) ?DataItem {
        if (self.count >= self.len) return null;

        var new_i: usize = self.i;
        if (burn(self.data, &new_i) == null) return null;

        const tmp = self.data[self.i..new_i];
        self.i = new_i;
        self.count += 1;
        return DataItem.new(tmp);
    }
};

/// Move the index `i` to the beginning of the next data item.
fn burn(data: []const u8, i: *usize) ?void {
    var offset: usize = 0;
    const len = if (additionalInfo(data[i.*..], &offset)) |v| @intCast(usize, v) else return null;

    switch (data[i.*]) {
        0x00...0x1b => i.* += offset,
        0x20...0x3b => i.* += offset,
        0x40...0x5b => i.* += offset + len,
        0x60...0x7b => i.* += offset + len,
        0x80...0x9b => {
            i.* += offset;
            var x: usize = 0;
            while (x < len) : (x += 1) {
                if (burn(data, i) == null) {
                    return null;
                }
            }
        },
        0xa0...0xbb => {
            i.* += offset;
            var x: usize = 0;
            while (x < len) : (x += 1) {
                // this is NOT redundant!!!
                if (burn(data, i) == null or burn(data, i) == null) {
                    return null;
                }
            }
        },
        0xe0...0xfb => i.* += offset,
        else => return null,
    }
}

/// Return the additional information of the given data item.
///
/// Pass a reference to `l` if you want to know where the
/// actual data begins (|head| + |additional information|).
fn additionalInfo(data: []const u8, l: ?*usize) ?u64 {
    if (data.len < 1) return null;

    switch (data[0] & 0x1f) {
        0x00...0x17 => {
            if (l != null) l.?.* = 1;
            return @intCast(u64, data[0] & 0x1f);
        },
        0x18 => {
            if (data.len < 2) return null;
            if (l != null) l.?.* = 2;
            return @intCast(u64, data[1]);
        },
        0x19 => {
            if (data.len < 3) return null;
            if (l != null) l.?.* = 3;
            return @intCast(u64, unsigned_16(data[1..3]));
        },
        0x1a => {
            if (data.len < 5) return null;
            if (l != null) l.?.* = 5;
            return @intCast(u64, unsigned_32(data[1..5]));
        },
        0x1b => {
            if (data.len < 9) return null;
            if (l != null) l.?.* = 9;
            return @intCast(u64, unsigned_64(data[1..9]));
        },
        else => return null,
    }
}

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
    try std.testing.expectEqual(di1.unsigned().?, 0);

    const di2 = DataItem.new("\x01");
    try std.testing.expectEqual(Type.Unsigned, di2.getType());
    try std.testing.expectEqual(di2.unsigned().?, 1);

    const di3 = DataItem.new("\x17");
    try std.testing.expectEqual(Type.Unsigned, di3.getType());
    try std.testing.expectEqual(di3.unsigned().?, 23);

    const di4 = DataItem.new("\x18\x18");
    try std.testing.expectEqual(Type.Unsigned, di4.getType());
    try std.testing.expectEqual(di4.unsigned().?, 24);

    const di5 = DataItem.new("\x18\x64");
    try std.testing.expectEqual(Type.Unsigned, di5.getType());
    try std.testing.expectEqual(di5.unsigned().?, 100);

    const di6 = DataItem.new("\x19\x03\xe8");
    try std.testing.expectEqual(Type.Unsigned, di6.getType());
    try std.testing.expectEqual(di6.unsigned().?, 1000);

    const di7 = DataItem.new("\x1a\x00\x0f\x42\x40");
    try std.testing.expectEqual(Type.Unsigned, di7.getType());
    try std.testing.expectEqual(di7.unsigned().?, 1000000);

    const di8 = DataItem.new("\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00");
    try std.testing.expectEqual(Type.Unsigned, di8.getType());
    try std.testing.expectEqual(di8.unsigned().?, 1000000000000);

    const di9 = DataItem.new("\x1b\xff\xff\xff\xff\xff\xff\xff\xff");
    try std.testing.expectEqual(Type.Unsigned, di9.getType());
    try std.testing.expectEqual(di9.unsigned().?, 18446744073709551615);
}

test "deserialize negative" {
    const di1 = DataItem.new("\x20");
    try std.testing.expectEqual(Type.Negative, di1.getType());
    try std.testing.expectEqual(di1.negative().?, -1);

    const di2 = DataItem.new("\x29");
    try std.testing.expectEqual(Type.Negative, di2.getType());
    try std.testing.expectEqual(di2.negative().?, -10);

    const di3 = DataItem.new("\x38\x63");
    try std.testing.expectEqual(Type.Negative, di3.getType());
    try std.testing.expectEqual(di3.negative().?, -100);

    const di6 = DataItem.new("\x39\x03\xe7");
    try std.testing.expectEqual(Type.Negative, di6.getType());
    try std.testing.expectEqual(di6.negative().?, -1000);

    const di9 = DataItem.new("\x3b\xff\xff\xff\xff\xff\xff\xff\xff");
    try std.testing.expectEqual(Type.Negative, di9.getType());
    try std.testing.expectEqual(di9.negative().?, -18446744073709551616);
}

test "deserialize byte string" {
    const di1 = DataItem.new("\x40");
    try std.testing.expectEqual(Type.ByteString, di1.getType());
    try std.testing.expectEqualSlices(u8, di1.byteString().?, "");

    const di2 = DataItem.new("\x44\x01\x02\x03\x04");
    try std.testing.expectEqual(Type.ByteString, di2.getType());
    try std.testing.expectEqualSlices(u8, di2.byteString().?, "\x01\x02\x03\x04");
}

test "deserialize text string" {
    const di1 = DataItem.new("\x60");
    try std.testing.expectEqual(Type.TextString, di1.getType());
    try std.testing.expectEqualStrings(di1.textString().?, "");

    const di2 = DataItem.new("\x61\x61");
    try std.testing.expectEqual(Type.TextString, di2.getType());
    try std.testing.expectEqualStrings(di2.textString().?, "a");

    const di3 = DataItem.new("\x64\x49\x45\x54\x46");
    try std.testing.expectEqual(Type.TextString, di3.getType());
    try std.testing.expectEqualStrings(di3.textString().?, "IETF");

    const di4 = DataItem.new("\x62\x22\x5c");
    try std.testing.expectEqual(Type.TextString, di4.getType());
    try std.testing.expectEqualStrings(di4.textString().?, "\"\\");

    const di5 = DataItem.new("\x62\xc3\xbc");
    try std.testing.expectEqual(Type.TextString, di5.getType());
    try std.testing.expectEqualStrings(di5.textString().?, "ü");

    const di6 = DataItem.new("\x63\xe6\xb0\xb4");
    try std.testing.expectEqual(Type.TextString, di6.getType());
    try std.testing.expectEqualStrings(di6.textString().?, "水");
}

test "deserialize array" {
    const di1 = DataItem.new("\x80");
    try std.testing.expectEqual(Type.Array, di1.getType());
    var ai1 = di1.array().?;
    try std.testing.expectEqual(ai1.next(), null);
    try std.testing.expectEqual(ai1.next(), null);

    const di2 = DataItem.new("\x83\x01\x02\x03");
    try std.testing.expectEqual(Type.Array, di2.getType());
    var ai2 = di2.array().?;
    try std.testing.expectEqual(ai2.next().?.unsigned().?, 1);
    try std.testing.expectEqual(ai2.next().?.unsigned().?, 2);
    try std.testing.expectEqual(ai2.next().?.unsigned().?, 3);
    try std.testing.expectEqual(ai2.next(), null);

    const di3 = DataItem.new("\x98\x19\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19");
    try std.testing.expectEqual(Type.Array, di3.getType());
    var ai3 = di3.array().?;
    var i: u64 = 1;
    while (i <= 25) : (i += 1) {
        try std.testing.expectEqual(ai3.next().?.unsigned().?, i);
    }
    try std.testing.expectEqual(ai3.next(), null);

    const di4 = DataItem.new("\x83\x01\x82\x02\x03\x82\x04\x05");
    try std.testing.expectEqual(Type.Array, di4.getType());
    var ai4 = di4.array().?;
    try std.testing.expectEqual(ai4.next().?.unsigned().?, 1);
    var ai4_1 = ai4.next().?.array().?;
    try std.testing.expectEqual(ai4_1.next().?.unsigned().?, 2);
    try std.testing.expectEqual(ai4_1.next().?.unsigned().?, 3);
    try std.testing.expectEqual(ai4_1.next(), null);
    var ai4_2 = ai4.next().?.array().?;
    try std.testing.expectEqual(ai4_2.next().?.unsigned().?, 4);
    try std.testing.expectEqual(ai4_2.next().?.unsigned().?, 5);
    try std.testing.expectEqual(ai4_2.next(), null);
    try std.testing.expectEqual(ai4.next(), null);
}

test "deserialize map" {
    const di1 = DataItem.new("\xa0");
    try std.testing.expectEqual(Type.Map, di1.getType());
    var ai1 = di1.map().?;
    try std.testing.expectEqual(ai1.next(), null);
    try std.testing.expectEqual(ai1.next(), null);

    const di2 = DataItem.new("\xa2\x01\x02\x03\x04");
    try std.testing.expectEqual(Type.Map, di2.getType());
    var ai2 = di2.map().?;
    const kv1 = ai2.next().?;
    try std.testing.expectEqual(kv1.key.unsigned().?, 1);
    try std.testing.expectEqual(kv1.value.unsigned().?, 2);
    const kv2 = ai2.next().?;
    try std.testing.expectEqual(kv2.key.unsigned().?, 3);
    try std.testing.expectEqual(kv2.value.unsigned().?, 4);
    try std.testing.expectEqual(ai2.next(), null);

    const di3 = DataItem.new("\xa2\x61\x61\x01\x61\x62\x82\x02\x03");
    try std.testing.expectEqual(Type.Map, di3.getType());
    var ai3 = di3.map().?;
    const kv1_2 = ai3.next().?;
    try std.testing.expectEqualStrings("a", kv1_2.key.textString().?);
    try std.testing.expectEqual(kv1_2.value.unsigned().?, 1);
    const kv2_2 = ai3.next().?;
    try std.testing.expectEqualStrings("b", kv2_2.key.textString().?);
    var ai3_1 = kv2_2.value.array().?;
    try std.testing.expectEqual(ai3_1.next().?.unsigned().?, 2);
    try std.testing.expectEqual(ai3_1.next().?.unsigned().?, 3);
    try std.testing.expectEqual(ai3_1.next(), null);
    try std.testing.expectEqual(ai3.next(), null);
}

test "deserialize other" {
    const di1 = DataItem.new("\x82\x61\x61\xa1\x61\x62\x61\x63");
    try std.testing.expectEqual(Type.Array, di1.getType());
    var ai1 = di1.array().?;
    try std.testing.expectEqualStrings("a", ai1.next().?.textString().?);
    var m1 = ai1.next().?.map().?;
    var kv1 = m1.next().?;
    try std.testing.expectEqualStrings("b", kv1.key.textString().?);
    try std.testing.expectEqualStrings("c", kv1.value.textString().?);
}

test "deserialize simple" {
    const di1 = DataItem.new("\xf4");
    try std.testing.expectEqual(Type.False, di1.getType());

    const di2 = DataItem.new("\xf5");
    try std.testing.expectEqual(Type.True, di2.getType());

    const di3 = DataItem.new("\xf6");
    try std.testing.expectEqual(Type.Null, di3.getType());

    const di4 = DataItem.new("\xf7");
    try std.testing.expectEqual(Type.Undefined, di4.getType());

    const di5 = DataItem.new("\xf0");
    try std.testing.expectEqual(Type.Simple, di5.getType());
    try std.testing.expectEqual(di5.simple().?, 16);

    const di6 = DataItem.new("\xf8\xff");
    try std.testing.expectEqual(Type.Simple, di6.getType());
    try std.testing.expectEqual(di6.simple().?, 255);
}
