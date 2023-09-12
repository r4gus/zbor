const std = @import("std");

/// CBOR type (see RFC 8949)
pub const Type = enum {
    /// Integer in the range -2^64..2^64 - 1 (MT 0/1)
    Int,
    /// Byte string (MT 2)
    ByteString,
    /// UTF-8 text string (MT 3)
    TextString,
    /// Array of data items (MT 4)
    Array,
    /// Map of pairs of data items (MT 5)
    Map,
    /// False (MT 7)
    False,
    /// True (MT 7)
    True,
    /// Null (MT 7)
    Null,
    /// Undefined (MT 7)
    Undefined,
    /// Simple value (MT 7)
    Simple,
    /// Tagged data item whose tag number is an integer in the range 0..2^64 - 1 (MT 6)
    Tagged,
    /// Floating point value (MT 7)
    Float,
    /// Unknown data item
    Unknown,

    /// Detect the data item type encoded within a raw byte
    pub fn fromByte(b: u8) @This() {
        return switch (b) {
            0x00...0x3b => .Int,
            0x40...0x5b => .ByteString,
            0x60...0x7b => .TextString,
            0x80...0x9b => .Array,
            0xa0...0xbb => .Map,
            0xf4 => .False,
            0xf5 => .True,
            0xf6 => .Null,
            0xf7 => .Undefined,
            0xe0...0xf3, 0xf8 => .Simple,
            0xc0...0xdb => .Tagged,
            0xf9...0xfb => .Float,
            else => .Unknown,
        };
    }
};

/// DataItem is a wrapper around raw CBOR data
pub const DataItem = struct {
    /// Raw CBOR data
    data: []const u8,

    /// Create a new DataItem from raw CBOR data
    ///
    /// This function will run a check to verify that the data is not malfromed as defined by RFC 8949
    /// before returning a DataItem. Returns an error if the data is malformed.
    pub fn new(data: []const u8) !@This() {
        var i: usize = 0;
        if (!validate(data, &i, false)) return error.Malformed;
        return .{ .data = data };
    }

    /// Get the Type of the given DataItem
    pub fn getType(self: @This()) Type {
        return Type.fromByte(self.data[0]);
    }

    /// Decode the given DataItem into an integer
    ///
    /// The function will return null if the given DataItems doesn't have the
    /// tpye Type.Int.
    pub fn int(self: @This()) ?i65 {
        if (self.data[0] <= 0x1b and self.data[0] >= 0x00) {
            return @as(i65, @intCast(if (additionalInfo(self.data, null)) |v| v else return null));
        } else if (self.data[0] <= 0x3b and self.data[0] >= 0x20) {
            return -@as(i65, @intCast(if (additionalInfo(self.data, null)) |v| v else return null)) - 1;
        } else {
            return null;
        }
    }

    /// Decode the given DataItem into a string
    ///
    /// The function will return null if the given DataItems doesn't have the
    /// tpye Type.ByteString or Type.TextString.
    pub fn string(self: @This()) ?[]const u8 {
        const T = Type.fromByte(self.data[0]);
        if (T != Type.ByteString and T != Type.TextString) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @as(usize, @intCast(v)) else return null;

        return self.data[begin .. begin + len];
    }

    /// Decode the given DataItem into a array
    ///
    /// This function will return an ArrayIterator on success and null if
    /// the given DataItem doesn't have the type Type.Array.
    pub fn array(self: @This()) ?ArrayIterator {
        const T = Type.fromByte(self.data[0]);
        if (T != Type.Array) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @as(usize, @intCast(v)) else return null;

        // Get to the end of the array
        var end: usize = 0;
        if (burn(self.data, &end) == null) return null;

        return ArrayIterator{
            .data = self.data[begin..end],
            .len = len,
            .count = 0,
            .i = 0,
        };
    }

    /// Decode the given DataItem into a map
    ///
    /// This function will return an MapIterator on success and null if
    /// the given DataItem doesn't have the type Type.Map.
    pub fn map(self: @This()) ?MapIterator {
        const T = Type.fromByte(self.data[0]);
        if (T != Type.Map) return null;

        var begin: usize = 0;
        var len = if (additionalInfo(self.data, &begin)) |v| @as(usize, @intCast(v)) else return null;

        // Get to the end of the map
        var end: usize = 0;
        if (burn(self.data, &end) == null) return null;

        return MapIterator{
            .data = self.data[begin..end],
            .len = len,
            .count = 0,
            .i = 0,
        };
    }

    /// Decode the given DataItem into a simple value
    ///
    /// This function will return null if the DataItems type
    /// is not Type.Simple, Type.False, Type.True, Type.Null
    /// or Type.Undefined.
    pub fn simple(self: @This()) ?u8 {
        return switch (self.data[0]) {
            0xe0...0xf7 => self.data[0] & 0x1f,
            0xf8 => self.data[1],
            else => null,
        };
    }

    /// Decode the given DataItem into a boolean
    ///
    /// Returns null if the DataItem's type is not
    /// Type.False or Type.True.
    pub fn boolean(self: @This()) ?bool {
        return switch (self.data[0]) {
            0xf4 => false,
            0xf5 => true,
            else => null,
        };
    }

    /// Decode the given DataItem into a float
    ///
    /// This function will return null if the DataItem
    /// isn't a half-, single-, or double precision
    /// floating point value.
    pub fn float(self: @This()) ?f64 {
        const T = Type.fromByte(self.data[0]);
        if (T != Type.Float) return null;

        if (additionalInfo(self.data, null)) |v| {
            return switch (self.data[0]) {
                0xf9 => @as(f64, @floatCast(@as(f16, @bitCast(@as(u16, @intCast(v)))))),
                0xfa => @as(f64, @floatCast(@as(f32, @bitCast(@as(u32, @intCast(v)))))),
                0xfb => @as(f64, @bitCast(v)),
                else => unreachable,
            };
        } else {
            return null;
        }
    }

    /// Decode the given DataItem into a Tag
    ///
    /// This function will return null if the DataItem
    /// isn't of type Type.Tagged.
    pub fn tagged(self: @This()) ?Tag {
        const T = Type.fromByte(self.data[0]);
        if (T != Type.Tagged) return null;

        var begin: usize = 0;
        var nr = if (additionalInfo(self.data, &begin)) |v| v else return null;

        return Tag{
            .nr = nr,
            .content = DataItem.new(self.data[begin..]) catch {
                unreachable; // this can only be if DataItem hasn't been instantiated with new()
            },
        };
    }
};

