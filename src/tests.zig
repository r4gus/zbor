const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const core = @import("core.zig");
const CborError = core.CborError;
const Pair = core.Pair;
const Tag = core.Tag;
const FloatTag = core.FloatTag;
const Float = core.Float;
const SimpleValue = core.SimpleValue;
const DataItemTag = core.DataItemTag;
const DataItem = core.DataItem;

//const encode = @import("encoder.zig").encode;
const decode = @import("decoder.zig").decode;

const TestError = CborError || error{ TestExpectedEqual, TestUnexpectedResult };

fn test_data_item(data: []const u8, expected: DataItem) TestError!void {
    const allocator = std.testing.allocator;
    const dip = try decode(allocator, data);
    defer dip.deinit(allocator);
    try std.testing.expectEqual(expected, dip);
}

fn test_data_item_eql(data: []const u8, expected: *DataItem) TestError!void {
    const allocator = std.testing.allocator;
    const dip = try decode(allocator, data);
    defer dip.deinit(allocator);
    try std.testing.expect(expected.*.equal(&dip));
}

test "DataItem.equal test" {
    const di1 = DataItem{ .int = 10 };
    const di2 = DataItem{ .int = 23 };
    const di3 = DataItem{ .int = 23 };
    const di4 = DataItem{ .int = -9988776655 };

    try std.testing.expect(!di1.equal(&di2));
    try std.testing.expect(di2.equal(&di3));
    try std.testing.expect(!di1.equal(&di4));
    try std.testing.expect(!di2.equal(&di4));
    try std.testing.expect(!di3.equal(&di4));

    var allocator = std.testing.allocator;

    var di5 = try DataItem.bytes(allocator, &.{10});
    defer di5.deinit(allocator);

    try std.testing.expect(!di5.equal(&di1));
    try std.testing.expect(!di1.equal(&di5));
    try std.testing.expect(di5.equal(&di5));

    var di6 = try DataItem.bytes(allocator, &.{10});
    defer di6.deinit(allocator);

    try std.testing.expect(di5.equal(&di6));
}

test "MT0: decode cbor unsigned integer value" {
    try test_data_item(&.{0x00}, DataItem{ .int = 0 });
    try test_data_item(&.{0x01}, DataItem{ .int = 1 });
    try test_data_item(&.{0x0a}, DataItem{ .int = 10 });
    try test_data_item(&.{0x17}, DataItem{ .int = 23 });
    try test_data_item(&.{ 0x18, 0x18 }, DataItem{ .int = 24 });
    try test_data_item(&.{ 0x18, 0x19 }, DataItem{ .int = 25 });
    try test_data_item(&.{ 0x18, 0x64 }, DataItem{ .int = 100 });
    try test_data_item(&.{ 0x18, 0x7b }, DataItem{ .int = 123 });
    try test_data_item(&.{ 0x19, 0x03, 0xe8 }, DataItem{ .int = 1000 });
    try test_data_item(&.{ 0x19, 0x04, 0xd2 }, DataItem{ .int = 1234 });
    try test_data_item(&.{ 0x1a, 0x00, 0x01, 0xe2, 0x40 }, DataItem{ .int = 123456 });
    try test_data_item(&.{ 0x1a, 0x00, 0x0f, 0x42, 0x40 }, DataItem{ .int = 1000000 });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0x02, 0xdf, 0xdc, 0x1c, 0x34 }, DataItem{ .int = 12345678900 });
    try test_data_item(&.{ 0x1b, 0x00, 0x00, 0x00, 0xe8, 0xd4, 0xa5, 0x10, 0x00 }, DataItem{ .int = 1000000000000 });
    try test_data_item(&.{ 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .int = 18446744073709551615 });
}

test "MT1: decode cbor signed integer value" {
    try test_data_item(&.{0x20}, DataItem{ .int = -1 });
    try test_data_item(&.{0x22}, DataItem{ .int = -3 });
    try test_data_item(&.{ 0x38, 0x63 }, DataItem{ .int = -100 });
    try test_data_item(&.{ 0x39, 0x01, 0xf3 }, DataItem{ .int = -500 });
    try test_data_item(&.{ 0x39, 0x03, 0xe7 }, DataItem{ .int = -1000 });
    try test_data_item(&.{ 0x3a, 0x00, 0x0f, 0x3d, 0xdc }, DataItem{ .int = -998877 });
    try test_data_item(&.{ 0x3b, 0x00, 0x00, 0x00, 0x02, 0x53, 0x60, 0xa2, 0xce }, DataItem{ .int = -9988776655 });
    try test_data_item(&.{ 0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, DataItem{ .int = -18446744073709551616 });
}

test "MT2: decode cbor byte string" {
    const allocator = std.testing.allocator;

    try test_data_item(&.{0b01000000}, DataItem{ .bytes = &.{} });

    var di1 = try DataItem.bytes(allocator, &.{10});
    defer di1.deinit(allocator);
    try test_data_item_eql(&.{ 0b01000001, 0x0a }, &di1);

    var di2 = try DataItem.bytes(allocator, &.{ 10, 11, 12, 13, 14 });
    defer di2.deinit(allocator);
    try test_data_item_eql(&.{ 0b01000101, 0x0a, 0xb, 0xc, 0xd, 0xe }, &di2);

    try std.testing.expectError(CborError.Malformed, decode(allocator, &.{ 0b01000011, 0x0a }));
    try std.testing.expectError(CborError.Malformed, decode(allocator, &.{ 0b01000101, 0x0a, 0xb, 0xc }));
}

test "MT3: decode cbor text string" {
    const allocator = std.testing.allocator;

    try test_data_item(&.{0x60}, try DataItem.text(allocator, &.{}));

    const exp1 = try DataItem.text(allocator, "a");
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{ 0x61, 0x61 });
    defer di1.deinit(allocator);
    try std.testing.expectEqualSlices(u8, exp1.text, di1.text);
    try std.testing.expect(exp1.equal(&di1));

    const exp2 = try DataItem.text(allocator, "IETF");
    defer exp2.deinit(allocator);
    const di2 = try decode(allocator, &.{ 0x64, 0x49, 0x45, 0x54, 0x46 });
    defer di2.deinit(allocator);
    try std.testing.expectEqualSlices(u8, exp2.text, di2.text);
    try std.testing.expect(exp2.equal(&di2));

    const exp3 = try DataItem.text(allocator, "\"\\");
    defer exp3.deinit(allocator);
    const di3 = try decode(allocator, &.{ 0x62, 0x22, 0x5c });
    defer di3.deinit(allocator);
    try std.testing.expectEqualSlices(u8, exp3.text, di3.text);
    try std.testing.expect(exp3.equal(&di3));

    try std.testing.expect(!exp1.equal(&di2));
    try std.testing.expect(!exp1.equal(&di3));
    try std.testing.expect(!exp2.equal(&di3));

    // TODO: test unicode https://www.rfc-editor.org/rfc/rfc8949.html#name-examples-of-encoded-cbor-da
}

