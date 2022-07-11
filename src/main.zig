const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const CborError = error{
    // Indicates that one of the reserved values 28, 29 or 30 has been used.
    ReservedAdditionalInformation,
    // Default error.
    Default,
    OutOfMemory,
};

const Pair = struct { key: DataItem, value: DataItem };

const Tag = struct { number: u64, content: *DataItem, allocator: Allocator };

const FloatTag = enum { float16, float32, float64 };

const Float = union(FloatTag) {
    /// IEEE 754 Half-Precision Float (16 bits follow)
    float16: f16,
    /// IEEE 754 Single-Precision Float (32 bits follow)
    float32: f32,
    /// IEEE 754 Double-Precision Float (64 bits follow)
    float64: f64,
};

const DataItemTag = enum { int, bytes, text, array, map, tag, float };

const DataItem = union(DataItemTag) {
    /// Major type 0 and 1: An integer in the range -2^64..2^64-1
    int: i128,
    /// Major type 2: A byte string.
    bytes: std.ArrayList(u8),
    /// Major type 3: A text string encoded as utf-8.
    text: std.ArrayList(u8),
    /// Major type 4: An array of data items.
    array: std.ArrayList(DataItem),
    /// Major type 5: A map of pairs of data items.
    map: std.ArrayList(Pair),
    /// Major type 6: A tagged data item.
    tag: Tag,
    /// IEEE 754 Half-, Single-, or Double-Precision float.
    float: Float,

    fn deinit(self: @This()) void {
        switch (self) {
            .int => |_| {},
            .bytes => |list| list.deinit(),
            .text => |list| list.deinit(),
            .array => |arr| {
                // We must deinitialize each item of the given array...
                for (arr.items) |item| {
                    item.deinit();
                }
                // ...before deinitializing the ArrayList itself.
                arr.deinit();
            },
            .map => |m| {
                for (m.items) |item| {
                    item.key.deinit();
                    item.value.deinit();
                }
                m.deinit();
            },
            .tag => |t| {
                // First free the allocated memory of the nested data items...
                t.content.*.deinit();
                // ...then free the memory of the content.
                t.allocator.destroy(t.content);
            },
            .float => |_| {},
        }
    }

    fn equal(self: *const @This(), other: *const @This()) bool {
        // self and other hold different types, i.e. can't be equal.
        if (@as(DataItemTag, self.*) != @as(DataItemTag, other.*)) {
            return false;
        }

        switch (self.*) {
            .int => |value| return value == other.*.int,
            .bytes => |list| return std.mem.eql(u8, list.items, other.*.bytes.items),
            .text => |list| return std.mem.eql(u8, list.items, other.*.text.items),
            .array => |arr| {
                if (arr.items.len != other.*.array.items.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < arr.items.len) : (i += 1) {
                    if (!arr.items[i].equal(&other.*.array.items[i])) {
                        return false;
                    }
                }

                return true;
            },
            .map => |m| {
                if (m.items.len != other.*.map.items.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < m.items.len) : (i += 1) {
                    if (!m.items[i].key.equal(&other.*.map.items[i].key) or
                        !m.items[i].value.equal(&other.*.map.items[i].value))
                    {
                        return false;
                    }
                }

                return true;
            },
            .tag => |t| {
                return t.number == other.tag.number and
                    t.content.*.equal(other.tag.content);
            },
            .float => |f| {
                if (@as(FloatTag, f) != @as(FloatTag, other.float)) {
                    return false;
                }

                switch (f) {
                    .float16 => |fv| return fv == other.float.float16,
                    .float32 => |fv| return fv == other.float.float32,
                    .float64 => |fv| return fv == other.float.float64,
                }
            },
        }
    }
};