/// Representaion of a tagged data item
pub const Tag = struct {
    /// The tag of the data item
    nr: u64,
    /// The data item being tagged
    content: DataItem,
};

/// The key-value pair of a map
pub const Pair = struct {
    key: DataItem,
    value: DataItem,
};

/// Iterator for iterating over a map, returned by DataItem.map()
pub const MapIterator = struct {
    data: []const u8,
    len: usize,
    count: usize,
    i: usize,

    /// Get the next key Pair
    ///
    /// Returns null after the last element.
    pub fn next(self: *@This()) ?Pair {
        if (self.count >= self.len) return null;
        var new_i: usize = self.i;

        if (burn(self.data, &new_i) == null) return null;
        const k = DataItem.new(self.data[self.i..new_i]) catch {
            unreachable; // this can only be if DataItem hasn't been instantiated with new()
        };
        self.i = new_i;

        if (burn(self.data, &new_i) == null) return null;
        const v = DataItem.new(self.data[self.i..new_i]) catch {
            unreachable; // this can only be if DataItem hasn't been instantiated with new()
        };
        self.i = new_i;

        self.count += 1;
        return Pair{ .key = k, .value = v };
    }
};

/// Iterator for iterating over an array, returned by DataItem.array()
pub const ArrayIterator = struct {
    data: []const u8,
    len: usize,
    count: usize,
    i: usize,

    /// Get the next DataItem
    ///
    /// Returns null after the last element.
    pub fn next(self: *@This()) ?DataItem {
        if (self.count >= self.len) return null;

        var new_i: usize = self.i;
        if (burn(self.data, &new_i) == null) return null;

        const tmp = self.data[self.i..new_i];
        self.i = new_i;
        self.count += 1;
        return DataItem.new(tmp) catch {
            unreachable;
        };
    }
};

