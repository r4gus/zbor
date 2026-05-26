const std = @import("std");

const cbor = @import("cbor.zig");
const Type = cbor.Type;
const DataItem = cbor.DataItem;
const Tag = cbor.Tag;
const Pair = cbor.Pair;
const MapIterator = cbor.MapIterator;
const ArrayIterator = cbor.ArrayIterator;
const parse_ = @import("parse.zig");
const stringify = parse_.stringify;
const parse = parse_.parse;
const Options = parse_.Options;

const EcdsaP256Sha256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

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
        const i = @intFromEnum(self);
        return std.mem.asBytes(&i).*;
    }

    pub fn from_raw(raw: [4]u8) @This() {
        return @as(@This(), @enumFromInt(std.mem.bytesToValue(i32, &raw)));
    }
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
    kid: ?[]u8 = null,
    /// kty: Identification of the key type
    kty: KeyType,
    /// alg: Key usage restriction to this algorithm
    alg: Algorithm,
    /// crv: EC identifier -- Taken from the "COSE Elliptic Curves" registry
    crv: ?Curve = null,
    /// x: x-coordinate
    x: ?[]u8 = null,
    /// y: y-coordinate
    y: ?[]u8 = null,
    /// Private key
    d: ?[]u8 = null,
    /// The public key
    @"pub": ?[]u8 = null,
    /// The seed for expanding the private key
    priv: ?[]u8 = null,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        if (self.kid) |v| allocator.free(v);
        if (self.x) |v| allocator.free(v);
        if (self.y) |v| allocator.free(v);
        if (self.d) |v| allocator.free(v);
        if (self.@"pub") |v| allocator.free(v);
        if (self.priv) |v| allocator.free(v);
    }

    pub fn getAlg(self: *const @This()) Algorithm {
        return self.alg;
    }

    pub fn getPrivKey(self: *const @This()) ?[]const u8 {
        return switch (self.kty) {
            .Ec2 => self.d,
            .AKP => self.priv,
            else => null, // TODO
        };
    }

    pub fn copySecure(
        self: *const @This(),
        allocator: std.mem.Allocator,
    ) !@This() {
        switch (self.kty) {
            .Ec2 => {
                return .{
                    .kid = if (self.kid) |kid| try allocator.dupe(u8, kid) else null,
                    .kty = self.kty,
                    .alg = self.alg,
                    .crv = self.crv,
                    .x = if (self.x) |v| try allocator.dupe(u8, v) else null,
                    .y = if (self.y) |v| try allocator.dupe(u8, v) else null,
                    .d = null,
                };
            },
            .AKP => {
                return .{
                    .kid = if (self.kid) |kid| try allocator.dupe(u8, kid) else null,
                    .kty = self.kty,
                    .alg = self.alg,
                    .@"pub" = if (self.@"pub") |v| try allocator.dupe(u8, v) else null,
                    .priv = null,
                };
            },
            else => return error.UnsupportedKeyType, // TODO
        }
    }

    pub fn fromP256Pub(alg: Algorithm, pk: anytype, allocator: std.mem.Allocator) !@This() {
        const sec1 = pk.toUncompressedSec1();
        return .{
            .kty = .Ec2,
            .alg = alg,
            .crv = .P256,
            .x = try allocator.dupe(u8, sec1[1..33]),
            .y = try allocator.dupe(u8, sec1[33..65]),
        };
    }

    pub fn fromP256PrivPub(
        alg: Algorithm,
        privk: anytype,
        pubk: anytype,
        allocator: std.mem.Allocator,
    ) !@This() {
        const sec1 = pubk.toUncompressedSec1();
        const pk = privk.toBytes();
        return .{
            .kty = .Ec2,
            .alg = alg,
            .crv = .P256,
            .x = try allocator.dupe(u8, sec1[1..33]),
            .y = try allocator.dupe(u8, sec1[33..65]),
            .d = try allocator.dupe(u8, &pk),
        };
    }

    /// Creates a new ECDSA P-256 (secp256r1) key pair for the ES256 algorithm.
    ///
    /// - `io`: `std.Io` interface
    ///
    /// Returns the newly created key pair as a structure containing the algorithm identifier,
    /// public key coordinates, and the secret key.
    ///
    /// # Examples
    ///
    /// ```zig
    /// const cbor = @import("zbor");
    /// var io_impl = std.Io.Threaded.init_single_threaded;
    /// const io = io_impl.io();
    /// const keyPair = cbor.cose.Key.es256(io);
    ///
    /// // Use the key pair...
    /// ```
    pub fn es256(
        allocator: std.mem.Allocator,
        io: std.Io,
    ) !@This() {
        const kp = EcdsaP256Sha256.KeyPair.generate(io);
        const sec1 = kp.public_key.toUncompressedSec1();
        const pk = kp.secret_key.toBytes();
        return .{
            .kty = .Ec2,
            .alg = .Es256,
            .x = try allocator.dupe(u8, sec1[1..33]),
            .y = try allocator.dupe(u8, sec1[33..65]),
            .d = try allocator.dupe(u8, &pk),
        };
    }

    pub fn mlDsa87(
        allocator: std.mem.Allocator,
        io: std.Io,
    ) !@This() {
        const e = std.crypto.sign.mldsa.MLDSA87;

        var seed: [e.seed_length]u8 = undefined;
        io.random(&seed);
        // The generate() function in std calls it the same, i.e.
        // unreachable is fine.
        const kp = e.KeyPair.generateDeterministic(seed) catch unreachable;

        return .{
            .kty = .AKP,
            .alg = .@"ML-DSA-87",
            .@"pub" = try allocator.dupe(u8, &kp.public_key.toBytes()),
            .priv = try allocator.dupe(u8, &seed),
        };
    }

    /// Signs the provided data using the specified algorithm and key.
    ///
    /// - `data_seq`: A sequence of data slices to be signed together.
    /// - `allocator`: Allocator to allocate memory for the signature.
    ///
    /// Returns the DER-encoded signature as a dynamically allocated byte slice,
    /// or an error if the algorithm or key is unsupported.
    ///
    /// The user is responsible for freeing the allocated memory.
    ///
    /// # Errors
    ///
    /// - `error.UnsupportedAlgorithm`: If the algorithm is not supported.
    ///
    /// # Examples
    ///
    /// ```zig
    /// const result = try key.sign(&.{data}, allocator);
    ///
    /// // Use the signature...
    /// ```
    pub fn sign(
        self: *const @This(),
        data_seq: []const []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        switch (self.alg) {
            .Es256 => {
                if (self.d == null) return error.MissingPrivateKey;

                var kp = try EcdsaP256Sha256.KeyPair.fromSecretKey(
                    try EcdsaP256Sha256.SecretKey.fromBytes(self.d.?[0..EcdsaP256Sha256.SecretKey.encoded_length].*),
                );
                var signer = try kp.signer(null);

                // Append data that should be signed together
                for (data_seq) |data| {
                    signer.update(data);
                }

                // Sign the data
                const sig = try signer.finalize();
                var buffer: [EcdsaP256Sha256.Signature.der_encoded_length_max]u8 = undefined;
                const der = sig.toDer(&buffer);
                const mem = try allocator.alloc(u8, der.len);
                @memcpy(mem, der);
                return mem;
            },
            else => return error.UnsupportedAlgorithm,
        }
    }

    /// Verifies a signature using the provided public key and a data sequence.
    ///
    /// - `signature`: signature to be verified.
    /// - `data_seq`: Array of data slices that were signed together.
    ///
    /// Returns `true` if the signature is valid, `false` otherwise.
    ///
    /// # Examples
    ///
    /// ```zig
    /// const signatureValid = try key.verify(signature, &.{data});
    /// if (signatureValid) {
    ///     // Signature is valid
    /// } else {
    ///     // Signature is not valid
    /// }
    /// ```
    pub fn verify(
        self: *const @This(),
        signature: []const u8,
        data_seq: []const []const u8,
    ) !bool {
        switch (self.alg) {
            .Es256 => {
                if (self.x == null) return error.MissingX;
                if (self.y == null) return error.MissingY;

                // Get public key struct
                var usec1: [65]u8 = undefined;
                usec1[0] = 4;
                @memcpy(usec1[1..33], self.x.?[0..32]);
                @memcpy(usec1[33..65], self.y.?[0..32]);
                const pk = try EcdsaP256Sha256.PublicKey.fromSec1(&usec1);
                // Get signature struct
                const sig = try EcdsaP256Sha256.Signature.fromDer(signature);
                // Get verifier
                var verifier = try sig.verifier(pk);
                for (data_seq) |data| {
                    verifier.update(data);
                }
                verifier.verify() catch {
                    // Verification failed
                    return false;
                };

                return true;
            },
            else => return error.UnsupportedAlgorithm,
        }
    }

    pub fn cborStringify(self: *const @This(), options: Options, out: anytype) !void {
        _ = options;
        return stringify(self, .{
            .ignore_override = true,
            .field_settings = &.{
                .{
                    .name = "kty",
                    .field_options = .{
                        .alias = "1",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{ .name = "kid", .field_options = .{
                    .alias = "2",
                    .serialization_type = .Integer,
                } },
                .{
                    .name = "alg",
                    .field_options = .{
                        .alias = "3",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{
                    .name = "crv",
                    .field_options = .{
                        .alias = "-1",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{ .name = "x", .field_options = .{
                    .alias = "-2",
                    .serialization_type = .Integer,
                } },
                .{ .name = "y", .field_options = .{
                    .alias = "-3",
                    .serialization_type = .Integer,
                } },
                .{ .name = "d", .field_options = .{
                    .alias = "-4",
                    .serialization_type = .Integer,
                } },
                .{ .name = "pub", .field_options = .{
                    .alias = "-1",
                    .serialization_type = .Integer,
                } },
                .{ .name = "priv", .field_options = .{
                    .alias = "-2",
                    .serialization_type = .Integer,
                } },
            },
        }, out);
    }

    pub fn cborParse(item: cbor.DataItem, options: Options) !@This() {
        return try parse(@This(), item, .{
            .allocator = options.allocator,
            .ignore_override = true, // prevent infinite loops
            .field_settings = &.{
                .{
                    .name = "kty",
                    .field_options = .{
                        .alias = "1",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{ .name = "kid", .field_options = .{
                    .alias = "2",
                    .serialization_type = .Integer,
                } },
                .{
                    .name = "alg",
                    .field_options = .{
                        .alias = "3",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{
                    .name = "crv",
                    .field_options = .{
                        .alias = "-1",
                        .serialization_type = .Integer,
                    },
                    .value_options = .{ .enum_serialization_type = .Integer },
                },
                .{ .name = "x", .field_options = .{
                    .alias = "-2",
                    .serialization_type = .Integer,
                } },
                .{ .name = "y", .field_options = .{
                    .alias = "-3",
                    .serialization_type = .Integer,
                } },
                .{ .name = "d", .field_options = .{
                    .alias = "-4",
                    .serialization_type = .Integer,
                } },
                .{ .name = "pub", .field_options = .{
                    .alias = "-1",
                    .serialization_type = .Integer,
                } },
                .{ .name = "priv", .field_options = .{
                    .alias = "-2",
                    .serialization_type = .Integer,
                } },
            },
        });
    }
};

test "cose Key p256 stringify #1" {
    const x = try EcdsaP256Sha256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");

    const k = try Key.fromP256Pub(.Es256, x, std.testing.allocator);
    defer k.deinit(std.testing.allocator);

    const allocator = std.testing.allocator;
    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try stringify(k, .{}, &str.writer);

    try std.testing.expectEqualSlices(u8, "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.written());
}

test "cose Key p256 parse #1" {
    const payload = "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52";

    const di = try DataItem.new(payload);

    const key = try parse(Key, di, .{
        .allocator = std.testing.allocator,
    });
    defer key.deinit(std.testing.allocator);

    try std.testing.expectEqual(Algorithm.Es256, key.alg);
    try std.testing.expectEqual(KeyType.Ec2, key.kty);
    try std.testing.expectEqual(Curve.P256, key.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", key.x.?);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", key.y.?);
}

test "alg to raw" {
    const es256 = Algorithm.Es256;
    const x: [4]u8 = es256.to_raw();

    try std.testing.expectEqualSlices(u8, "\xF9\xFF\xFF\xFF", &x);
}

test "raw to alg" {
    const x: [4]u8 = "\xF9\xFF\xFF\xFF".*;

    try std.testing.expectEqual(Algorithm.Es256, Algorithm.from_raw(x));
}

test "es256 sign verify 1" {
    const allocator = std.testing.allocator;
    const msg = "Hello, World!";

    const kp1 = EcdsaP256Sha256.KeyPair.generate(std.testing.io);

    // Create a signature via cose key struct
    var cosep256 = try Key.fromP256PrivPub(.Es256, kp1.secret_key, kp1.public_key, std.testing.allocator);
    defer cosep256.deinit(std.testing.allocator);
    const sig_der_1 = try cosep256.sign(&.{msg}, allocator);
    defer allocator.free(sig_der_1);

    // Verify the created signature
    const sig1 = try EcdsaP256Sha256.Signature.fromDer(sig_der_1);
    sig1.verify(msg, kp1.public_key) catch {
        try std.testing.expect(false); // expected void but got error
    };

    // Verify the created signature again
    try std.testing.expectEqual(true, try cosep256.verify(sig_der_1, &.{msg}));

    // Create another key-pair
    var kp2 = try Key.es256(std.testing.allocator, std.testing.io);
    defer kp2.deinit(std.testing.allocator);

    // Trying to verfiy the first signature using the new key-pair should fail
    try std.testing.expectEqual(false, try kp2.verify(sig_der_1, &.{msg}));
}

test "copy secure #1" {
    const kp1 = EcdsaP256Sha256.KeyPair.generate(std.testing.io);
    var cosep256 = try Key.fromP256PrivPub(.Es256, kp1.secret_key, kp1.public_key, std.testing.allocator);
    defer cosep256.deinit(std.testing.allocator);
    const cpy = try cosep256.copySecure(std.testing.allocator);
    defer cpy.deinit(std.testing.allocator);
    try std.testing.expectEqual(cpy.d, null);
}

test "ML-DSA-87 #1" {
    const kp = try Key.mlDsa87(std.testing.allocator, std.testing.io);
    defer kp.deinit(std.testing.allocator);
}
