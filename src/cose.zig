const std = @import("std");
const DataItem = @import("DataItem.zig");

/// COSE algorithm identifiers
pub const Algorithm = enum(i32) {
    /// RSASSA-PKCS1-v1_5 using SHA-1
    Rs1 = -65535,
    /// WalnutDSA signature
    WalnutDSA = -260,
    /// RSASSA-PKCS1-v1_5 using SHA-512
    Rs512 = -259,
    /// RSASSA-PKCS1-v1_5 using SHA-384
    Rs384 = -258,
    /// RSASSA-PKCS1-v1_5 using SHA-256
    Rs256 = -257,
    /// EdDSA using the Ed448 parameter set in Section 5.2 of [RFC8032]
    Ed448 = -53,
    /// ECDSA using P-521 curve and SHA-512
    ESP512 = -52,
    /// ECDSA using P-384 curve and SHA-384
    ESP384 = -51,
    /// ML-DSA-87 (RFC9964)
    @"ML-DSA-87" = -50,
    /// ML-DSA-65 (RFC9964)
    @"ML-DSA-65" = -49,
    /// ML-DSA-44 (RFC9964)
    @"ML-DSA-44" = -48,
    /// ECDSA using secp256k1 curve and SHA-256
    ES256K = -47,
    /// HSS/LMS hash-based digital signature
    HssLms = -46,
    /// SHAKE-256 512-bit Hash Value
    Shake256 = -45,
    /// SHA-2 512-bit Hash
    Sha512 = -44,
    /// SHA-2 384-bit Hash
    Sha384 = -43,
    /// RSAES-OAEP w/ SHA-512
    RsaesOaepSha512 = -42,
    /// RSAES-OAEP w/ SHA-256
    RsaesOaepSha256 = -41,
    /// RSAES-OAEP w/ SHA-1
    RsaesOaepDefault = -40,
    /// RSASSA-PSS w/ SHA-512
    Ps512 = -39,
    /// RSASSA-PSS w/ SHA-384
    Ps384 = -38,
    /// RSASSA-PSS w/ SHA-256
    Ps256 = -37,
    /// ECDSA w/ SHA-512
    Es512 = -36,
    /// ECDSA w/ SHA-384
    Es384 = -35,
    /// ECDH SS w/ Concat KDF and AES Key Wrap w/ 256-bit key
    EcdhSsA256Kw = -34,
    /// ECDH SS w/ Concat KDF and AES Key Wrap w/ 192-bit key
    EcdhSsA192Kw = -33,
    /// ECDH SS w/ Concat KDF and AES Key Wrap w/ 128-bit key
    EcdhSsA128Kw = -32,
    /// ECDH ES w/ Concat KDF and AES Key Wrap w/ 256-bit key
    EcdhEsA256Kw = -31,
    /// ECDH ES w/ Concat KDF and AES Key Wrap w/ 192-bit key
    EcdhEsA192Kw = -30,
    /// ECDH ES w/ Concat KDF and AES Key Wrap w/ 128-bit key
    EcdhEsA128Kw = -29,
    /// ECDH SS w/ HKDF - generate key directly
    EcdhSsHkdf512 = -28,
    /// ECDH SS w/ HKDF - generate key directly
    EcdhSsHkdf256 = -27,
    /// ECDH ES w/ HKDF - generate key directly
    EcdhEsHkdf512 = -26,
    /// ECDH ES w/ HKDF - generate key directly
    EcdhEsHkdf256 = -25,
    /// SHAKE-128 256-bit Hash Value
    Shake128 = -18,
    /// SHA-2 512-bit Hash truncated to 256-bits
    Sha512_256 = -17,
    /// SHA-2 256-bit Hash
    Sha256 = -16,
    /// SHA-2 256-bit Hash truncated to 64-bits
    Sha256_64 = -15,
    /// SHA-1 Hash
    Sha1 = -14,
    /// Shared secret w/ AES-MAC 256-bit key
    DirectHkdfAes256 = -13,
    /// Shared secret w/ AES-MAC 128-bit key
    DirectHkdfAes128 = -12,
    /// Shared secret w/ HKDF and SHA-512
    DirectHkdfSha512 = -11,
    /// Shared secret w/ HKDF and SHA-256
    DirectHkdfSha256 = -10,
    /// EdDSA
    EdDsa = -8,
    /// ECDSA w/ SHA-256
    Es256 = -7,
    /// Direct use of CEK
    Direct = -6,
    /// AES Key Wrap w/ 256-bit key
    A256Kw = -5,
    /// AES Key Wrap w/ 192-bit key
    A192Kw = -4,
    /// AES Key Wrap w/ 128-bit key
    A128Kw = -3,
    /// AES-GCM mode w/ 128-bit key, 128-bit tag
    A128Gcm = 1,
    /// AES-GCM mode w/ 192-bit key, 128-bit tag
    A192Gcm = 2,
    /// AES-GCM mode w/ 256-bit key, 128-bit tag
    A256Gcm = 3,

    pub fn to_raw(self: @This()) [4]u8 {
        const i = @backingInt(self);
        return std.mem.asBytes(&i).*;
    }

    pub fn from_raw(raw: [4]u8) @This() {
        return @as(@This(), @fromBackingInt(@intCast(std.mem.bytesToValue(i32, &raw))));
    }
};

