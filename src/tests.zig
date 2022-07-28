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
const pair_asc = core.pair_asc;

const encode = @import("encoder.zig").encode;
const decode = @import("decoder.zig").decode;

const TestError = CborError || error{ TestExpectedEqual, TestUnexpectedResult };

fn test_data_item(data: []const u8, expected: DataItem) TestError!void {
    const allocator = std.testing.allocator;
    const dip = try decode(data, allocator);
    defer dip.deinit();
    try std.testing.expectEqual(expected, dip);
}

fn test_data_item_eql(data: []const u8, expected: *DataItem) TestError!void {
    const allocator = std.testing.allocator;
    const dip = try decode(data, allocator);
    defer dip.deinit();
    defer expected.*.deinit();
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

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    var di5 = DataItem{ .bytes = list };
    defer di5.deinit();

    try std.testing.expect(!di5.equal(&di1));
    try std.testing.expect(!di1.equal(&di5));
    try std.testing.expect(di5.equal(&di5));

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    var di6 = DataItem{ .bytes = list2 };
    defer di6.deinit();

    try std.testing.expect(di5.equal(&di6));
    try di6.bytes.append(123);
    try std.testing.expect(!di5.equal(&di6));
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

    try test_data_item(&.{0b01000000}, DataItem{ .bytes = std.ArrayList(u8).init(allocator) });

    var list = std.ArrayList(u8).init(allocator);
    try list.append(10);
    try test_data_item_eql(&.{ 0b01000001, 0x0a }, &DataItem{ .bytes = list });

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    try list2.append(11);
    try list2.append(12);
    try list2.append(13);
    try list2.append(14);
    try test_data_item_eql(&.{ 0b01000101, 0x0a, 0xb, 0xc, 0xd, 0xe }, &DataItem{ .bytes = list2 });
}

test "MT3: decode cbor text string" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    try test_data_item(&.{0x60}, DataItem{ .text = std.ArrayList(u8).init(allocator) });

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    try list.appendSlice("a");
    const di = try decode(&.{ 0x61, 0x61 }, allocator);
    defer di.deinit();
    try std.testing.expectEqualSlices(u8, list.items, di.text.items);

    index = 0;
    var list2 = std.ArrayList(u8).init(allocator);
    defer list2.deinit();
    try list2.appendSlice("IETF");
    const di2 = try decode(&.{ 0x64, 0x49, 0x45, 0x54, 0x46 }, allocator);
    defer di2.deinit();
    try std.testing.expectEqualSlices(u8, list2.items, di2.text.items);

    index = 0;
    var list3 = std.ArrayList(u8).init(allocator);
    defer list3.deinit();
    try list3.appendSlice("\"\\");
    const di3 = try decode(&.{ 0x62, 0x22, 0x5c }, allocator);
    defer di3.deinit();
    try std.testing.expectEqualSlices(u8, list3.items, di3.text.items);

    // TODO: test unicode https://www.rfc-editor.org/rfc/rfc8949.html#name-examples-of-encoded-cbor-da
}

