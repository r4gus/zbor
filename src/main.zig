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

const Content = union(enum) {
    /// Major type 0 and 1: An integer in the range -2^64..2^64-1
    int: i128,
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
        // TODO: DataItem's can be nested so keep in mind to free everything!

        if (self.allocator != null) {
            self.allocator.?.destroy(self);
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
        // MT2: Byte String, MT3: Text string.
        2, 3 => {},
        else => {
            unreachable;
        },
    }

    return item orelse CborError.Default;
}

const TestError = CborError || error{TestExpectedEqual};

fn test_data_item(data: []const u8, expected: DataItem) TestError!void {
    const allocator = std.testing.allocator;
    var index: usize = 0;
    const dip = try decode_(data, &index, allocator, false);
    defer dip.deinit();
    try std.testing.expectEqual(expected.content, dip.*.content);
}

test "MT0: decode cbor unsigned integer value" {
    try test_data_item(&.{0x00}, DataItem{ .content = Content{ .int = 0 } });
    try test_data_item(&.{ 0x18, 0x7b }, DataItem{ .content = Content{ .int = 123 } });
    try test_data_item(&.{ 0x19, 0x04, 0xd2 }, DataItem{ .content = Content{ .int = 1234 } });
    try test_data_item(&.{ 0x1a, 0x00, 0x01, 0xe2, 0x40 }, DataItem{ .content = Content{ .int = 123456 } });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0x02, 0xdf, 0xdc, 0x1c, 0x34 }, DataItem{ .content = Content{ .int = 12345678900 } });
}

test "MT1: decode cbor signed integer value" {
    try test_data_item(&.{0x22}, DataItem{ .content = Content{ .int = -3 } });
    try test_data_item(&.{ 0x39, 0x01, 0xf3 }, DataItem{ .content = Content{ .int = -500 } });
    try test_data_item(&.{ 0x3a, 0x00, 0x0f, 0x3d, 0xdc }, DataItem{ .content = Content{ .int = -998877 } });
    try test_data_item(&.{ 0x3b, 0x00, 0x00, 0x00, 0x02, 0x53, 0x60, 0xa2, 0xce }, DataItem{ .content = Content{ .int = -9988776655 } });
}
