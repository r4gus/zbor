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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try stderr.writeAll("error: no cbor byte string specified\n");
        return;
    }

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try buffer.resize(args[1].len / 2);
    _ = try std.fmt.hexToBytes(buffer.items, args[1]);

    var di = try decode(allocator, buffer.items);
    defer di.deinit(allocator);
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();

    try std.json.stringify(di, .{}, json.writer());
    try stdout.print("{s}\n", .{json.items});
}

test {
    const tests = @import("tests.zig");

    _ = core;
    _ = encoder;
    _ = decoder;
    _ = tests;
}