/// Move the index `i` to the beginning of the next data item.
fn burn(data: []const u8, i: *usize) ?void {
    var offset: usize = 0;
    const len = if (additionalInfo(data[i.*..], &offset)) |v| @as(usize, @intCast(v)) else return null;

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
        0xc0...0xdb => {
            i.* += offset;
            if (burn(data, i) == null) return null;
        },
        0xe0...0xfb => i.* += offset,
        else => return null,
    }
}

/// Return the additional information of the given data item.
///
/// Pass a reference to `l` if you want to know where the
/// actual data begins (l := |head| + |additional information|).
fn additionalInfo(data: []const u8, l: ?*usize) ?u64 {
    if (data.len < 1) return null;

    switch (data[0] & 0x1f) {
        0x00...0x17 => {
            if (l != null) l.?.* = 1;
            return @as(u64, @intCast(data[0] & 0x1f));
        },
        0x18 => {
            if (data.len < 2) return null;
            if (l != null) l.?.* = 2;
            return @as(u64, @intCast(data[1]));
        },
        0x19 => {
            if (data.len < 3) return null;
            if (l != null) l.?.* = 3;
            return @as(u64, @intCast(unsigned_16(data[1..3])));
        },
        0x1a => {
            if (data.len < 5) return null;
            if (l != null) l.?.* = 5;
            return @as(u64, @intCast(unsigned_32(data[1..5])));
        },
        0x1b => {
            if (data.len < 9) return null;
            if (l != null) l.?.* = 9;
            return @as(u64, @intCast(unsigned_64(data[1..9])));
        },
        else => return null,
    }
}

/// Check if the given CBOR data is well formed
///
/// * `data` - Raw CBOR data
/// * `i` - Pointer to an index (must be initialized to 0)
/// * `check_len` - It's important that `data` doesn't contain any extra bytes at the end [Yes/no]
///
/// Returns true if the given data is well formed, false otherwise.
pub fn validate(data: []const u8, i: *usize, check_len: bool) bool {
    if (i.* >= data.len) return false;
    const ib = data[i.*];
    i.* += 1;
    const mt = ib >> 5;
    const ai = ib & 0x1f;
    var val: usize = @as(usize, @intCast(ai));

    switch (ai) {
        24, 25, 26, 27 => {
            const bytes = @as(usize, @intCast(1)) << @intCast(ai - 24);
            if (i.* + bytes > data.len) return false;
            val = 0;
            for (data[i.* .. i.* + bytes]) |byte| {
                val <<= 8;
                val += byte;
            }
            i.* += bytes;
        },
        28, 29, 30 => return false,
        31 => return false, // we dont support indefinite length items for now
        else => {},
    }

    switch (mt) {
        2, 3 => i.* += val,
        4 => {
            var j: usize = 0;
            while (j < val) : (j += 1) {
                if (!validate(data, i, false)) return false;
            }
        },
        5 => {
            var j: usize = 0;
            while (j < val * 2) : (j += 1) {
                if (!validate(data, i, false)) return false;
            }
        },
        6 => if (!validate(data, i, false)) return false,
        7 => if (ai == 24 and val < 32) return false,
        else => {},
    }

    // no bytes must be left in the input
    if (check_len and i.* != data.len) return false;
    return true;
}

pub inline fn unsigned_16(data: []const u8) u16 {
    return @as(u16, @intCast(data[0])) << 8 | @as(u16, @intCast(data[1]));
}

pub inline fn unsigned_32(data: []const u8) u32 {
    return @as(u32, @intCast(data[0])) << 24 | @as(u32, @intCast(data[1])) << 16 | @as(u32, @intCast(data[2])) << 8 | @as(u32, @intCast(data[3]));
}

