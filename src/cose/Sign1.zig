const std = @import("std");
const cbor = @import("../cbor.zig");
const cose = @import("../cose.zig");
const parse_ = @import("../parse.zig");
const Builder = @import("../builder.zig").Builder;
const Headers = @import("Headers.zig");
const Options = parse_.Options;
const stringify = parse_.stringify;
const parse = parse_.parse;

protected: []const u8,
unprotected: Headers,
payload: []const u8,
signature: []const u8,

pub const Message = struct {
    phdr: Headers,
    uhdr: Headers,
    payload: []const u8,
    external: ?[]const u8 = null,

    pub fn encode(self: *const @This(), allocator: std.mem.Allocator) ![]u8 {
        var str = std.Io.Writer.Allocating.init(allocator);
        defer str.deinit();
        try stringify(self.phdr, .{}, &str.writer);
        const p = str.written();

        var builder = try Builder.withType(allocator, .Array);
        try builder.pushTextString("Signature1");
        try builder.pushByteString(if (p.len == 1 and p[0] == '\xA0') "" else p);
        try builder.pushByteString(if (self.external) |e| e else ""); // external aad
        try builder.pushByteString(self.payload);
        return try builder.finish();
    }

    pub fn sign(
        self: *const @This(),
        key: cose.Key,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const em = try self.encode(allocator);
        defer allocator.free(em);
        return try key.sign(&.{em}, allocator, .{});
    }
};

pub fn generate(
    key: cose.Key,
    payload: []const u8,
    allocator: std.mem.Allocator,
    options: struct {
        external_aad: ?[]const u8 = null,
    },
) !@This() {
    const prot = Headers{
        .alg = key.alg,
    };

    var str = std.Io.Writer.Allocating.init(allocator);
    errdefer str.deinit();
    try stringify(prot, .{}, &str.writer);

    var unprot: Headers = .{};
    if (key.kid) |kid| {
        unprot.kid = try allocator.dupe(u8, kid);
    }
    errdefer if (unprot.kid) |kid| allocator.free(kid);

    const sig_struct = try sig_structure(
        "Signature1",
        str.written(),
        null,
        if (options.external_aad) |aad| aad else "",
        payload,
        allocator,
    );
    defer allocator.free(sig_struct);

    const sig = try key.sign(
        &.{sig_struct},
        allocator,
        .{},
    );
    errdefer allocator.free(sig);

    return .{
        .protected = try str.toOwnedSlice(),
        .unprotected = unprot,
        .payload = try allocator.dupe(u8, payload),
        .signature = sig,
    };
}

pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
    if (self.unprotected.kid) |kid| {
        allocator.free(kid);
    }

    std.crypto.secureZero(u8, @constCast(self.protected));
    allocator.free(self.protected);
    std.crypto.secureZero(u8, @constCast(self.payload));
    allocator.free(self.payload);
    std.crypto.secureZero(u8, @constCast(self.signature));
    allocator.free(self.signature);
}

pub fn sig_structure(
    context: []const u8,
    body_protected: []const u8,
    sign_protected: ?[]const u8,
    external_aad: []const u8,
    payload: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var builder = try Builder.withType(allocator, .Array);
    try builder.pushTextString(context);
    try builder.pushByteString(body_protected);
    if (sign_protected != null and !std.mem.eql(u8, context, "Signature1")) {
        try builder.pushByteString(sign_protected.?);
    }
    try builder.pushByteString(external_aad);
    try builder.pushByteString(payload);
    return try builder.finish();

    //const s = try builder.finish();
    //defer allocator.free(s);

    //var builder2 = try Builder.new(allocator);
    //try builder2.pushByteString(s);
    //return try builder2.finish();
}

test "Single ECDSA Signature - ECDSA w/ SHA-256, Curve P-256 #1" {
    //18(
    //     [
    //       / protected / h'a10126' / {
    //           \ alg \ 1:-7 \ ECDSA 256 \
    //         } / ,
    //       / unprotected / {
    //         / kid / 4:'11'
    //       },
    //       / payload / 'This is the content.',
    //       / signature / h'8eb33e4ca31d1c465ab05aac34cc6b23d58fef5c083106c4
    //   d25a91aef0b0117e2af9a291aa32e14ab834dc56ed2a223444547e01f11d3b0916e5
    //   a4c345cacb36'
    //     ]
    //   )
    const allocator = std.testing.allocator;

    const key = cose.Key{
        .alg = .Es256,
        .crv = .P256,
        .kty = .Ec2,
        .kid = try allocator.dupe(u8, "11"),
        .x = try allocator.dupe(u8, "\xba\xc5\xb1\x1c\xad\x8f\x99\xf9\xc7\x2b\x05\xcf\x4b\x9e\x26\xd2\x44\xdc\x18\x9f\x74\x52\x28\x25\x5a\x21\x9a\x86\xd6\xa0\x9e\xff"),
        .y = try allocator.dupe(u8, "\x20\x13\x8b\xf8\x2d\xc1\xb6\xd5\x62\xbe\x0f\xa5\x4a\xb7\x80\x4a\x3a\x64\xb6\xd7\x2c\xcf\xed\x6b\x6f\xb6\xed\x28\xbb\xfc\x11\x7e"),
        .d = try allocator.dupe(u8, "\x57\xc9\x20\x77\x66\x41\x46\xe8\x76\x76\x0c\x95\x20\xd0\x54\xaa\x93\xc3\xaf\xb0\x4e\x30\x67\x05\xdb\x60\x90\x30\x85\x07\xb4\xd3"),
    };
    defer key.deinit(allocator);

    const sig1 = try generate(
        key,
        "This is the content.",
        allocator,
        .{},
    );
    defer sig1.deinit(allocator);

    try std.testing.expectEqualSlices(u8, "\xa1\x01\x26", sig1.protected);
    try std.testing.expectEqualSlices(u8, "11", sig1.unprotected.kid.?);
    try std.testing.expectEqualSlices(u8, "This is the content.", sig1.payload);
    //try std.testing.expectEqualSlices(u8, "\x8e\xb3\x3e\x4c\xa3\x1d\x1c\x46\x5a\xb0\x5a\xac\x34\xcc\x6b\x23\xd5\x8f\xef\x5c\x08\x31\x06\xc4\xd2\x5a\x91\xae\xf0\xb0\x11\x7e\x2a\xf9\xa2\x91\xaa\x32\xe1\x4a\xb8\x34\xdc\x56\xed\x2a\x22\x34\x44\x54\x7e\x01\xf1\x1d\x3b\x09\x16\xe5\xa4\xc3\x45\xca\xcb\x36", sig1.signature);
}