/// COSE key types
pub const KeyType = enum(u8) {
    Reserved = 0,
    /// Octet Key Pair
    Okp = 1,
    /// Elliptic Curve Keys w/ x- and y-coordinate pair
    Ec2 = 2,
    /// RSA Key
    Rsa = 3,
    /// Symmetric Keys
    Symmetric = 4,
    /// Public key for HSS/LMS hash-based digital signature
    HssLms = 5,
    /// WalnutDSA public key
    WalnutDsa = 6,
    /// COSE Key Type for Algorithm Key Pairs
    AKP = 7,
};

/// COSE elliptic curves
pub const Curve = enum(i16) {
    /// NIST P-256 also known as secp256r1 (EC2)
    P256 = 1,
    /// NIST P-384 also known as secp384r1 (EC2)
    P384 = 2,
    /// NIST P-521 also known as secp521r1 (EC2)
    P521 = 3,
    /// X25519 for use w/ ECDH only (OKP)
    X25519 = 4,
    /// X448 for use w/ ECDH only (OKP)
    X448 = 5,
    /// Ed25519 for use w/ EdDSA only (OKP)
    Ed25519 = 6,
    /// Ed448 for use w/ EdDSA only (OKP)
    Ed448 = 7,
    /// SECG secp256k1 curve (EC2)
    secp256k1 = 8,

    /// Return the `KeyType` of the given elliptic curve
    pub fn keyType(self: @This()) KeyType {
        return switch (self) {
            .P256, .P384, .P521, .secp256k1 => .Ec2,
            else => .Okp,
        };
    }
};

