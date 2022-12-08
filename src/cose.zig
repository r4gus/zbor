const std = @import("std");

const cbor = @import("cbor.zig");
const Error = cbor.Error;
const Type = cbor.Type;
const DataItem = cbor.DataItem;
const Tag = cbor.Tag;
const Pair = cbor.Pair;
const MapIterator = cbor.MapIterator;
const ArrayIterator = cbor.ArrayIterator;
const parse_ = @import("parse.zig");
const stringify = parse_.stringify;
const parse = parse_.parse;

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
};

/// COSE key types
pub const KeyType = enum(u8) {
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

pub const KeyTag = enum { P256 };

pub const Key = union(KeyTag) {
    P256: struct {
        /// kty: Identification of the key type
        @"1": KeyType = .Ec2,
        /// alg: Key usage restriction to this algorithm
        @"3": Algorithm,
        /// crv: EC identifier -- Taken from the "COSE Elliptic Curves" registry
        @"-1": Curve = .P256,
        /// x: x-coordinate
        @"-2_b": [32]u8,
        /// y: y-coordinate
        @"-3_b": [32]u8,
    },

    pub fn fromP256Pub(alg: Algorithm, pk: anytype) @This() {
        const sec1 = pk.toUncompressedSec1();
        return .{ .P256 = .{
            .@"3" = alg,
            .@"-2_b" = sec1[1..33].*,
            .@"-3_b" = sec1[33..65].*,
        } };
    }
};

test "cose Key p256 stringify #1" {
    const EcdsaP256Sha256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

    const x = try EcdsaP256Sha256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");

    const k = Key.fromP256Pub(.Es256, x);

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try stringify(k, .{ .enum_as_text = false }, str.writer());

    try std.testing.expectEqualStrings("\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.items);
}

test "cose Key p256 parse #1" {
    const payload = "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52";

    const di = DataItem.new(payload);

    const key = try parse(Key, di, .{});

    try std.testing.expectEqual(Algorithm.Es256, key.P256.@"3");

    //const x = try EcdsaP256Sha256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
}