test "MT4: decode cbor array" {
    const allocator = std.testing.allocator;
    var index: usize = 0;

    var list = std.ArrayList(DataItem).init(allocator);
    defer list.deinit();
    const di = try decode(&.{0x80}, allocator);
    defer di.deinit();
    try std.testing.expectEqualSlices(DataItem, list.items, di.array.items);

    index = 0;
    var list2 = std.ArrayList(DataItem).init(allocator);
    defer list2.deinit();
    try list2.append(DataItem{ .int = 1 });
    try list2.append(DataItem{ .int = 2 });
    try list2.append(DataItem{ .int = 3 });
    const di2 = try decode(&.{ 0x83, 0x01, 0x02, 0x03 }, allocator);
    defer di2.deinit();
    try std.testing.expectEqualSlices(DataItem, list2.items, di2.array.items);

    index = 0;
    var list3 = std.ArrayList(DataItem).init(allocator);
    defer list3.deinit();
    var list3_1 = std.ArrayList(DataItem).init(allocator);
    defer list3_1.deinit();
    var list3_2 = std.ArrayList(DataItem).init(allocator);
    defer list3_2.deinit();
    try list3_1.append(DataItem{ .int = 2 });
    try list3_1.append(DataItem{ .int = 3 });
    try list3_2.append(DataItem{ .int = 4 });
    try list3_2.append(DataItem{ .int = 5 });
    try list3.append(DataItem{ .int = 1 });
    try list3.append(DataItem{ .array = list3_1 });
    try list3.append(DataItem{ .array = list3_2 });
    const expected3 = DataItem{ .array = list3 };
    const di3 = try decode(&.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05 }, allocator);
    defer di3.deinit();
    try std.testing.expect(di3.equal(&expected3));

    index = 0;
    var list4 = std.ArrayList(DataItem).init(allocator);
    defer list4.deinit();
    var i: i128 = 1;
    while (i <= 25) : (i += 1) {
        try list4.append(DataItem{ .int = i });
    }
    const di4 = try decode(&.{ 0x98, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19 }, allocator);
    defer di4.deinit();
    try std.testing.expectEqualSlices(DataItem, list4.items, di4.array.items);
}

test "MT5: decode empty cbor map" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.map.deinit();
    const di = try decode(&.{0xa0}, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));

    try expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try std.testing.expect(!di.equal(&expected));
}

test "MT5: decode cbor map {1:2,3:4}" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();
    try expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try expected.map.append(Pair{ .key = DataItem{ .int = 3 }, .value = DataItem{ .int = 4 } });

    var not_expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer not_expected.map.deinit();
    try not_expected.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try not_expected.map.append(Pair{ .key = DataItem{ .int = 5 }, .value = DataItem{ .int = 4 } });

    const di = try decode(&.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
    try std.testing.expect(!di.equal(&not_expected));
}

