const cbor = @import("v0/cbor.zig");
const parser = @import("v0/parse.zig");
pub const cose = @import("v0/cose.zig");
pub const builder = @import("v0/builder.zig");
pub const advance = cbor.burn;

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

pub const Builder = builder.Builder;
pub const ContainerType = builder.ContainerType;

pub const ArrayBackedSlice = parser.ArrayBackedSlice;
pub const ArrayBackedSliceType = parser.ArrayBackedSliceType;

test "main tests" {
    _ = cbor;
    _ = parser;
    _ = cose;
    _ = builder;
}
