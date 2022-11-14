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
    return decode_(data, &index, allocator);
}

// calling function is responsible for deallocating memory.
fn decode_(data: []const u8, index: *usize, allocator: Allocator) CborError!DataItem {
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
            // Values are reserved for future additions to the CBOR format.
            // In the present version of CBOR, the encoded item is not
            // well-formed.
            return CborError.ReservedAdditionalInformation;
        },
        else => { // 31 (all other values are impossible)
            switch (mt) {
                // The encoded item is not well formed.
                0, 1, 6 => return CborError.Malformed,
                // The item's length is indefinite (currently
                // not supported).
                2, 3, 4, 5 => return CborError.IndefiniteLength,
                // The byte terminates an indefinite-length item
                // (currently not supported).
                7 => return CborError.IndefiniteLength,
                else => unreachable,
            }
        },
    }

    // Process content.
    switch (mt) {
        // MT0: Unsigned int, e.g. 1, 10, 23, 25.
        0 => {
            return DataItem{ .int = @as(i65, val) };
        },
        // MT1: Signed int, e.g. -1, -10, -12345.
        1 => {
            // The value of the item is -1 minus the argument.
            return DataItem{ .int = -1 - @as(i65, val) };
        },
        // Byte string (mt 2)
        // The number of bytes in the string is equal to the argument (val).
        2 => {
            if (index.* + @as(usize, val) > data.len) return CborError.Malformed; // Not enough bytes available.

            var m = try allocator.alloc(u8, @as(usize, val));
            std.mem.copy(u8, m, data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);

            return DataItem{ .bytes = m };
        },
        // Text string (mt 3)
        3 => {
            if (index.* + @as(usize, val) > data.len) return CborError.Malformed; // Not enough bytes available.

            var m = try allocator.alloc(u8, @as(usize, val));
            std.mem.copy(u8, m, data[index.* .. index.* + @as(usize, val)]);
            index.* += @as(usize, val);

            return DataItem{ .text = m };
        },
        // MT4: DataItem array, e.g. [], [1, 2, 3], [1, [2, 3], [4, 5]].
        4 => {
            var m = try allocator.alloc(DataItem, @as(usize, val));
            errdefer allocator.free(m);
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                m[i] = try decode_(data, index, allocator);
            }

            return DataItem{ .array = m };
        },
        // MT5: Map of pairs of DataItem, e.g. {1:2, 3:4}.
        5 => {
            var m = try allocator.alloc(Pair, @as(usize, val));
            errdefer allocator.free(m);
            var i: usize = 0;
            while (i < val) : (i += 1) {
                // The index will be incremented by the recursive call to decode_.
                const k = try decode_(data, index, allocator);
                errdefer k.deinit(allocator);
                const v = try decode_(data, index, allocator);
                m[i] = Pair{ .key = k, .value = v };
            }

            return DataItem{ .map = m };
        },
        // MT6: Tagged data item, e.g. 1("a").
        6 => {
            var item = try allocator.create(DataItem);
            errdefer allocator.destroy(item);
            // The enclosed data item (tag content) is the single encoded data
            // item that follows the head.
            item.* = try decode_(data, index, allocator);
            return DataItem{ .tag = Tag{ .number = val, .content = item } };
        },
        7 => {
            switch (ai) {
                0...19 => return CborError.Unassigned,
                20 => return DataItem{ .simple = SimpleValue.False },
                21 => return DataItem{ .simple = SimpleValue.True },
                22 => return DataItem{ .simple = SimpleValue.Null },
                23 => return DataItem{ .simple = SimpleValue.Undefined },
                24 => {
                    if (val < 32) {
                        return CborError.ReservedSimpleValue;
                    } else {
                        return CborError.Unassigned;
                    }
                },
                // The following narrowing conversions are fine because the
                // number of parsed bytes always matches the size of the float.
                25 => return DataItem{ .float = Float{ .float16 = @bitCast(f16, @intCast(u16, val)) } },
                26 => return DataItem{ .float = Float{ .float32 = @bitCast(f32, @intCast(u32, val)) } },
                27 => return DataItem{ .float = Float{ .float64 = @bitCast(f64, val) } },
                // Reserved, not well-formed
                28, 29, 30 => return CborError.Malformed,
                // Break stop code unsupported for the moment.
                31 => return CborError.IndefiniteLength,
                else => unreachable,
            }
        },
        else => {
            unreachable;
        },
    }

    return CborError.Malformed;
}