test "MT5: decode cbor map {\"a\":1,\"b\":[2,3]}" {
    const allocator = std.testing.allocator;

    // {"a":1,"b":[2,3]}
    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();
    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    try expected.map.append(Pair{ .key = s1, .value = DataItem{ .int = 1 } });
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("b");
    var arr = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try arr.array.append(DataItem{ .int = 2 });
    try arr.array.append(DataItem{ .int = 3 });
    try expected.map.append(Pair{ .key = s2, .value = arr });

    const di = try decode(&.{ 0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03 }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT5: decode cbor map within array" {
    const allocator = std.testing.allocator;

    // ["a",{"b":"c"}]
    var expected = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    defer expected.deinit();

    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    try expected.array.append(s1);

    var map = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("b");
    var s3 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s3.text.appendSlice("c");
    try map.map.append(Pair{ .key = s2, .value = s3 });
    try expected.array.append(map);

    const di = try decode(&.{ 0x82, 0x61, 0x61, 0xa1, 0x61, 0x62, 0x61, 0x63 }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT5: decode cbor map of text pairs" {
    const allocator = std.testing.allocator;

    // ["a",{"b":"c"}]
    var expected = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer expected.deinit();

    var s1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s1.text.appendSlice("a");
    var s2 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s2.text.appendSlice("A");
    var s3 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s3.text.appendSlice("b");
    var s4 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s4.text.appendSlice("B");
    var s5 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s5.text.appendSlice("c");
    var s6 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s6.text.appendSlice("C");
    var s7 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s7.text.appendSlice("d");
    var s8 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s8.text.appendSlice("D");
    var s9 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s9.text.appendSlice("e");
    var s10 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try s10.text.appendSlice("E");

    try expected.map.append(Pair{ .key = s1, .value = s2 });
    try expected.map.append(Pair{ .key = s3, .value = s4 });
    try expected.map.append(Pair{ .key = s5, .value = s6 });
    try expected.map.append(Pair{ .key = s7, .value = s8 });
    try expected.map.append(Pair{ .key = s9, .value = s10 });

    const di = try decode(&.{ 0xa5, 0x61, 0x61, 0x61, 0x41, 0x61, 0x62, 0x61, 0x42, 0x61, 0x63, 0x61, 0x43, 0x61, 0x64, 0x61, 0x44, 0x61, 0x65, 0x61, 0x45 }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT6: decode cbor tagged data item 1(1363896240)" {
    const allocator = std.testing.allocator;

    var item = try allocator.create(DataItem);
    item.* = DataItem{ .int = 1363896240 };
    var expected = DataItem{ .tag = Tag{ .number = 1, .content = item, .allocator = allocator } };
    defer expected.deinit();

    const di = try decode(&.{ 0xc1, 0x1a, 0x51, 0x4b, 0x67, 0xb0 }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT6: decode cbor tagged data item 32(\"http://www.example.com\")" {
    const allocator = std.testing.allocator;

    var item = try allocator.create(DataItem);
    var text = std.ArrayList(u8).init(allocator);
    try text.appendSlice("http://www.example.com");
    item.* = DataItem{ .text = text };
    var expected = DataItem{ .tag = Tag{ .number = 32, .content = item, .allocator = allocator } };
    defer expected.deinit();

    const di = try decode(&.{ 0xd8, 0x20, 0x76, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d }, allocator);
    defer di.deinit();

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 0.0" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = 0.0 } };
    var ne1 = DataItem{ .float = Float{ .float16 = 0.1 } };
    var ne2 = DataItem{ .float = Float{ .float16 = -0.1 } };
    var ne3 = DataItem{ .float = Float{ .float32 = 0.0 } };
    var ne4 = DataItem{ .float = Float{ .float64 = 0.0 } };
    var di = try decode(&.{ 0xf9, 0x00, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
    try std.testing.expect(!di.equal(&ne1));
    try std.testing.expect(!di.equal(&ne2));
    try std.testing.expect(!di.equal(&ne3));
    try std.testing.expect(!di.equal(&ne4));
}

test "MT7: decode f16 -0.0" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = -0.0 } };
    var di = try decode(&.{ 0xf9, 0x80, 0x00 }, allocator);

    try std.testing.expectEqual(expected.float.float16, di.float.float16);
    //try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 1.0" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = 1.0 } };
    var di = try decode(&.{ 0xf9, 0x3c, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 1.5" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = 1.5 } };
    var di = try decode(&.{ 0xf9, 0x3e, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 5.960464477539063e-8" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = 5.960464477539063e-8 } };
    var di = try decode(&.{ 0xf9, 0x00, 0x01 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 0.00006103515625" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = 0.00006103515625 } };
    var di = try decode(&.{ 0xf9, 0x04, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f16 -4.0" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float16 = -4.0 } };
    var di = try decode(&.{ 0xf9, 0xc4, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f32 100000.0" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float32 = 100000.0 } };
    var di = try decode(&.{ 0xfa, 0x47, 0xc3, 0x50, 0x00 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f32 3.4028234663852886e+38" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float32 = 3.4028234663852886e+38 } };
    var di = try decode(&.{ 0xfa, 0x7f, 0x7f, 0xff, 0xff }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f64 1.1" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float64 = 1.1 } };
    var di = try decode(&.{ 0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f64 1.0e+300" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float64 = 1.0e+300 } };
    var di = try decode(&.{ 0xfb, 0x7e, 0x37, 0xe4, 0x3c, 0x88, 0x00, 0x75, 0x9c }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: decode f64 -4.1" {
    const allocator = std.testing.allocator;

    var expected = DataItem{ .float = Float{ .float64 = -4.1 } };
    var di = try decode(&.{ 0xfb, 0xc0, 0x10, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66 }, allocator);

    try std.testing.expect(di.equal(&expected));
}

test "MT7: simple value" {
    const allocator = std.testing.allocator;

    var expected1 = DataItem{ .simple = SimpleValue.False };
    var di1 = try decode(&.{0xf4}, allocator);
    try std.testing.expect(di1.equal(&expected1));

    var expected2 = DataItem{ .simple = SimpleValue.True };
    var di2 = try decode(&.{0xf5}, allocator);
    try std.testing.expect(di2.equal(&expected2));

    var expected3 = DataItem{ .simple = SimpleValue.Null };
    var di3 = try decode(&.{0xf6}, allocator);
    try std.testing.expect(di3.equal(&expected3));

    var expected4 = DataItem{ .simple = SimpleValue.Undefined };
    var di4 = try decode(&.{0xf7}, allocator);
    try std.testing.expect(di4.equal(&expected4));
}

test "decode WebAuthn attestationObject" {
    const allocator = std.testing.allocator;
    const attestationObject = try std.fs.cwd().openFile("data/WebAuthnCreate.dat", .{ .mode = .read_only });
    defer attestationObject.close();
    const bytes = try attestationObject.readToEndAlloc(allocator, 4096);
    defer allocator.free(bytes);

    var di = try decode(bytes, allocator);
    defer di.deinit();

    try std.testing.expect(di.isMap());

    // ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    const fmt = di.getValueByString("fmt");
    try std.testing.expect(fmt.?.isText());
    try std.testing.expectEqualStrings("fido-u2f", fmt.?.text.items);

    // ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    const attStmt = di.getValueByString("attStmt");
    try std.testing.expect(attStmt.?.isMap());
    const authData = di.getValueByString("authData");
    try std.testing.expect(authData.?.isBytes());

    // ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    try std.testing.expectEqual(@as(usize, 196), authData.?.bytes.items.len);

    // ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    const sig = attStmt.?.getValueByString("sig");
    try std.testing.expect(sig.?.isBytes());
    try std.testing.expectEqual(@as(usize, 71), sig.?.bytes.items.len);

    const x5c = attStmt.?.getValueByString("x5c");
    try std.testing.expect(x5c.?.isArray());
    try std.testing.expectEqual(@as(usize, 1), x5c.?.array.items.len);

    const x5c_stmt = x5c.?.get(0);
    try std.testing.expect(x5c_stmt.?.isBytes());
    try std.testing.expectEqual(@as(usize, 704), x5c_stmt.?.bytes.items.len);
}

test "MT0: encode cbor unsigned integer value" {
    const allocator = std.testing.allocator;

    const di1 = DataItem{ .int = 0 };
    const cbor1 = try encode(allocator, &di1);
    defer cbor1.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x00}, cbor1.items);

    const di2 = DataItem{ .int = 23 };
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x17}, cbor2.items);

    const di3 = DataItem{ .int = 24 };
    const cbor3 = try encode(allocator, &di3);
    defer cbor3.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x18 }, cbor3.items);

    const di4 = DataItem{ .int = 255 };
    const cbor4 = try encode(allocator, &di4);
    defer cbor4.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0xff }, cbor4.items);

    const di5 = DataItem{ .int = 256 };
    const cbor5 = try encode(allocator, &di5);
    defer cbor5.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x19, 0x01, 0x00 }, cbor5.items);

    const di6 = DataItem{ .int = 1000 };
    const cbor6 = try encode(allocator, &di6);
    defer cbor6.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x19, 0x03, 0xe8 }, cbor6.items);

    const di7 = DataItem{ .int = 65535 };
    const cbor7 = try encode(allocator, &di7);
    defer cbor7.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x19, 0xff, 0xff }, cbor7.items);

    const di8 = DataItem{ .int = 65536 };
    const cbor8 = try encode(allocator, &di8);
    defer cbor8.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x1a, 0x00, 0x01, 0x00, 0x00 }, cbor8.items);

    const di9 = DataItem{ .int = 4294967295 };
    const cbor9 = try encode(allocator, &di9);
    defer cbor9.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x1a, 0xff, 0xff, 0xff, 0xff }, cbor9.items);

    const di10 = DataItem{ .int = 12345678900 };
    const cbor10 = try encode(allocator, &di10);
    defer cbor10.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x1b, 0x00, 0x00, 0x00, 0x02, 0xdf, 0xdc, 0x1c, 0x34 }, cbor10.items);

    const di11 = DataItem{ .int = 18446744073709551615 };
    const cbor11 = try encode(allocator, &di11);
    defer cbor11.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, cbor11.items);
}