// calling function is responsible for deallocating memory.
fn decode_(data: []const u8, index: *usize, allocator: Allocator, breakable: bool) CborError!DataItem {
    _ = breakable;
    const head: u8 = data[index.*];
    index.* += 1;
    const mt: u8 = head >> 5; // the 3 msb represent the major type.
    const ai: u8 = head & 0x1f; // the 5 lsb represent additional information.
    var val: u64 = @intCast(u64, ai);

    // Process data item head.
    switch (ai) {
        0...23 => {},
        24 => {
            val = data[index.*];
            index.* += 1;
        },
        25 => {
            val = @intCast(u64, data[index.*]) << 8;
            val |= @intCast(u64, data[index.* + 1]);
            index.* += 2;
        },
        26 => {
            val = @intCast(u64, data[index.*]) << 24;
            val |= @intCast(u64, data[index.* + 1]) << 16;
            val |= @intCast(u64, data[index.* + 2]) << 8;
            val |= @intCast(u64, data[index.* + 3]);
            index.* += 4;
        },
        27 => {
            val = @intCast(u64, data[index.*]) << 56;
            val |= @intCast(u64, data[index.* + 1]) << 48;
            val |= @intCast(u64, data[index.* + 2]) << 40;
            val |= @intCast(u64, data[index.* + 3]) << 32;
            val |= @intCast(u64, data[index.* + 4]) << 24;
            val |= @intCast(u64, data[index.* + 5]) << 16;
            val |= @intCast(u64, data[index.* + 6]) << 8;
            val |= @intCast(u64, data[index.* + 7]);
            index.* += 8;
        },
        28...30 => {
            return CborError.ReservedAdditionalInformation;
        },
        else => { // 31 (all other values are impossible)
            unreachable; // TODO: actually reachable but we pretend for now...
        },
    }

    // Process content.
    switch (mt) {
        // MT0: Unsigned int, e.g. 1, 10, 23, 25.
        0 => {
            return DataItem{ .int = @as(i128, val) };
        },
        // MT1: Signed int, e.g. -1, -10, -12345.
        1 => {
            // The value of the item is -1 minus the argument.
            return DataItem{ .int = -1 - @as(i128, val) };
        },
        // MT2: Byte string.
        // The number of bytes in the string is equal to the argument (val).
        2 => {
            var item = DataItem{ .bytes = std.ArrayList(u8).init(allocator) };
            try item.bytes.appendSlice(data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);
            return item;
        },
        // MT3: UTF-8 text string, e.g. "a", "IETF".
        3 => {
            var item = DataItem{ .text = std.ArrayList(u8).init(allocator) };
            try item.text.appendSlice(data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);
            return item;
        },
        // MT4: DataItem array, e.g. [], [1, 2, 3], [1, [2, 3], [4, 5]].
        4 => {
            var item = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                try item.array.append(try decode_(data, index, allocator, false));
            }
            return item;
        },
        // MT5: Map of pairs of DataItem, e.g. {1:2, 3:4}.
        5 => {
            var item = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                const k = try decode_(data, index, allocator, false);
                const v = try decode_(data, index, allocator, false);
                try item.map.append(Pair{ .key = k, .value = v });
            }
            return item;
        },
        // MT6: Tagged data item, e.g. 1("a").
        6 => {
            var item = try allocator.create(DataItem);
            // The enclosed data item (tag content) is the single encoded data
            // item that follows the head.
            item.* = try decode_(data, index, allocator, false);

            return DataItem{ .tag = Tag{ .number = val, .content = item, .allocator = allocator } };
        },
        7 => {
            switch (ai) {
                // The following narrowing conversions are fine because the
                // number of parsed bytes always matches the size of the float.
                25 => return DataItem{ .float = Float{ .float16 = @bitCast(f16, @intCast(u16, val)) } },
                26 => return DataItem{ .float = Float{ .float32 = @bitCast(f32, @intCast(u32, val)) } },
                27 => return DataItem{ .float = Float{ .float64 = @bitCast(f64, val) } },
                else => {},
            }
        },
        else => {
            unreachable;
        },
    }

    return CborError.Default;
}

const TestError = CborError || error{ TestExpectedEqual, TestUnexpectedResult };

fn test_data_item(data: []const u8, expected: DataItem) TestError!void {
    const allocator = std.testing.allocator;
    var index: usize = 0;
    const dip = try decode_(data, &index, allocator, false);
    defer dip.deinit();
    try std.testing.expectEqual(expected, dip);
}

fn test_data_item_eql(data: []const u8, expected: *DataItem) TestError!void {
    const allocator = std.testing.allocator;
    var index: usize = 0;
    const dip = try decode_(data, &index, allocator, false);
    defer dip.deinit();
    defer expected.*.deinit();
    try std.testing.expect(expected.*.equal(&dip));
}