test "MT4: decode cbor array" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.array(allocator, &.{});
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{0x80});
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));

    const exp2 = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3) });
    defer exp2.deinit(allocator);
    const di2 = try decode(allocator, &.{ 0x83, 0x01, 0x02, 0x03 });
    defer di2.deinit(allocator);
    try std.testing.expect(exp2.equal(&di2));

    const exp3 = try DataItem.array(allocator, &.{ DataItem.int(1), try DataItem.array(allocator, &.{ DataItem.int(2), DataItem.int(3) }), try DataItem.array(allocator, &.{ DataItem.int(4), DataItem.int(5) }) });
    defer exp3.deinit(allocator);
    const di3 = try decode(allocator, &.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05 });
    defer di3.deinit(allocator);
    try std.testing.expect(exp3.equal(&di3));

    const exp4 = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3), DataItem.int(4), DataItem.int(5), DataItem.int(6), DataItem.int(7), DataItem.int(8), DataItem.int(9), DataItem.int(10), DataItem.int(11), DataItem.int(12), DataItem.int(13), DataItem.int(14), DataItem.int(15), DataItem.int(16), DataItem.int(17), DataItem.int(18), DataItem.int(19), DataItem.int(20), DataItem.int(21), DataItem.int(22), DataItem.int(23), DataItem.int(24), DataItem.int(25) });
    defer exp4.deinit(allocator);
    const di4 = try decode(allocator, &.{ 0x98, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19 });
    defer di4.deinit(allocator);
    try std.testing.expect(exp4.equal(&di4));

    try std.testing.expect(!exp1.equal(&di2));
    try std.testing.expect(!exp1.equal(&di3));
    try std.testing.expect(!exp1.equal(&di4));
    try std.testing.expect(!exp2.equal(&di3));
    try std.testing.expect(!exp2.equal(&di4));
    try std.testing.expect(!exp3.equal(&di4));
}

test "MT5: decode empty cbor map" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.map(allocator, &.{});
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{0xa0});
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));
}

test "MT5: decode cbor map {1:2,3:4}" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.map(allocator, &.{ Pair.new(DataItem.int(1), DataItem.int(2)), Pair.new(DataItem.int(3), DataItem.int(4)) });
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{ 0xa2, 0x01, 0x02, 0x03, 0x04 });
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));
}

test "MT5: decode cbor map {\"a\":1,\"b\":[2,3]}" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "a"), DataItem.int(1)), Pair.new(try DataItem.text(allocator, "b"), try DataItem.array(allocator, &.{ DataItem.int(2), DataItem.int(3) })) });
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{ 0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03 });
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));
}

test "MT5: decode cbor map within array [\"a\",{\"b\":\"c\"}]" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.array(allocator, &.{ try DataItem.text(allocator, "a"), try DataItem.map(allocator, &.{Pair.new(try DataItem.text(allocator, "b"), try DataItem.text(allocator, "c"))}) });
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{ 0x82, 0x61, 0x61, 0xa1, 0x61, 0x62, 0x61, 0x63 });
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));
}

test "MT5: decode cbor map of text pairs" {
    const allocator = std.testing.allocator;

    const exp1 = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "a"), try DataItem.text(allocator, "A")), Pair.new(try DataItem.text(allocator, "b"), try DataItem.text(allocator, "B")), Pair.new(try DataItem.text(allocator, "c"), try DataItem.text(allocator, "C")), Pair.new(try DataItem.text(allocator, "d"), try DataItem.text(allocator, "D")), Pair.new(try DataItem.text(allocator, "e"), try DataItem.text(allocator, "E")) });
    defer exp1.deinit(allocator);
    const di1 = try decode(allocator, &.{ 0xa5, 0x61, 0x61, 0x61, 0x41, 0x61, 0x62, 0x61, 0x42, 0x61, 0x63, 0x61, 0x43, 0x61, 0x64, 0x61, 0x44, 0x61, 0x65, 0x61, 0x45 });
    defer di1.deinit(allocator);
    try std.testing.expect(exp1.equal(&di1));
}