pub const Key = struct {
    /// kty: Identification of the key type
    kty: KeyType,
    kid: ?[]u8 = null,
    /// alg: Key usage restriction to this algorithm
    alg: Algorithm,
    /// crv: EC identifier -- Taken from the "COSE Elliptic Curves" registry
    crv: ?Curve = null,
    /// The public key
    @"pub": ?[]u8 = null,
    /// x: x-coordinate
    x: ?[]u8 = null,
    /// The seed for expanding the private key
    priv: ?[]u8 = null,
    /// y: y-coordinate
    y: ?[]u8 = null,
    /// Private key
    d: ?[]u8 = null,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        if (self.kid) |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
        if (self.x) |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
        if (self.y) |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
        if (self.d) |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
        if (self.@"pub") |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
        if (self.priv) |v| {
            std.crypto.secureZero(u8, v);
            allocator.free(v);
        }
    }

    pub fn getAlg(self: *const @This()) Algorithm {
        return self.alg;
    }

    pub fn getPrivKey(self: *const @This()) !?[]const u8 {
        return switch (self.kty) {
            .Ec2 => self.d,
            .AKP => self.priv,
            else => error.NotYetImplemented, // TODO
        };
    }

    pub fn copy(
        self: *const @This(),
        allocator: std.mem.Allocator,
    ) !@This() {
        return .{
            .kid = if (self.kid) |kid| try allocator.dupe(u8, kid) else null,
            .kty = self.kty,
            .alg = self.alg,
            .crv = self.crv,
            .x = if (self.x) |v| try allocator.dupe(u8, v) else null,
            .y = if (self.y) |v| try allocator.dupe(u8, v) else null,
            .d = if (self.d) |v| try allocator.dupe(u8, v) else null,
            .@"pub" = if (self.@"pub") |v| try allocator.dupe(u8, v) else null,
            .priv = if (self.priv) |v| try allocator.dupe(u8, v) else null,
        };
    }

    pub fn cborDecode(
        di: DataItem,
        options: DataItem.DecodeOptions,
    ) DataItem.DecodeError!@This() {
        if (di.getMajorType() != .Map) return error.UnsupportedType;
        if (options.allocator == null) return error.AllocatorRequired;
        const a = options.allocator.?;

        var kty: ?KeyType = null;
        var kid: ?[]u8 = null;
        errdefer if (kid) |v| a.free(v);
        var crv: ?Curve = null;
        var alg: ?Algorithm = null;
        var x: ?[]u8 = null;
        errdefer if (x) |v| a.free(v);
        var y: ?[]u8 = null;
        errdefer if (y) |v| a.free(v);
        var d: ?[]u8 = null;
        errdefer if (d) |v| a.free(v);

        const len = if (di.isIndef()) null else try di.getLength();

        var i: usize = 0;
        while (true) : (i += 1) {
            if (len != null and i >= len.?) break;

            const key = try di.next();
            if (len == null and key.getType() == .Break) break;

            if (key.getType() != .Int) return error.InvalidKeyType;
            //const key_: i64 = @as(i64, @intCast(try key.getInt()));
            const key_ = try key.getInt();

            const value = try di.next();

            switch (key_) {
                // kty
                1 => {
                    kty = try value.decode(KeyType, options);
                },
                // kid
                2 => {
                    kid = try value.getStringAlloc(a);
                },
                // alg
                3 => {
                    alg = try value.decode(Algorithm, options);
                },
                // crv, pub
                -1 => {
                    if (kty == null) return error.FieldParsingDependencyNotSeenYet;
                    switch (kty.?) {
                        .Okp, .Ec2 => {
                            crv = try value.decode(Curve, options);
                        },
                        else => return error.NotYetImplemented,
                    }
                },
                // x, priv
                -2 => {
                    if (kty == null) return error.FieldParsingDependencyNotSeenYet;
                    switch (kty.?) {
                        .Okp, .Ec2 => {
                            x = try value.getStringAlloc(a);
                        },
                        else => return error.NotYetImplemented,
                    }
                },
                // y
                -3 => {
                    std.debug.print("key_ = {d}, branch = -3\n", .{key_});
                    y = try value.getStringAlloc(a);
                },
                // d
                -4 => {
                    d = try value.getStringAlloc(a);
                },
                else => return error.UnknownField,
            }
        }

        return .{
            .kty = kty orelse return error.MissingField,
            .kid = kid,
            .alg = alg orelse return error.MissingField,
            .crv = crv,
            .x = x,
            .y = y,
            .d = d,
        };
    }
};

test "cose Key p256 parse #1" {
    const payload = "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52";

    var r = std.Io.Reader.fixed(payload);
    var di = try DataItem.new(&r);

    const key = try di.decode(Key, .{
        .allocator = std.testing.allocator,
    });
    defer key.deinit(std.testing.allocator);

    try std.testing.expectEqual(Algorithm.Es256, key.alg);
    try std.testing.expectEqual(KeyType.Ec2, key.kty);
    try std.testing.expectEqual(Curve.P256, key.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", key.x.?);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", key.y.?);
}
