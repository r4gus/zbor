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
const pair_asc = core.pair_asc;

/// Encode a (nested) DataItem as CBOR byte string.
pub fn encode(allocator: Allocator, item: *const DataItem) CborError!std.ArrayList(u8) {
    var cbor = std.ArrayList(u8).init(allocator);
    try encode_(&cbor, item);
    return cbor;
}

fn encode_2(cbor: *std.ArrayList(u8), head: u8, v: u64) CborError!void {
    try cbor.append(head | 25);
    try cbor.append(@intCast(u8, (v >> 8) & 0xff));
    try cbor.append(@intCast(u8, v & 0xff));
}

fn encode_4(cbor: *std.ArrayList(u8), head: u8, v: u64) CborError!void {
    try cbor.append(head | 26);
    try cbor.append(@intCast(u8, (v >> 24) & 0xff));
    try cbor.append(@intCast(u8, (v >> 16) & 0xff));
    try cbor.append(@intCast(u8, (v >> 8) & 0xff));
    try cbor.append(@intCast(u8, v & 0xff));
}

fn encode_8(cbor: *std.ArrayList(u8), head: u8, v: u64) CborError!void {
    try cbor.append(head | 27);
    try cbor.append(@intCast(u8, (v >> 56) & 0xff));
    try cbor.append(@intCast(u8, (v >> 48) & 0xff));
    try cbor.append(@intCast(u8, (v >> 40) & 0xff));
    try cbor.append(@intCast(u8, (v >> 32) & 0xff));
    try cbor.append(@intCast(u8, (v >> 24) & 0xff));
    try cbor.append(@intCast(u8, (v >> 16) & 0xff));
    try cbor.append(@intCast(u8, (v >> 8) & 0xff));
    try cbor.append(@intCast(u8, v & 0xff));
}

fn encode_(cbor: *std.ArrayList(u8), item: *const DataItem) CborError!void {
    // The first byte of a data item encodes its type.
    var head: u8 = 0;
    switch (item.*) {
        .int => |value| {
            if (value < 0) head = 0x20;
        },
        .bytes => |_| head = 0x40,
        .text => |_| head = 0x60,
        .array => |_| head = 0x80,
        .map => |_| head = 0xa0,
        .tag => |_| head = 0xc0,
        .float => |_| head = 0xe0,
        else => unreachable,
    }

    // The arguments value represents either a integer, float or size.
    var v: u64 = 0;
    switch (item.*) {
        .int => |value| {
            if (value < 0)
                v = @intCast(u64, (-value) - 1)
            else
                v = @intCast(u64, value);
        },
        // The number of bytes in the byte string is equal to the arugment.
        .bytes => |value| v = @intCast(u64, value.len),
        // The number of bytes in the text string is equal to the arugment.
        .text => |value| v = @intCast(u64, value.len),
        // The argument is the number of data items in the array.
        .array => |value| v = @intCast(u64, value.len),
        // The argument is the number of (k,v) pairs.
        .map => |value| v = @intCast(u64, value.len),
        // The argument is the tag.
        .tag => |value| v = value.number,
        .float => |f| {
            // The representation of any floating-point values are not changed.
            switch (f) {
                .float16 => |value| {
                    try encode_2(cbor, head, @intCast(u64, @bitCast(u16, value)));
                    return;
                },
                .float32 => |value| {
                    try encode_4(cbor, head, @intCast(u64, @bitCast(u32, value)));
                    return;
                },
                .float64 => |value| {
                    try encode_8(cbor, head, @bitCast(u64, value));
                    return;
                },
            }
        },
        else => unreachable,
    }

    switch (v) {
        0x00...0x17 => {
            try cbor.append(head | @intCast(u8, v));
        },
        0x18...0xff => {
            try cbor.append(head | 24);
            try cbor.append(@intCast(u8, v));
        },
        0x0100...0xffff => try encode_2(cbor, head, v),
        0x00010000...0xffffffff => try encode_4(cbor, head, v),
        0x0000000100000000...0xffffffffffffffff => try encode_8(cbor, head, v),
    }

    switch (item.*) {
        .int, .float => {},
        .bytes => |value| try cbor.appendSlice(value),
        .text => |value| try cbor.appendSlice(value),
        .array => |arr| {
            // Encode every data item of the array.
            for (arr) |*itm| {
                try encode_(cbor, itm);
            }
        },
        .map => |m| {
            // Sort keys lowest to highest (CTAP2 canonical CBOR encoding form)
            std.sort.sort(Pair, m, {}, pair_asc);

            var i: usize = 0;
            while (i < m.len) : (i += 1) {
                // each pair consisting of a key...
                try encode_(cbor, &m[i].key);
                // ...that is immediately followed by a value.
                try encode_(cbor, &m[i].value);
            }
        },
        .tag => |t| {
            // Tag content is the single encoded data item that follows the head.
            try encode_(cbor, t.content);
        },
        else => unreachable,
    }
}