pub inline fn unsigned_64(data: []const u8) u64 {
    return @as(u64, @intCast(data[0])) << 56 | @as(u64, @intCast(data[1])) << 48 | @as(u64, @intCast(data[2])) << 40 | @as(u64, @intCast(data[3])) << 32 | @as(u64, @intCast(data[4])) << 24 | @as(u64, @intCast(data[5])) << 16 | @as(u64, @intCast(data[6])) << 8 | @as(u64, @intCast(data[7]));
}

pub inline fn encode_2(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 25);
    try cbor.writeByte(@as(u8, @intCast((v >> 8) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast(v & 0xff)));
}

pub inline fn encode_4(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 26);
    try cbor.writeByte(@as(u8, @intCast((v >> 24) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 16) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 8) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast(v & 0xff)));
}

pub inline fn encode_8(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 27);
    try cbor.writeByte(@as(u8, @intCast((v >> 56) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 48) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 40) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 32) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 24) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 16) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast((v >> 8) & 0xff)));
    try cbor.writeByte(@as(u8, @intCast(v & 0xff)));
}

test "deserialize unsigned" {
    const di1 = try DataItem.new("\x00");
    try std.testing.expectEqual(Type.Int, di1.getType());
    try std.testing.expectEqual(di1.int().?, 0);

    const di2 = try DataItem.new("\x01");
    try std.testing.expectEqual(Type.Int, di2.getType());
    try std.testing.expectEqual(di2.int().?, 1);

    const di3 = try DataItem.new("\x17");
    try std.testing.expectEqual(Type.Int, di3.getType());
    try std.testing.expectEqual(di3.int().?, 23);

    const di4 = try DataItem.new("\x18\x18");
    try std.testing.expectEqual(Type.Int, di4.getType());
    try std.testing.expectEqual(di4.int().?, 24);

    const di5 = try DataItem.new("\x18\x64");
    try std.testing.expectEqual(Type.Int, di5.getType());
    try std.testing.expectEqual(di5.int().?, 100);

    const di6 = try DataItem.new("\x19\x03\xe8");
    try std.testing.expectEqual(Type.Int, di6.getType());
    try std.testing.expectEqual(di6.int().?, 1000);

    const di7 = try DataItem.new("\x1a\x00\x0f\x42\x40");
    try std.testing.expectEqual(Type.Int, di7.getType());
    try std.testing.expectEqual(di7.int().?, 1000000);

    const di8 = try DataItem.new("\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00");
    try std.testing.expectEqual(Type.Int, di8.getType());
    try std.testing.expectEqual(di8.int().?, 1000000000000);

    const di9 = try DataItem.new("\x1b\xff\xff\xff\xff\xff\xff\xff\xff");
    try std.testing.expectEqual(Type.Int, di9.getType());
    try std.testing.expectEqual(di9.int().?, 18446744073709551615);
}

test "deserialize negative" {
    const di1 = try DataItem.new("\x20");
    try std.testing.expectEqual(Type.Int, di1.getType());
    try std.testing.expectEqual(di1.int().?, -1);

    const di2 = try DataItem.new("\x29");
    try std.testing.expectEqual(Type.Int, di2.getType());
    try std.testing.expectEqual(di2.int().?, -10);

    const di3 = try DataItem.new("\x38\x63");
    try std.testing.expectEqual(Type.Int, di3.getType());
    try std.testing.expectEqual(di3.int().?, -100);

    const di6 = try DataItem.new("\x39\x03\xe7");
    try std.testing.expectEqual(Type.Int, di6.getType());
    try std.testing.expectEqual(di6.int().?, -1000);

    const di9 = try DataItem.new("\x3b\xff\xff\xff\xff\xff\xff\xff\xff");
    try std.testing.expectEqual(Type.Int, di9.getType());
    try std.testing.expectEqual(di9.int().?, -18446744073709551616);
}

test "deserialize byte string" {
    const di1 = try DataItem.new("\x40");
    try std.testing.expectEqual(Type.ByteString, di1.getType());
    try std.testing.expectEqualSlices(u8, di1.string().?, "");

    const di2 = try DataItem.new("\x44\x01\x02\x03\x04");
    try std.testing.expectEqual(Type.ByteString, di2.getType());
    try std.testing.expectEqualSlices(u8, di2.string().?, "\x01\x02\x03\x04");
}

