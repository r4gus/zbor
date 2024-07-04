const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const cbor = @import("cbor.zig");
const parser = @import("parse.zig");
pub const cose = @import("cose.zig");
pub const build = @import("build.zig");

pub const Type = cbor.Type;
pub const DataItem = cbor.DataItem;
pub const Tag = cbor.Tag;
pub const Pair = cbor.Pair;
pub const MapIterator = cbor.MapIterator;
pub const ArrayIterator = cbor.ArrayIterator;

pub const ParseError = parser.ParseError;
pub const StringifyError = parser.StringifyError;
pub const Options = parser.Options;
pub const SerializationType = parser.SerializationType;
pub const SkipBehavior = parser.SkipBehavior;
pub const FieldSettings = parser.FieldSettings;
pub const parse = parser.parse;
pub const stringify = parser.stringify;

pub const Builder = build.Builder;
pub const ContainerType = build.ContainerType;

pub const ArrayBackedSlice = parser.ArrayBackedSlice;
pub const ArrayBackedSliceType = parser.ArrayBackedSliceType;

// TODO: can we somehow read this from build.zig.zon???
pub const VERSION: []const u8 = "0.15.0";

test "main tests" {
    _ = cbor;
    _ = parser;
    _ = cose;
    _ = build;
}