test "DataItem.equal test" {
    const di1 = DataItem{ .int = 10 };
    const di2 = DataItem{ .int = 23 };
    const di3 = DataItem{ .int = 23 };
    const di4 = DataItem{ .int = -9988776655 };

    try std.testing.expect(!di1.equal(&di2));
    try std.testing.expect(di2.equal(&di3));
    try std.testing.expect(!di1.equal(&di4));
    try std.testing.expect(!di2.equal(&di4));
    try std.testing.expect(!di3.equal(&di4));

    var allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    var di5 = DataItem{ .bytes = list };
    defer di5.deinit();

    try std.testing.expect(!di5.equal(&di1));
    try std.testing.expect(!di1.equal(&di5));
    try std.testing.expect(di5.equal(&di5));

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    var di6 = DataItem{ .bytes = list2 };
    defer di6.deinit();

    try std.testing.expect(di5.equal(&di6));
    try di6.bytes.append(123);
    try std.testing.expect(!di5.equal(&di6));
}

test "MT0: decode cbor unsigned integer value" {
    try test_data_item(&.{0x00}, DataItem{ .int = 0 });
    try test_data_item(&.{0x01}, DataItem{ .int = 1 });
    try test_data_item(&.{0x0a}, DataItem{ .int = 10 });
    try test_data_item(&.{0x17}, DataItem{ .int = 23 });
    try test_data_item(&.{ 0x18, 0x18 }, DataItem{ .int = 24 });
    try test_data_item(&.{ 0x18, 0x19 }, DataItem{ .int = 25 });
    try test_data_item(&.{ 0x18, 0x64 }, DataItem{ .int = 100 });
    try test_data_item(&.{ 0x18, 0x7b }, DataItem{ .int = 123 });
    try test_data_item(&.{ 0x19, 0x03, 0xe8 }, DataItem{ .int = 1000 });
    try test_data_item(&.{ 0x19, 0x04, 0xd2 }, DataItem{ .int = 1234 });
    try test_data_item(&.{ 0x1a, 0x00, 0x01, 0xe2, 0x40 }, DataItem{ .int = 123456 });
    try test_data_item(&.{ 0x1a, 0x00, 0x0f, 0x42, 0x40 }, DataItem{ .int = 1000000 });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0x02, 0xdf, 0xdc, 0x1c, 0x34 }, DataItem{ .int = 12345678900 });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0xe8, 0xd4, 0xa5, 0x10, 0x00 }, DataItem{ .int = 1000000000000 });
    try test_data_item(&.{ 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .int = 18446744073709551615 });
}

test "MT1: decode cbor signed integer value" {
    try test_data_item(&.{0x20}, DataItem{ .int = -1 });
    try test_data_item(&.{0x22}, DataItem{ .int = -3 });
    try test_data_item(&.{ 0x38, 0x63 }, DataItem{ .int = -100 });
    try test_data_item(&.{ 0x39, 0x01, 0xf3 }, DataItem{ .int = -500 });
    try test_data_item(&.{ 0x39, 0x03, 0xe7 }, DataItem{ .int = -1000 });
    try test_data_item(&.{ 0x3a, 0x00, 0x0f, 0x3d, 0xdc }, DataItem{ .int = -998877 });
    try test_data_item(&.{ 0x3b, 0x00, 0x00, 0x00, 0x02, 0x53, 0x60, 0xa2, 0xce }, DataItem{ .int = -9988776655 });
    try test_data_item(&.{ 0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .int = -18446744073709551616 });
}

test "MT2: decode cbor byte string" {
    const allocator = std.testing.allocator;

    try test_data_item(&.{0b01000000}, DataItem{ .bytes = std.ArrayList(u8).init(allocator) });

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    try test_data_item_eql(&.{ 0b01000001, 0x0a }, &DataItem{ .bytes = list });

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    try list2.append(11);
    try list2.append(12);
    try list2.append(13);
    try list2.append(14);
    try test_data_item_eql(&.{ 0b01000101, 0x0a, 0xb, 0xc, 0xd, 0xe }, &DataItem{ .bytes = list2 });
}