test "deserialize text string" {
    const di1 = try DataItem.new("\x60");
    try std.testing.expectEqual(Type.TextString, di1.getType());
    try std.testing.expectEqualStrings(di1.string().?, "");

    const di2 = try DataItem.new("\x61\x61");
    try std.testing.expectEqual(Type.TextString, di2.getType());
    try std.testing.expectEqualStrings(di2.string().?, "a");

    const di3 = try DataItem.new("\x64\x49\x45\x54\x46");
    try std.testing.expectEqual(Type.TextString, di3.getType());
    try std.testing.expectEqualStrings(di3.string().?, "IETF");

    const di4 = try DataItem.new("\x62\x22\x5c");
    try std.testing.expectEqual(Type.TextString, di4.getType());
    try std.testing.expectEqualStrings(di4.string().?, "\"\\");

    const di5 = try DataItem.new("\x62\xc3\xbc");
    try std.testing.expectEqual(Type.TextString, di5.getType());
    try std.testing.expectEqualStrings(di5.string().?, "ü");

    const di6 = try DataItem.new("\x63\xe6\xb0\xb4");
    try std.testing.expectEqual(Type.TextString, di6.getType());
    try std.testing.expectEqualStrings(di6.string().?, "水");
}

test "deserialize array" {
    const di1 = try DataItem.new("\x80");
    try std.testing.expectEqual(Type.Array, di1.getType());
    var ai1 = di1.array().?;
    try std.testing.expectEqual(ai1.next(), null);
    try std.testing.expectEqual(ai1.next(), null);

    const di2 = try DataItem.new("\x83\x01\x02\x03");
    try std.testing.expectEqual(Type.Array, di2.getType());
    var ai2 = di2.array().?;
    try std.testing.expectEqual(ai2.next().?.int().?, 1);
    try std.testing.expectEqual(ai2.next().?.int().?, 2);
    try std.testing.expectEqual(ai2.next().?.int().?, 3);
    try std.testing.expectEqual(ai2.next(), null);

    const di3 = try DataItem.new("\x98\x19\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19");
    try std.testing.expectEqual(Type.Array, di3.getType());
    var ai3 = di3.array().?;
    var i: u64 = 1;
    while (i <= 25) : (i += 1) {
        try std.testing.expectEqual(ai3.next().?.int().?, i);
    }
    try std.testing.expectEqual(ai3.next(), null);

    const di4 = try DataItem.new("\x83\x01\x82\x02\x03\x82\x04\x05");
    try std.testing.expectEqual(Type.Array, di4.getType());
    var ai4 = di4.array().?;
    try std.testing.expectEqual(ai4.next().?.int().?, 1);
    var ai4_1 = ai4.next().?.array().?;
    try std.testing.expectEqual(ai4_1.next().?.int().?, 2);
    try std.testing.expectEqual(ai4_1.next().?.int().?, 3);
    try std.testing.expectEqual(ai4_1.next(), null);
    var ai4_2 = ai4.next().?.array().?;
    try std.testing.expectEqual(ai4_2.next().?.int().?, 4);
    try std.testing.expectEqual(ai4_2.next().?.int().?, 5);
    try std.testing.expectEqual(ai4_2.next(), null);
    try std.testing.expectEqual(ai4.next(), null);
}

