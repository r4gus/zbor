const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const core = @import("core.zig");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");

const CborError = core.CborError;
const Pair = core.Pair;
const Tag = core.Tag;
const FloatTag = core.FloatTag;
const Float = core.Float;
const SimpleValue = core.SimpleValue;
const DataItemTag = core.DataItemTag;
const DataItem = core.DataItem;
const pair_asc = core.pair_asc;

const encode = encoder.encode;
const decode = decoder.decode;

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("Hello World\n");
}

test {
    const tests = @import("tests.zig");

    _ = core;
    _ = encoder;
    _ = decoder;
    _ = tests;
}