test "MT3: decode cbor text string" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    try test_data_item(&.{0x60}, DataItem{ .text = std.ArrayList(u8).init(allocator) });

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    try list.appendSlice("a");
    const di = try decode_(&.{ 0x61, 0x61 }, &index, allocator, false);
    defer di.deinit();
    try std.testing.expectEqualSlices(u8, list.items, di.text.items);

    index = 0;
    var list2 = std.ArrayList(u8).init(allocator);
    defer list2.deinit();
    try list2.appendSlice("IETF");
    const di2 = try decode_(&.{ 0x64, 0x49, 0x45, 0x54, 0x46 }, &index, allocator, false);
    defer di2.deinit();
    try std.testing.expectEqualSlices(u8, list2.items, di2.text.items);

    index = 0;
    var list3 = std.ArrayList(u8).init(allocator);
    defer list3.deinit();
    try list3.appendSlice("\"\\");
    const di3 = try decode_(&.{ 0x62, 0x22, 0x5c }, &index, allocator, false);
    defer di3.deinit();
    try std.testing.expectEqualSlices(u8, list3.items, di3.text.items);

    // TODO: test unicode https://www.rfc-editor.org/rfc/rfc8949.html#name-examples-of-encoded-cbor-da
}

test "MT4: decode cbor array" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var list = std.ArrayList(DataItem).init(allocator);
    defer list.deinit();
    const di = try decode_(&.{0x80}, &index, allocator, false);
    defer di.deinit();
    try std.testing.expectEqualSlices(DataItem, list.items, di.array.items);

    index = 0;
    var list2 = std.ArrayList(DataItem).init(allocator);
    defer list2.deinit();
    try list2.append(DataItem{ .int = 1 });
    try list2.append(DataItem{ .int = 2 });
    try list2.append(DataItem{ .int = 3 });
    const di2 = try decode_(&.{ 0x83, 0x01, 0x02, 0x03 }, &index, allocator, false);
    defer di2.deinit();
    try std.testing.expectEqualSlices(DataItem, list2.items, di2.array.items);

    index = 0;
    var list3 = std.ArrayList(DataItem).init(allocator);
    defer list3.deinit();
    var list3_1 = std.ArrayList(DataItem).init(allocator);
    defer list3_1.deinit();
    var list3_2 = std.ArrayList(DataItem).init(allocator);
    defer list3_2.deinit();
    try list3_1.append(DataItem{ .int = 2 });
    try list3_1.append(DataItem{ .int = 3 });
    try list3_2.append(DataItem{ .int = 4 });
    try list3_2.append(DataItem{ .int = 5 });
    try list3.append(DataItem{ .int = 1 });
    try list3.append(DataItem{ .array = list3_1 });
    try list3.append(DataItem{ .array = list3_2 });
    const expected3 = DataItem{ .array = list3 };
    const di3 = try decode_(&.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05 }, &index, allocator, false);
    defer di3.deinit();
    try std.testing.expect(di3.equal(&expected3));

    index = 0;
    var list4 = std.ArrayList(DataItem).init(allocator);
    defer list4.deinit();
    var i: i128 = 1;
    while (i <= 25) : (i += 1) {
        try list4.append(DataItem{ .int = i });
    }
    const di4 = try decode_(&.{ 0x98, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19 }, &index, allocator, false);
    defer di4.deinit();
    try std.testing.expectEqualSlices(DataItem, list4.items, di4.array.items);
}

test "MT5: decode empty cbor map" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.map.deinit();
    const di = try decode_(&.{0xa0}, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));

    try expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try std.testing.expect(!di.equal(&expected));
}

test "MT5: decode cbor map {1:2,3:4}" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();
    try expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try expected.map.append(Pair{ .key = DataItem{ .int = 3 }, .value = DataItem{ .int = 4 } });

    var not_expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer not_expected.map.deinit();
    try not_expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try not_expected.map.append(Pair{ .key = DataItem{ .int = 5 }, .value = DataItem{ .int = 4 } });

    const di = try decode_(&.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
    try std.testing.expect(!di.equal(&not_expected));
}