test "MT1: encode cbor signed integer value" {
    const allocator = std.testing.allocator;

    const di1 = DataItem{ .int = -1 };
    const cbor1 = try encode(allocator, &di1);
    defer cbor1.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x20}, cbor1.items);

    const di2 = DataItem{ .int = -3 };
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x22}, cbor2.items);

    const di3 = DataItem{ .int = -100 };
    const cbor3 = try encode(allocator, &di3);
    defer cbor3.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x38, 0x63 }, cbor3.items);

    const di4 = DataItem{ .int = -1000 };
    const cbor4 = try encode(allocator, &di4);
    defer cbor4.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x39, 0x03, 0xe7 }, cbor4.items);

    const di5 = DataItem{ .int = -998877 };
    const cbor5 = try encode(allocator, &di5);
    defer cbor5.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x3a, 0x00, 0x0f, 0x3d, 0xdc }, cbor5.items);

    const di6 = DataItem{ .int = -18446744073709551616 };
    const cbor6 = try encode(allocator, &di6);
    defer cbor6.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, cbor6.items);
}

test "MT2: encode cbor byte string" {
    const allocator = std.testing.allocator;

    var di1 = DataItem{ .bytes = std.ArrayList(u8).init(allocator) };
    defer di1.deinit();
    const cbor1 = try encode(allocator, &di1);
    defer cbor1.deinit();
    try std.testing.expectEqualSlices(u8, &.{0b01000000}, cbor1.items);

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.append(10);
    var di2 = DataItem{ .bytes = list2 };
    defer di2.deinit();
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x41, 0x0a }, cbor2.items);

    var list3 = std.ArrayList(u8).init(allocator);
    try list3.append(10);
    try list3.append(11);
    try list3.append(12);
    try list3.append(13);
    try list3.append(14);
    var di3 = DataItem{ .bytes = list3 };
    defer di3.deinit();
    const cbor3 = try encode(allocator, &di3);
    defer cbor3.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x45, 0x0a, 0xb, 0xc, 0xd, 0xe }, cbor3.items);

    var list4 = std.ArrayList(u8).init(allocator);
    try list4.appendSlice(&.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 });
    var di4 = DataItem{ .bytes = list4 };
    defer di4.deinit();
    const cbor4 = try encode(allocator, &di4);
    defer cbor4.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x58, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 }, cbor4.items);
}

