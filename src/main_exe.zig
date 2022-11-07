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
            try printDataItem(&di, 0, stdout);
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

fn printDataItem(item: *const DataItem, level: usize, out_stream: anytype) @TypeOf(out_stream).Error!void {
    try out_stream.writeByteNTimes(' ', level * 2);

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
        .float, .simple => head = 0xe0,
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
                    try out_stream.print("{X} {X} # float2({e})\n", .{ head | 25, @bitCast(u16, value), value });
                },
                .float32 => |value| {
                    try out_stream.print("{X} {X} # float4({e})\n", .{ head | 26, @bitCast(u32, value), value });
                },
                .float64 => |value| {
                    try out_stream.print("{X} {X} # float8({e})\n", .{ head | 27, @bitCast(u64, value), value });
                },
            }
            return;
        },
        .simple => |value| {
            v = @enumToInt(value);
        },
    }

    switch (v) {
        0x00...0x17 => head |= @intCast(u8, v),
        0x18...0xff => head |= 24,
        0x0100...0xffff => head |= 25,
        0x00010000...0xffffffff => head |= 26,
        0x0000000100000000...0xffffffffffffffff => head |= 27,
    }

    switch (item.*) {
        .bytes, .text, .array, .map, .tag, .simple => {
            switch (v) {
                0x00...0x17 => {
                    try out_stream.print("{X} # {s}({d})\n", .{ head, @tagName(item.*), v });
                },
                else => {
                    try out_stream.print("{X} {X} # {s}({d})\n", .{ head, v, @tagName(item.*), v });
                },
            }
        },
        else => {},
    }

    switch (item.*) {
        .int => |value| {
            switch (v) {
                0x00...0x17 => {
                    try out_stream.print("{X} # integer({d})\n", .{ head, value });
                },
                else => {
                    try out_stream.print("{X} {X} # integer({d})\n", .{ head, v, value });
                },
            }
        },
        // The number of bytes in the byte string is equal to the arugment.
        .bytes => |value| {
            try out_stream.print("\n{s}\n", .{std.fmt.fmtSliceHexUpper(value)});
        },
        // The number of bytes in the text string is equal to the arugment.
        .text => |value| {
            try out_stream.writeByteNTimes(' ', level * 2 + 2);
            try out_stream.print("{s} # \"{s}\"\n", .{ std.fmt.fmtSliceHexUpper(value), value });
        },
        // The argument is the number of data items in the array.
        .array => |value| {
            for (value) |*itm| {
                try printDataItem(itm, level + 1, out_stream);
            }
        },
        // The argument is the number of (k,v) pairs.
        .map => |value| {
            //std.sort.sort(Pair, value, {}, pair_asc);
            var i: usize = 0;
            while (i < value.len) : (i += 1) {
                // each pair consisting of a key...
                try printDataItem(&value[i].key, level + 1, out_stream);
                // ...that is immediately followed by a value.
                try printDataItem(&value[i].value, level + 1, out_stream);
            }
        },
        // The argument is the tag.
        .tag => |value| {
            try printDataItem(value.content, level + 1, out_stream);
        },
        .simple => {},
        else => unreachable, // float already handled
    }
}
