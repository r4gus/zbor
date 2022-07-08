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

const DataItemTag = enum { int, bytes, text, array };

const DataItem = union(DataItemTag) {
    /// Major type 0 and 1: An integer in the range -2^64..2^64-1
    int: i128,
    /// Major type 2: A byte string.
    bytes: std.ArrayList(u8),
    /// Major type 3: A text string encoded as utf-8.
    text: std.ArrayList(u8),
    /// Major type 4: An array of DataItem's.
    array: std.ArrayList(DataItem),

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
        }
    }

    fn equal(self: @This(), other: @This()) bool {
        // self and other hold different types, i.e. can't be equal.
        if (@as(DataItemTag, self) != @as(DataItemTag, other)) {
            return false;
        }

        switch (self) {
            .int => |value| return value == other.int,
            .bytes => |list| return std.mem.eql(u8, list.items, other.bytes.items),
            .text => |list| return std.mem.eql(u8, list.items, other.bytes.items),
            .array => |arr| {
                if (arr.items.len != other.array.items.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < arr.items.len) : (i += 1) {
                    if (!arr.items[i].equal(other.array.items[i])) {
                        return false;
                    }
                }

                return true;
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
        // MT0: Unsigned int.
        0 => {
            return DataItem{ .int = @as(i128, val) };
        },
        // MT1: Signed int.
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
        // MT3: UTF-8 text string.
        3 => {
            var item = DataItem{ .text = std.ArrayList(u8).init(allocator) };
            try item.text.appendSlice(data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);
            return item;
        },
        // MT4: DataItem array.
        4 => {
            var item = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                try item.array.append(try decode_(data, index, allocator, false));
            }
            return item;
        },
        else => {
            //unreachable;
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
    try std.testing.expect(expected.*.equal(dip));
}

test "DataItem.equal test" {
    const di1 = DataItem{ .int = 10 };
    const di2 = DataItem{ .int = 23 };
    const di3 = DataItem{ .int = 23 };
    const di4 = DataItem{ .int = -9988776655 };

    try std.testing.expect(!di1.equal(di2));
    try std.testing.expect(di2.equal(di3));
    try std.testing.expect(!di1.equal(di4));
    try std.testing.expect(!di2.equal(di4));
    try std.testing.expect(!di3.equal(di4));

    var allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    var di5 = DataItem{ .bytes = list };
    defer di5.deinit();

    try std.testing.expect(!di5.equal(di1));
    try std.testing.expect(!di1.equal(di5));
    try std.testing.expect(di5.equal(di5));

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    var di6 = DataItem{ .bytes = list2 };
    defer di6.deinit();

    try std.testing.expect(di5.equal(di6));
    try di6.bytes.append(123);
    try std.testing.expect(!di5.equal(di6));
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
}