test "deserialize map" {
    const di1 = try DataItem.new("\xa0");
    try std.testing.expectEqual(Type.Map, di1.getType());
    var ai1 = di1.map().?;
    try std.testing.expectEqual(ai1.next(), null);
    try std.testing.expectEqual(ai1.next(), null);

    const di2 = try DataItem.new("\xa2\x01\x02\x03\x04");
    try std.testing.expectEqual(Type.Map, di2.getType());
    var ai2 = di2.map().?;
    const kv1 = ai2.next().?;
    try std.testing.expectEqual(kv1.key.int().?, 1);
    try std.testing.expectEqual(kv1.value.int().?, 2);
    const kv2 = ai2.next().?;
    try std.testing.expectEqual(kv2.key.int().?, 3);
    try std.testing.expectEqual(kv2.value.int().?, 4);
    try std.testing.expectEqual(ai2.next(), null);

    const di3 = try DataItem.new("\xa2\x61\x61\x01\x61\x62\x82\x02\x03");
    try std.testing.expectEqual(Type.Map, di3.getType());
    var ai3 = di3.map().?;
    const kv1_2 = ai3.next().?;
    try std.testing.expectEqualStrings("a", kv1_2.key.string().?);
    try std.testing.expectEqual(kv1_2.value.int().?, 1);
    const kv2_2 = ai3.next().?;
    try std.testing.expectEqualStrings("b", kv2_2.key.string().?);
    var ai3_1 = kv2_2.value.array().?;
    try std.testing.expectEqual(ai3_1.next().?.int().?, 2);
    try std.testing.expectEqual(ai3_1.next().?.int().?, 3);
    try std.testing.expectEqual(ai3_1.next(), null);
    try std.testing.expectEqual(ai3.next(), null);
}

test "deserialize other" {
    const di1 = try DataItem.new("\x82\x61\x61\xa1\x61\x62\x61\x63");
    try std.testing.expectEqual(Type.Array, di1.getType());
    var ai1 = di1.array().?;
    try std.testing.expectEqualStrings("a", ai1.next().?.string().?);
    var m1 = ai1.next().?.map().?;
    var kv1 = m1.next().?;
    try std.testing.expectEqualStrings("b", kv1.key.string().?);
    try std.testing.expectEqualStrings("c", kv1.value.string().?);
}

test "deserialize simple" {
    const di1 = try DataItem.new("\xf4");
    try std.testing.expectEqual(Type.False, di1.getType());
    try std.testing.expectEqual(di1.boolean().?, false);

    const di2 = try DataItem.new("\xf5");
    try std.testing.expectEqual(Type.True, di2.getType());
    try std.testing.expectEqual(di2.boolean().?, true);

    const di3 = try DataItem.new("\xf6");
    try std.testing.expectEqual(Type.Null, di3.getType());

    const di4 = try DataItem.new("\xf7");
    try std.testing.expectEqual(Type.Undefined, di4.getType());

    const di5 = try DataItem.new("\xf0");
    try std.testing.expectEqual(Type.Simple, di5.getType());
    try std.testing.expectEqual(di5.simple().?, 16);

    const di6 = try DataItem.new("\xf8\xff");
    try std.testing.expectEqual(Type.Simple, di6.getType());
    try std.testing.expectEqual(di6.simple().?, 255);
}

test "deserialize float" {
    const di1 = try DataItem.new("\xfb\x3f\xf1\x99\x99\x99\x99\x99\x9a");
    try std.testing.expectEqual(Type.Float, di1.getType());
    try std.testing.expectApproxEqAbs(di1.float().?, 1.1, 0.000000001);

    const di2 = try DataItem.new("\xf9\x3e\x00");
    try std.testing.expectEqual(Type.Float, di2.getType());
    try std.testing.expectApproxEqAbs(di2.float().?, 1.5, 0.000000001);

    const di3 = try DataItem.new("\xf9\x80\x00");
    try std.testing.expectEqual(Type.Float, di3.getType());
    try std.testing.expectApproxEqAbs(di3.float().?, -0.0, 0.000000001);

    const di4 = try DataItem.new("\xfb\x7e\x37\xe4\x3c\x88\x00\x75\x9c");
    try std.testing.expectEqual(Type.Float, di4.getType());
    try std.testing.expectApproxEqAbs(di4.float().?, 1.0e+300, 0.000000001);
}

test "deserialize tagged" {
    const di1 = try DataItem.new("\xc0\x74\x32\x30\x31\x33\x2d\x30\x33\x2d\x32\x31\x54\x32\x30\x3a\x30\x34\x3a\x30\x30\x5a");
    try std.testing.expectEqual(Type.Tagged, di1.getType());
    const t1 = di1.tagged().?;
    try std.testing.expectEqual(t1.nr, 0);
}

fn validateTest(data: []const u8, expected: bool) !void {
    var i: usize = 0;
    try std.testing.expectEqual(expected, validate(data, &i, true));
}