test "MT3: encode cbor text string" {
    const allocator = std.testing.allocator;

    var di1 = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    defer di1.deinit();
    const cbor1 = try encode(allocator, &di1);
    defer cbor1.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x60}, cbor1.items);

    var list2 = std.ArrayList(u8).init(allocator);
    try list2.appendSlice("a");
    var di2 = DataItem{ .text = list2 };
    defer di2.deinit();
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x61, 0x61 }, cbor2.items);

    var list3 = std.ArrayList(u8).init(allocator);
    try list3.appendSlice("IETF");
    var di3 = DataItem{ .text = list3 };
    defer di3.deinit();
    const cbor3 = try encode(allocator, &di3);
    defer cbor3.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x64, 0x49, 0x45, 0x54, 0x46 }, cbor3.items);

    var list4 = std.ArrayList(u8).init(allocator);
    try list4.appendSlice("\"\\");
    var di4 = DataItem{ .text = list4 };
    defer di4.deinit();
    const cbor4 = try encode(allocator, &di4);
    defer cbor4.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x62, 0x22, 0x5c }, cbor4.items);

    // TODO: test unicode https://www.rfc-editor.org/rfc/rfc8949.html#name-examples-of-encoded-cbor-da
}

test "MT4: encode cbor array" {
    const allocator = std.testing.allocator;

    var di1 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    defer di1.deinit();
    const cbor1 = try encode(allocator, &di1);
    defer cbor1.deinit();
    try std.testing.expectEqualSlices(u8, &.{0x80}, cbor1.items);

    var di2 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try di2.array.append(DataItem{ .int = 1 });
    try di2.array.append(DataItem{ .int = 2 });
    try di2.array.append(DataItem{ .int = 3 });
    defer di2.deinit();
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x83, 0x01, 0x02, 0x03 }, cbor2.items);

    var di3_1 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try di3_1.array.append(DataItem{ .int = 2 });
    try di3_1.array.append(DataItem{ .int = 3 });
    var di3_2 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try di3_2.array.append(DataItem{ .int = 4 });
    try di3_2.array.append(DataItem{ .int = 5 });
    var di3 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    try di3.array.append(DataItem{ .int = 1 });
    try di3.array.append(di3_1);
    try di3.array.append(di3_2);
    defer di3.deinit();
    const cbor3 = try encode(allocator, &di3);
    defer cbor3.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05 }, cbor3.items);

    var di4 = DataItem{ .array = std.ArrayList(DataItem).init(allocator) };
    defer di4.deinit();
    var i: i128 = 1;
    while (i <= 25) : (i += 1) {
        try di4.array.append(DataItem{ .int = i });
    }
    const cbor4 = try encode(allocator, &di4);
    defer cbor4.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0x98, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19 }, cbor4.items);
}

