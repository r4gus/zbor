const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const clap = @import("clap");

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
    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Handle command line arguments ++++++++++++++++++++++++++++++++++++++++++
    // see: https://github.com/Hejsil/zig-clap by Hejsil
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-o, --output <OUTPUT> An optional output type parameter, {default, json}.
        \\--hex <STR>           Specify the input as hex string.
        \\<FILE>...
        \\
    );

    const Output = enum { default, json };
    const parsers = comptime .{
        .OUTPUT = clap.parsers.enumeration(Output),
        .STR = clap.parsers.string,
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return;
    };
    defer res.deinit();

    // Show help message and exit.
    if (res.args.help) {
        return clap.help(stderr, clap.Help, &params, .{});
    }

    // Decode the given CBOR data +++++++++++++++++++++++++++++++++++++++++++++

    // How the CBOR byte string should be displayed.
    const output = if (res.args.output) |o| o else Output.default;

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    if (res.args.hex) |h| {
        if (h.len % 2 != 0) {
            try stderr.writeAll("hex string must contain an even number of digits\n");
            return;
        }

        // Two digits make one byte.
        try buffer.resize(h.len / 2);

        _ = std.fmt.hexToBytes(buffer.items, h) catch {
            try stderr.print("hex string malformed\n", .{});
            return;
        };
    } else if (res.positionals.len > 0) {
        const file = std.fs.cwd().openFile(res.positionals[0], .{ .mode = .read_only }) catch {
            try stderr.print("unable to open file `{s}`\n", .{res.positionals[0]});
            return;
        };
        defer file.close();

        const stat = try file.stat();
        try buffer.resize(stat.size);
        _ = try file.readAll(buffer.items);
    } else {
        try stderr.writeAll("no CBOR file path or hex string specified\n");
        return;
    }

    var di = decode(allocator, buffer.items) catch |err| {
        switch (err) {
            CborError.ReservedAdditionalInformation => {
                try stderr.writeAll("error: CBOR data uses additional information that are currently not supported\n");
            },
            CborError.ReservedSimpleValue => {
                try stderr.writeAll("error: simple values 24..31 reserved for future use\n");
            },
            CborError.IndefiniteLength => {
                try stderr.writeAll("error: indefinite-length items not supported\n");
            },
            CborError.Malformed => {
                try stderr.writeAll("error: malformed data\n");
            },
            CborError.Unassigned => {
                try stderr.writeAll("error: simple values 0..19 and 32..255 currently unassigned\n");
            },
            CborError.OutOfMemory => {
                try stderr.writeAll("error: out of memory\n");
            },
        }
        return;
    };
    defer di.deinit(allocator);

    switch (output) {
        .default => {
            try stderr.writeAll("output format not yet supported; please use `-o json`\n");
            return;
        },
        .json => {
            var json = std.ArrayList(u8).init(allocator);
            defer json.deinit();
            std.json.stringify(di, .{}, json.writer()) catch {
                try stderr.writeAll("unable to serialize the given CBOR byte string to JSON\n");
                return;
            };
            try stdout.print("{s}\n", .{json.items});
        },
    }

    // Get command line arguments
    // const args = try std.process.argsAlloc(allocator);
    // defer std.process.argsFree(allocator, args);
}

fn printDataItem(item: *const DataItem, level: usize, out_stream: anytype) void {
    _ = item;
    _ = level;
    _ = out_stream;
}