test "well formed" {
    try validateTest("\x00", true);
    try validateTest("\x01", true);
    try validateTest("\x0a", true);
    try validateTest("\x17", true);
    try validateTest("\x18\x18", true);
    try validateTest("\x18\x19", true);
    try validateTest("\x18\x64", true);
    try validateTest("\x19\x03\xe8", true);
}

test "malformed" {
    // Empty
    try validateTest("", false);

    // End of input in a head
    try validateTest("\x18", false);
    try validateTest("\x19", false);
    try validateTest("\x1a", false);
    try validateTest("\x1b", false);
    try validateTest("\x19\x01", false);
    try validateTest("\x1a\x01\x02", false);
    try validateTest("\x1b\x01\x02\x03\x04\x05\x06\x07", false);
    try validateTest("\x38", false);
    try validateTest("\x58", false);
    try validateTest("\x78", false);
    try validateTest("\x98", false);
    try validateTest("\x9a\x01\xff\x00", false);
    try validateTest("\xb8", false);
    try validateTest("\xd8", false);
    try validateTest("\xf8", false);
    try validateTest("\xf9\x00", false);
    try validateTest("\xfa\x00\x00", false);
    try validateTest("\xfb\x00\x00\x00", false);

    // Definite-length strings with short data
    try validateTest("\x41", false);
    try validateTest("\x61", false);
    try validateTest("\x5a\xff\xff\xff\xff\x00", false);
    //try validateTest("\x5b\xff\xff\xff\xff\xff\xff\xff\xff\x01\x02\x03", false); TODO: crashes
    try validateTest("\x7a\xff\xff\xff\xff\x00", false);
    try validateTest("\x7b\x7f\xff\xff\xff\xff\xff\xff\xff\x01\x02\x03", false);

    // Definite-length maps and arrays not closed with enough items
    try validateTest("\x81", false);
    try validateTest("\x81\x81\x81\x81\x81\x81\x81\x81\x81", false);
    try validateTest("\x82\x00", false);
    try validateTest("\xa1", false);
    try validateTest("\xa2\x01\x02", false);
    try validateTest("\xa1\x00", false);
    try validateTest("\xa2\x00\x00\x00", false);

    // Tag number not followed by tag content
    try validateTest("\xc0", false);

    // Reserved additional information values
    try validateTest("\x1c", false);
    try validateTest("\x1d", false);
    try validateTest("\x1e", false);
    try validateTest("\x3c", false);
    try validateTest("\x3d", false);
    try validateTest("\x3e", false);
    try validateTest("\x5c", false);
    try validateTest("\x5d", false);
    try validateTest("\x5e", false);
    try validateTest("\x7c", false);
    try validateTest("\x7d", false);
    try validateTest("\x7e", false);
    try validateTest("\x9c", false);
    try validateTest("\x9d", false);
    try validateTest("\x9e", false);
    try validateTest("\xbc", false);
    try validateTest("\xbd", false);
    try validateTest("\xbe", false);
    try validateTest("\xdc", false);
    try validateTest("\xdd", false);
    try validateTest("\xde", false);
    try validateTest("\xfc", false);
    try validateTest("\xfd", false);
    try validateTest("\xfe", false);

    // Reserved two-byte encodings of simple values
    try validateTest("\xf8\x00", false);
    try validateTest("\xf8\x01", false);
    try validateTest("\xf8\x18", false);
    try validateTest("\xf8\x1f", false);

    // Break occuring on its own outside of an indifinite-length item
    try validateTest("\xff", false);

    // Break occuring in a definite-length array or map or a tag
    try validateTest("\x81\xff", false);
    try validateTest("\x82\x00\xff", false);
    try validateTest("\xa1\xff", false);
    try validateTest("\xa1\xff\x00", false);
    try validateTest("\xa1\x00\xff", false);
    try validateTest("\xa2\x00\x00\xff", false);
    try validateTest("\x9f\x81\xff", false);
    try validateTest("\x9f\x82\x9f\x81\x9f\x9f\xff\xff\xff\xff", false);
}