test "MT5: encode empty cbor map" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    defer di.deinit();
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{0xa0}, cbor.items);
}

test "MT5: encode cbor map {1:2,3:4}" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    try di.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    try di.map.append(Pair{ .key = DataItem{ .int = 3 }, .value = DataItem{ .int = 4 } });
    defer di.deinit();
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, cbor.items);

    // Keys should be sorted in asc order.
    var di2 = DataItem{ .map = std.ArrayList(Pair).init(allocator) };
    try di2.map.append(Pair{ .key = DataItem{ .int = 3 }, .value = DataItem{ .int = 4 } });
    try di2.map.append(Pair{ .key = DataItem{ .int = 1 }, .value = DataItem{ .int = 2 } });
    defer di2.deinit();
    const cbor2 = try encode(allocator, &di2);
    defer cbor2.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x01, 0x02, 0x03, 0x04 }, cbor2.items);
}

test "MT6: encode cbor tagged data item 1(1363896240)" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .tag = Tag{ .number = 1, .content = try allocator.create(DataItem), .allocator = allocator } };
    defer di.deinit();
    di.tag.content.* = DataItem{ .int = 1363896240 };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xc1, 0x1a, 0x51, 0x4b, 0x67, 0xb0 }, cbor.items);
}

test "MT6: encode cbor tagged data item 32(\"http://www.example.com\")" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .tag = Tag{ .number = 32, .content = try allocator.create(DataItem), .allocator = allocator } };
    defer di.deinit();
    di.tag.content.* = DataItem{ .text = std.ArrayList(u8).init(allocator) };
    try di.tag.content.text.appendSlice("http://www.example.com");
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xd8, 0x20, 0x76, 0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d }, cbor.items);
}

test "MT7: encode f16 0.0" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = 0.0 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x00, 0x00 }, cbor.items);
}

test "MT7: encode f16 -0.0" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = -0.0 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x80, 0x00 }, cbor.items);
}

test "MT7: encode f16 1.0" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = 1.0 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x3c, 0x00 }, cbor.items);
}

test "MT7: encode f16 1.5" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = 1.5 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x3e, 0x00 }, cbor.items);
}

test "MT7: encode f16 5.960464477539063e-8" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = 5.960464477539063e-8 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x00, 0x01 }, cbor.items);
}

test "MT7: encode f16 0.00006103515625" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = 0.00006103515625 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0x04, 0x00 }, cbor.items);
}