const test_messages: []const struct { Message, []const u8 } = &.{
    .{
        Message{
            .phdr = .{
                .alg = .Es256,
            },
            .uhdr = .{
                .kid = "11",
            },
            .payload = "This is the content.",
        },
        "\x84\x6a\x53\x69\x67\x6e\x61\x74\x75\x72\x65\x31\x43\xa1\x01\x26\x40\x54\x54\x68\x69\x73\x20\x69\x73\x20\x74\x68\x65\x20\x63\x6f\x6e\x74\x65\x6e\x74\x2e",
    },
    .{
        Message{
            .phdr = .{
                .alg = .Es256,
            },
            .uhdr = .{
                .kid = "11",
            },
            .payload = "This is the content.",
            .external = "\x11\xaa\x22\xbb\x33\xcc\x44\xdd\x55\x00\x66\x99",
        },
        "\x84\x6a\x53\x69\x67\x6e\x61\x74\x75\x72\x65\x31\x43\xa1\x01\x26\x4c\x11\xaa\x22\xbb\x33\xcc\x44\xdd\x55\x00\x66\x99\x54\x54\x68\x69\x73\x20\x69\x73\x20\x74\x68\x65\x20\x63\x6f\x6e\x74\x65\x6e\x74\x2e",
    },
    .{
        Message{
            .phdr = .{},
            .uhdr = .{
                .kid = "11",
                .alg = .Es256,
            },
            .payload = "This is the content.",
        },
        "\x84\x6a\x53\x69\x67\x6e\x61\x74\x75\x72\x65\x31\x40\x40\x54\x54\x68\x69\x73\x20\x69\x73\x20\x74\x68\x65\x20\x63\x6f\x6e\x74\x65\x6e\x74\x2e",
    },
};

test "encode message" {
    const allocator = std.testing.allocator;

    for (test_messages) |m| {
        const emsg = try m.@"0".encode(allocator);
        defer allocator.free(emsg);
        try std.testing.expectEqualSlices(u8, m.@"1", emsg);
    }
}

test "Single ECDSA Signature - ECDSA w/ SHA-256, Curve P-256 #2" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .phdr = .{},
        .uhdr = .{
            .kid = "11",
            .alg = .Es256,
        },
        .payload = "This is the content.",
    };

    const key = cose.Key{
        .alg = .Es256,
        .crv = .P256,
        .kty = .Ec2,
        .kid = try allocator.dupe(u8, "11"),
        .x = try allocator.dupe(u8, "\xba\xc5\xb1\x1c\xad\x8f\x99\xf9\xc7\x2b\x05\xcf\x4b\x9e\x26\xd2\x44\xdc\x18\x9f\x74\x52\x28\x25\x5a\x21\x9a\x86\xd6\xa0\x9e\xff"),
        .y = try allocator.dupe(u8, "\x20\x13\x8b\xf8\x2d\xc1\xb6\xd5\x62\xbe\x0f\xa5\x4a\xb7\x80\x4a\x3a\x64\xb6\xd7\x2c\xcf\xed\x6b\x6f\xb6\xed\x28\xbb\xfc\x11\x7e"),
        .d = try allocator.dupe(u8, "\x57\xc9\x20\x77\x66\x41\x46\xe8\x76\x76\x0c\x95\x20\xd0\x54\xaa\x93\xc3\xaf\xb0\x4e\x30\x67\x05\xdb\x60\x90\x30\x85\x07\xb4\xd3"),
    };
    defer key.deinit(allocator);

    const sig = try msg.sign(key, allocator);
    defer allocator.free(sig);

    try std.testing.expectEqualSlices(u8, "\x87\xdb\x0d\x2e\x55\x71\x84\x3b\x78\xac\x33\xec\xb2\x83\x0d\xf7\xb6\xe0\xa4\xd5\xb7\x37\x6d\xe3\x36\xb2\x3c\x59\x1c\x90\xc4\x25\x31\x7e\x56\x12\x7f\xbe\x04\x37\x00\x97\xce\x34\x70\x87\xb2\x33\xbf\x72\x2b\x64\x07\x2b\xeb\x44\x86\xbd\xa4\x03\x1d\x27\x24\x4f", sig);
}
