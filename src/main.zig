const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const core = @import("core.zig");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
const parser = @import("parse.zig");

pub const CborError = core.CborError;
pub const Pair = core.Pair;
pub const Tag = core.Tag;
pub const FloatTag = core.FloatTag;
pub const Float = core.Float;
pub const SimpleValue = core.SimpleValue;
pub const DataItemTag = core.DataItemTag;
pub const DataItem = core.DataItem;
pub const Options = core.Options;

pub const encode = encoder.encode;
pub const encodeAlloc = encoder.encodeAlloc;
pub const decode = decoder.decode;
pub const parse = parser.parse;

test {
    const tests = @import("tests.zig");

    _ = core;
    _ = encoder;
    _ = decoder;
    _ = tests;
    _ = parser;
}