test "MT7: encode f16 -4.0" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float16 = -4.0 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xf9, 0xc4, 0x00 }, cbor.items);
}

test "MT7: encode f32 100000.0" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float32 = 100000.0 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfa, 0x47, 0xc3, 0x50, 0x00 }, cbor.items);
}

test "MT7: encode f32 3.4028234663852886e+38" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float32 = 3.4028234663852886e+38 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfa, 0x7f, 0x7f, 0xff, 0xff }, cbor.items);
}

test "MT7: encode f64 1.1" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float64 = 1.1 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a }, cbor.items);
}

test "MT7: encode f64 1.0e+300" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float64 = 1.0e+300 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0x7e, 0x37, 0xe4, 0x3c, 0x88, 0x00, 0x75, 0x9c }, cbor.items);
}

test "MT7: encode f64 -4.1" {
    const allocator = std.testing.allocator;

    var di = DataItem{ .float = Float{ .float64 = -4.1 } };
    const cbor = try encode(allocator, &di);
    defer cbor.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xc0, 0x10, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66 }, cbor.items);
}

test "MT0,1: DataItem{ .int = 30 } to json" {
    const allocator = std.testing.allocator;

    const di = DataItem{ .int = 30 };

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(di, .{}, string.writer());

    try std.testing.expectEqualStrings("30", string.items);
}

test "MT2: DataItem to json" {
    const allocator = std.testing.allocator;

    const di = try DataItem.bytes(allocator, &.{ 0x95, 0x28, 0xe0, 0x8f, 0x32, 0xda, 0x3d, 0x36, 0x83, 0xc4, 0x6a, 0x1c, 0x36, 0x58, 0xb4, 0x86, 0x47, 0x2b });
    defer di.deinit();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(di, .{}, string.writer());

    try std.testing.expectEqualStrings("\"lSjgjzLaPTaDxGocNli0hkcr\"", string.items);
}

test "MT3: DataItem to json" {
    const allocator = std.testing.allocator;

    const di = try DataItem.text(allocator, "fido-u2f");
    defer di.deinit();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(di, .{}, string.writer());

    try std.testing.expectEqualStrings("\"fido-u2f\"", string.items);
}

test "MT4: DataItem to json" {
    const allocator = std.testing.allocator;

    const di = try DataItem.array(allocator, &.{ DataItem.int(1), DataItem.int(2), DataItem.int(3) });
    defer di.deinit();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(di, .{}, string.writer());

    try std.testing.expectEqualStrings("[1,2,3]", string.items);
}

test "MT5: DataItem to json" {
    const allocator = std.testing.allocator;

    const di = try DataItem.map(allocator, &.{ Pair.new(try DataItem.text(allocator, "a"), DataItem.int(1)), Pair.new(try DataItem.text(allocator, "b"), try DataItem.array(allocator, &.{ DataItem.int(2), DataItem.int(3) })) });
    defer di.deinit();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(di, .{}, string.writer());

    try std.testing.expectEqualStrings("{\"a\":1,\"b\":[2,3]}", string.items);
}

test "MT7: DataItem to json (false, true, null)" {
    const allocator = std.testing.allocator;

    const di1 = DataItem.False();
    const di2 = DataItem.True();
    const di3 = DataItem.Null();
    const di4 = DataItem.Undefined();

    const json1 = try di1.toJson(allocator);
    defer json1.deinit();
    const json2 = try di2.toJson(allocator);
    defer json2.deinit();
    const json3 = try di3.toJson(allocator);
    defer json3.deinit();
    const json4 = try di4.toJson(allocator);
    defer json4.deinit();

    try std.testing.expectEqualStrings("false", json1.items);
    try std.testing.expectEqualStrings("true", json2.items);
    try std.testing.expectEqualStrings("null", json3.items);
    // Any other simple value is represented as the substitue value (null).
    try std.testing.expectEqualStrings("null", json4.items);
}