test "MT5: decode cbor map {\"a\":1,\"b\":[2,3]}" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    // {"a":1,"b":[2,3]}
    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();
    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    try expected.map.append(Pair{ .key = s1, .value = DataItem{ .int = 1 } });
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("b");
    var arr = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try arr.array.append(DataItem{ .int = 2 });
    try arr.array.append(DataItem{ .int = 3 });
    try expected.map.append(Pair{ .key = s2, .value = arr });

    const di = try decode_(&.{ 0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03 }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT5: decode cbor map within array" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    // ["a",{"b":"c"}]
    var expected = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    defer expected.deinit();

    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    try expected.array.append(s1);

    var map = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("b");
    var s3 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s3.text.appendSlice("c");
    try map.map.append(Pair{ .key = s2, .value = s3 });
    try expected.array.append(map);

    const di = try decode_(&.{ 0x82, 0x61, 0x61, 0xa1, 0x61, 0x62, 0x61, 0x63 }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT5: decode cbor map of text pairs" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    // ["a",{"b":"c"}]
    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();

    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("A");
    var s3 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s3.text.appendSlice("b");
    var s4 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s4.text.appendSlice("B");
    var s5 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s5.text.appendSlice("c");
    var s6 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s6.text.appendSlice("C");
    var s7 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s7.text.appendSlice("d");
    var s8 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s8.text.appendSlice("D");
    var s9 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s9.text.appendSlice("e");
    var s10 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s10.text.appendSlice("E");

    try expected.map.append(Pair{ .key = s1, .value = s2 });
    try expected.map.append(Pair{ .key = s3, .value = s4 });
    try expected.map.append(Pair{ .key = s5, .value = s6 });
    try expected.map.append(Pair{ .key = s7, .value = s8 });
    try expected.map.append(Pair{ .key = s9, .value = s10 });

    const di = try decode_(&.{ 0xa5, 0x61, 0x61, 0x61, 0x41, 0x61, 0x62, 0x61, 0x42, 0x61, 0x63, 0x61, 0x43, 0x61, 0x64, 0x61, 0x44, 0x61, 0x65, 0x61, 0x45 }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT6: decode cbor tagged data item 1(1363896240)" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var item = try allocator.create(DataItem);
    item.* = DataItem{ .int = 1363896240 };
    var expected = DataItem{ .tag = Tag{ .number = 1, .content = item, .allocator = allocator } };
    defer expected.deinit();

    const di = try decode_(&.{ 0xc1, 0x1a, 0x51, 0x4b, 0x67, 0xb0 }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT6: decode cbor tagged data item 32(\"http://www.example.com\")" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var item = try allocator.create(DataItem);
    var text = std.ArrayList(u8).init(allocator);
    try text.appendSlice("http://www.example.com");
    item.* = DataItem{ .text = text };
    var expected = DataItem{ .tag = Tag{ .number = 32, .content = item, .allocator = allocator } };
    defer expected.deinit();

    const di = try decode_(&.{ 0xd8, 0x20, 0x76, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d }, &index, allocator, false);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 0.0" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .float = Float{ .float16 = 0.0 } };
    var ne1 = DataItem{ .float = Float{ .float16 = 0.1 } };
    var ne2 = DataItem{ .float = Float{ .float16 = -0.1 } };
    var ne3 = DataItem{ .float = Float{ .float32 = 0.0 } };
    var ne4 = DataItem{ .float = Float{ .float64 = 0.0 } };
    var di = try decode_(&.{ 0xf9, 0x00, 0x00 }, &index, allocator, false);

    try std.testing.expect(di.equal(&expected));
    try std.testing.expect(!di.equal(&ne1));
    try std.testing.expect(!di.equal(&ne2));
    try std.testing.expect(!di.equal(&ne3));
    try std.testing.expect(!di.equal(&ne4));
}

test "MT7: decode f16 -0.0" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .float = Float{ .float16 = -0.0 } };
    var di = try decode_(&.{ 0xf9, 0x80, 0x00 }, &index, allocator, false);

    try std.testing.expectEqual(expected.float.float16, di.float.float16);
    //try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 1.0" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .float = Float{ .float16 = 1.0 } };
    var di = try decode_(&.{ 0xf9, 0x3c, 0x00 }, &index, allocator, false);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 1.5" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .float = Float{ .float16 = 1.5 } };
    var di = try decode_(&.{ 0xf9, 0x3e, 0x00 }, &index, allocator, false);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 " {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var expected = DataItem{ .float = Float{ .float16 = 5.960464477539063e-8 } };
    var di = try decode_(&.{ 0xf9, 0x00, 0x01 }, &index, allocator, false);

    try std.testing.expect(di.equal(&expected));
}
