const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("core.zig");
const CborError = core.CborError;
const Pair = core.Pair;
const Tag = core.Tag;
const FloatTag = core.FloatTag;
const Float = core.Float;
const SimpleValue = core.SimpleValue;
const DataItemTag = core.DataItemTag;
const DataItem = core.DataItem;

/// Decode the given CBOR byte string into a (nested) DataItem.
///
/// The caller is responsible for deallocation, e.g. `defer data_item.deinit()`.
pub fn decode(allocator: Allocator, data: []const u8) CborError!DataItem {
    var index: usize = 0;
    return decode_(data, &index, allocator, false);
}

// calling function is responsible for deallocating memory.
fn decode_(data: []const u8, index: *usize, allocator: Allocator, breakable: bool) CborError!DataItem {
    _ = breakable;
    _ = allocator;
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
        // Byte string (mt 2)
        // The number of bytes in the string is equal to the argument (val).
        2 => {
            if (index.* + @as(usize, val) > data.len) return CborError.Malformed; // Not enough bytes available.

            var item = DataItem{ .bytes = try allocator.alloc(u8, @as(usize, val)) };
            std.mem.copy(u8, item.bytes, data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);
            return item;
        },
        // Text string (mt 3)
        3 => {
            if (index.* + @as(usize, val) > data.len) return CborError.Malformed; // Not enough bytes available.

            var item = DataItem{ .text = try allocator.alloc(u8, @as(usize, val)) };
            std.mem.copy(u8, item.text, data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);
            return item;
        },
        // MT4: DataItem array, e.g. [], [1, 2, 3], [1, [2, 3], [4, 5]].
        4 => {
            var item = DataItem{ .array = try allocator.alloc(DataItem, @as(usize, val)) };
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                item.array[i] = try decode_(data, index, allocator, false);
            }
            return item;
        },
        // MT5: Map of pairs of DataItem, e.g. {1:2, 3:4}.
        5 => {
            var item = DataItem{ .map = try allocator.alloc(Pair, @as(usize, val)) };
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                const k = try decode_(data, index, allocator, false);
                const v = try decode_(data, index, allocator, false);
                item.map[i] = Pair{ .key = k, .value = v };
            }
            return item;
        },
        // MT6: Tagged data item, e.g. 1("a").
        6 => {
            var item = try allocator.create(DataItem);
            // The enclosed data item (tag content) is the single encoded data
            // item that follows the head.
            item.* = try decode_(data, index, allocator, false);
            return DataItem{ .tag = Tag{ .number = val, .content = item } };
        },
        7 => {
            switch (ai) {
                20 => return DataItem{ .simple = SimpleValue.False },
                21 => return DataItem{ .simple = SimpleValue.True },
                22 => return DataItem{ .simple = SimpleValue.Null },
                23 => return DataItem{ .simple = SimpleValue.Undefined },
                24 => {
                    if (val < 32) {
                        return CborError.Malformed;
                    } else {
                        return CborError.Unsupported;
                    }
                },
                // The following narrowing conversions are fine because the
                // number of parsed bytes always matches the size of the float.
                25 => return DataItem{ .float = Float{ .float16 = @bitCast(f16, @intCast(u16, val)) } },
                26 => return DataItem{ .float = Float{ .float32 = @bitCast(f32, @intCast(u32, val)) } },
                27 => return DataItem{ .float = Float{ .float64 = @bitCast(f64, val) } },
                // Break stop code unsupported for the moment.
                31 => return CborError.Unsupported,
                else => return CborError.Malformed,
            }
        },
        else => {
            unreachable;
        },
    }

    return CborError.Malformed;
}
