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

const ContentTag = enum { int, bytes };

const Content = union(ContentTag) {
    /// Major type 0 and 1: An integer in the range -2^64..2^64-1
    int: i128,
    /// Major type 2: A byte string.
    bytes: std.ArrayList(u8),
};

const DataItem = struct {
    allocator: ?Allocator = null,
    content: Content,

    fn init(allocator: Allocator, content: Content) error{OutOfMemory}!*@This() {
        var item = try allocator.create(DataItem);
        item.*.allocator = allocator;
        item.*.content = content;

        return item;
    }

    fn deinit(self: *@This()) void {
        switch (self.content) {
            .int => |_| {},
            .bytes => |list| list.deinit(),
        }

        if (self.allocator != null) {
            self.allocator.?.destroy(self);
        }
    }

    fn equal(self: *const @This(), other: *const @This()) bool {
        if (@as(ContentTag, self.content) != @as(ContentTag, other.content)) {
            return false;
        }

        switch (self.content) {
            .int => |value| return value == other.content.int,
            .bytes => |list| return std.mem.eql(u8, list.items, other.content.bytes.items),
        }
    }
};

// calling function is responsible for deallocating memory.
fn decode_(data: []const u8, index: *usize, allocator: Allocator, breakable: bool) CborError!*DataItem {
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
    var item: ?*DataItem = null;
    switch (mt) {
        // MT0: Unsigned int.
        0 => {
            item = try DataItem.init(allocator, Content{ .int = @as(i128, val) });
        },
        // MT1: Signed int.
        1 => {
            // The value of the item is -1 minus the argument.
            item = try DataItem.init(allocator, Content{ .int = -1 - @as(i128, val) });
        },
        // MT2: Byte String.
        // The number of bytes in the string is equal to the argument (val).
        2 => {
            item = try DataItem.init(allocator, Content{ .bytes = std.ArrayList(u8).init(allocator) });
            try item.?.content.bytes.appendSlice(data[index.* .. index.* + @as(usize, val)]);
        },
        else => {
            //unreachable;
        },
    }

    return item orelse CborError.Default;
}

const TestError = CborError || error{ TestExpectedEqual, TestUnexpectedResult };

fn test_data_item(data: []const u8, expected: DataItem) TestError!void {
    const allocator = std.testing.allocator;
    var index: usize = 0;
    const dip = try decode_(data, &index, allocator, false);
    defer dip.deinit();
    try std.testing.expectEqual(expected.content, dip.*.content);
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
    const di1 = DataItem{ .content = Content{ .int = 10 } };
    const di2 = DataItem{ .content = Content{ .int = 23 } };
    const di3 = DataItem{ .content = Content{ .int = 23 } };
    const di4 = DataItem{ .content = Content{ .int = -9988776655 } };

    try std.testing.expect(!di1.equal(&di2));
    try std.testing.expect(di2.equal(&di3));
    try std.testing.expect(!di1.equal(&di4));
    try std.testing.expect(!di2.equal(&di4));
    try std.testing.expect(!di3.equal(&di4));

    var allocator = std.testing.allocator;

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    var di5 = DataItem{ .content = Content{ .bytes = list } };
    defer di5.deinit();

    try std.testing.expect(!di5.equal(&di1));
    try std.testing.expect(!di1.equal(&di5));
    try std.testing.expect(di5.equal(&di5));

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    var di6 = DataItem{ .content = Content{ .bytes = list2 } };
    defer di6.deinit();

    try std.testing.expect(di5.equal(&di6));
    try di6.content.bytes.append(123);
    try std.testing.expect(!di5.equal(&di6));
}

test "MT0: decode cbor unsigned integer value" {
    try test_data_item(&.{0x00}, DataItem{ .content = Content{ .int = 0 } });
    try test_data_item(&.{0x01}, DataItem{ .content = Content{ .int = 1 } });
    try test_data_item(&.{0x0a}, DataItem{ .content = Content{ .int = 10 } });
    try test_data_item(&.{0x17}, DataItem{ .content = Content{ .int = 23 } });
    try test_data_item(&.{ 0x18, 0x18 }, DataItem{ .content = Content{ .int = 24 } });
    try test_data_item(&.{ 0x18, 0x19 }, DataItem{ .content = Content{ .int = 25 } });
    try test_data_item(&.{ 0x18, 0x64 }, DataItem{ .content = Content{ .int = 100 } });
    try test_data_item(&.{ 0x18, 0x7b }, DataItem{ .content = Content{ .int = 123 } });
    try test_data_item(&.{ 0x19, 0x03, 0xe8 }, DataItem{ .content = Content{ .int = 1000 } });
    try test_data_item(&.{ 0x19, 0x04, 0xd2 }, DataItem{ .content = Content{ .int = 1234 } });
    try test_data_item(&.{ 0x1a, 0x00, 0x01, 0xe2, 0x40 }, DataItem{ .content = Content{ .int = 123456 } });
    try test_data_item(&.{ 0x1a, 0x00, 0x0f, 0x42, 0x40 }, DataItem{ .content = Content{ .int = 1000000 } });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0x02, 0xdf, 0xdc, 0x1c, 0x34 }, DataItem{ .content = Content{ .int = 12345678900 } });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0xe8, 0xd4, 0xa5, 0x10, 0x00 }, DataItem{ .content = Content{ .int = 1000000000000 } });
    try test_data_item(&.{ 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .content = Content{ .int = 18446744073709551615 } });
}

test "MT1: decode cbor signed integer value" {
    try test_data_item(&.{0x20}, DataItem{ .content = Content{ .int = -1 } });
    try test_data_item(&.{0x22}, DataItem{ .content = Content{ .int = -3 } });
    try test_data_item(&.{ 0x38, 0x63 }, DataItem{ .content = Content{ .int = -100 } });
    try test_data_item(&.{ 0x39, 0x01, 0xf3 }, DataItem{ .content = Content{ .int = -500 } });
    try test_data_item(&.{ 0x39, 0x03, 0xe7 }, DataItem{ .content = Content{ .int = -1000 } });
    try test_data_item(&.{ 0x3a, 0x00, 0x0f, 0x3d, 0xdc }, DataItem{ .content = Content{ .int = -998877 } });
    try test_data_item(&.{ 0x3b, 0x00, 0x00, 0x00, 0x02, 0x53, 0x60, 0xa2, 0xce }, DataItem{ .content = Content{ .int = -9988776655 } });
    try test_data_item(&.{ 0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .content = Content{ .int = -18446744073709551616 } });
}

test "MT2: decode cbor byte string" {
    const allocator = std.testing.allocator;

    try test_data_item(&.{0b01000000}, DataItem{ .content = Content{ .bytes = std.ArrayList(u8).init(allocator) } });

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    try test_data_item_eql(&.{ 0b01000001, 0x0a }, &DataItem{ .content = Content{ .bytes = list } });
}
