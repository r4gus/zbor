const std = @import("std");
const DataItem = @import("DataItem.zig");

pub fn expectAnyError(result: anytype) !void {
    if (result) |_| {
        return error.TestExpectedError;
    } else |_| {}
}

test "struct key claiming 2^64-1 bytes is rejected" {
    const S = struct { a: ?u8 = null };

    // {text(2^64-1): ...}
    var reader = std.Io.Reader.fixed("\xa1\x7b\xff\xff\xff\xff\xff\xff\xff\xff");
    var di = try DataItem.new(&reader);
    try expectAnyError(di.decode(S, .{}));
}

test "struct key claiming 2^64-9 bytes inside an indefinite map is rejected" {
    const S = struct { a: ?u8 = null };

    // In ReleaseFast the wrapped seek moved backwards and re-read the same
    // head forever.
    var reader = std.Io.Reader.fixed("\xbf\x7b\xff\xff\xff\xff\xff\xff\xff\xf7\xff");
    var di = try DataItem.new(&reader);
    try expectAnyError(di.decode(S, .{}));
}

test "enum value claiming 2^64-1 bytes is rejected" {
    const E = enum { a, b };

    var reader = std.Io.Reader.fixed("\x7b\xff\xff\xff\xff\xff\xff\xff\xff");
    var di = try DataItem.new(&reader);
    try expectAnyError(di.decode(E, .{}));
}

test "key longer than a streaming reader's buffer does not assert" {
    const S = struct { a: ?u8 = null };

    // {"zzz...z" (200 bytes): 1, "a": 5} read through a 16-byte buffer
    const input = "\xa2\x78\xc8" ++ @as([200]u8, @splat('z')) ++ "\x01" ++ "\x61a\x05";

    var fixed = std.Io.Reader.fixed(input);
    var small: [16]u8 = undefined;
    var indirect = std.testing.ReaderIndirect.init(&fixed, small[0..]);
    var di = try DataItem.new(&indirect.interface);

    const s = try di.decode(S, .{});
    try std.testing.expectEqual(@as(?u8, 5), s.a);
}

// The following tests don't pass due to an issue with the Zig std.Io.Reader
// see: https://codeberg.org/ziglang/zig/issues/37599

//test "discardAll" {
//    const l: usize = std.math.maxInt(usize);
//    var reader = std.Io.Reader.fixed("\xa1\x61\x7a\x5b\xff\xff\xff\xff\xff\xff\xff\xff");
//    const v = try reader.take(1);
//    _ = v;
//    try reader.discardAll(l);
//}

//test "F2: unknown field whose value is a byte string of 2^64-1 bytes" {
//    const S = struct { a: ?u8 = null };
//    // {"z": bytes(2^64-1)}
//    var reader = std.Io.Reader.fixed("\xa1\x61\x7a\x5b\xff\xff\xff\xff\xff\xff\xff\xff");
//    var di = try DataItem.new(&reader);
//    try std.testing.expectError(error.EndOfStream, di.decode(S, .{}));
//}
//
//test "F2: unknown field whose value is a text string of 2^64-1 bytes" {
//    const S = struct { a: ?u8 = null };
//    // {"z": text(2^64-1)}
//    var reader = std.Io.Reader.fixed("\xa1\x61\x7a\x7b\xff\xff\xff\xff\xff\xff\xff\xff");
//    var di = try DataItem.new(&reader);
//    try std.testing.expectError(error.EndOfStream, di.decode(S, .{}));
//}
//
//test "F2: unknown field of 2^64-9 bytes inside an indefinite map" {
//    const S = struct { a: ?u8 = null };
//    // In ReleaseFast the wrapped seek moved backwards so the decoder
//    // re-read the same head forever.
//    var reader = std.Io.Reader.fixed("\xbf\x61\x7a\x5b\xff\xff\xff\xff\xff\xff\xff\xf7\xff");
//    var di = try DataItem.new(&reader);
//    try std.testing.expectError(error.EndOfStream, di.decode(S, .{}));
//}
//
//test "F2: toOwnedSlice on a string of 2^64-1 bytes" {
//    var reader = std.Io.Reader.fixed("\x5b\xff\xff\xff\xff\xff\xff\xff\xff");
//    var di = try DataItem.new(&reader);
//    try expectAnyError(di.toOwnedSlice(std.testing.allocator));
//}

test "sentinel string claiming 2^64-1 bytes" {
    const allocator = std.testing.allocator;

    // bytes(2^64-1) -> alloc(u8, l + 1) overflows to 0 in ReleaseFast and
    // `readSliceAll` then writes through a zero-length allocation.
    var reader = std.Io.Reader.fixed("\x5b\xff\xff\xff\xff\xff\xff\xff\xff\x01\x02\x03");
    var di = try DataItem.new(&reader);
    try expectAnyError(di.decode([:0]const u8, .{ .allocator = allocator }));
}

test "sentinel string field claiming 2^64-1 bytes" {
    const allocator = std.testing.allocator;
    const S = struct { name: [:0]const u8 };

    // {"name": bytes(2^64-1)}
    var reader = std.Io.Reader.fixed("\xa1\x64name\x5b\xff\xff\xff\xff\xff\xff\xff\xff");
    var di = try DataItem.new(&reader);
    try expectAnyError(di.decode(S, .{ .allocator = allocator }));
}

test "sentinel strings and arrays still decode correctly" {
    const allocator = std.testing.allocator;

    var r1 = std.Io.Reader.fixed("\x65hello");
    var di1 = try DataItem.new(&r1);
    const s = try di1.decode([:0]const u8, .{ .allocator = allocator });
    defer allocator.free(s);
    const e: [:0]const u8 = "hello";
    try std.testing.expectEqualStrings(e, s);

    // [1, 2, 3] -> {1, 2, 3} with a terminating 0, not {1, 2, 3, 0}
    var r2 = std.Io.Reader.fixed("\x83\x01\x02\x03");
    var di2 = try DataItem.new(&r2);
    const a = try di2.decode([:0]const u32, .{ .allocator = allocator });
    defer allocator.free(a);
    const e2: [:0]const u32 = &.{ 1, 2, 3, 0 };
    try std.testing.expectEqualSlices(u32, e2, a);
}
