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
        kty: KeyType = .Ec2,
        /// alg: Key usage restriction to this algorithm
        alg: Algorithm,
        /// crv: EC identifier -- Taken from the "COSE Elliptic Curves" registry
        crv: Curve = .P256,
        /// x: x-coordinate
        x: [32]u8,
        /// y: y-coordinate
        y: [32]u8,
        /// Private key
        d: ?[32]u8 = null,
    },

    pub fn getAlg(self: *const @This()) Algorithm {
        switch (self.*) {
            .P256 => |k| return k.alg,
        }
    }

    pub fn getPrivKey(self: *const @This()) []const u8 {
        switch (self.*) {
            .P256 => |k| {
                return if (k.d) |d| d[0..] else null;
            },
        }
    }

    pub fn copySecure(self: *const @This()) @This() {
        switch (self.*) {
            .P256 => |k| {
                return .{ .P256 = .{
                    .kty = k.kty,
                    .alg = k.alg,
                    .crv = k.crv,
                    .x = k.x,
                    .y = k.y,
                    .d = null,
                } };
            },
        }
    }

    pub fn fromP256Pub(alg: Algorithm, pk: anytype) @This() {
        const sec1 = pk.toUncompressedSec1();
        return .{ .P256 = .{
            .alg = alg,
            .x = sec1[1..33].*,
            .y = sec1[33..65].*,
        } };
    }

    pub fn fromP256PrivPub(alg: Algorithm, privk: anytype, pubk: anytype) @This() {
        const sec1 = pubk.toUncompressedSec1();
        const pk = privk.toBytes();
        return .{ .P256 = .{
            .alg = alg,
            .x = sec1[1..33].*,
            .y = sec1[33..65].*,
            .d = pk,
        } };
    }

    /// Creates a new ECDSA P-256 (secp256r1) key pair for the ES256 algorithm.
    ///
    /// - `seed`: Optional seed to derive the key pair from. If `null`, a random seed will be used.
    ///
    /// Returns the newly created key pair as a structure containing the algorithm identifier,
    /// public key coordinates, and the secret key.
    ///
    /// # Examples
    ///
    /// ```zig
    /// const cbor = @import("zbor");
    /// const keyPair = try cbor.cose.Key.es256(null);
    ///
    /// // Use the key pair...
    /// ```
    pub fn es256(seed: ?[32]u8) !@This() {
        const kp = if (seed) |seed_|
            try EcdsaP256Sha256.KeyPair.generateDeterministic(seed_)
        else
            EcdsaP256Sha256.KeyPair.generate();
        const sec1 = kp.public_key.toUncompressedSec1();
        const pk = kp.secret_key.toBytes();
        return .{ .P256 = .{
            .alg = .Es256,
            .x = sec1[1..33].*,
            .y = sec1[33..65].*,
            .d = pk,
        } };
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
        switch (self.*) {
            .P256 => |k| {
                if (k.d == null) return error.MissingPrivateKey;

                switch (k.alg) {
                    .Es256 => {
                        var kp = try EcdsaP256Sha256.KeyPair.fromSecretKey(
                            try EcdsaP256Sha256.SecretKey.fromBytes(k.d.?),
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
            },
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
        switch (self.*) {
            .P256 => |k| {
                switch (k.alg) {
                    .Es256 => {
                        // Get public key struct
                        var usec1: [65]u8 = undefined;
                        usec1[0] = 4;
                        @memcpy(usec1[1..33], &k.x);
                        @memcpy(usec1[33..65], &k.y);
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
            },
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
                },
                .{
                    .name = "alg",
                    .field_options = .{
                        .alias = "3",
                        .serialization_type = .Integer,
                    },
                },
                .{
                    .name = "crv",
                    .field_options = .{
                        .alias = "-1",
                        .serialization_type = .Integer,
                    },
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
            },
        });
    }
};

test "cose Key p256 stringify #1" {
    const x = try EcdsaP256Sha256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");

    const k = Key.fromP256Pub(.Es256, x);

    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    try stringify(k, .{}, str.writer());

    try std.testing.expectEqualSlices(u8, "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.items);
}

test "cose Key p256 parse #1" {
    const payload = "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52";

    const di = try DataItem.new(payload);

    const key = try parse(Key, di, .{});

    try std.testing.expectEqual(Algorithm.Es256, key.P256.alg);
    try std.testing.expectEqual(KeyType.Ec2, key.P256.kty);
    try std.testing.expectEqual(Curve.P256, key.P256.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", &key.P256.x);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", &key.P256.y);
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

    const kp1 = EcdsaP256Sha256.KeyPair.generate();

    // Create a signature via cose key struct
    var cosep256 = Key.fromP256PrivPub(.Es256, kp1.secret_key, kp1.public_key);
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
    var kp2 = try Key.es256(null);

    // Trying to verfiy the first signature using the new key-pair should fail
    try std.testing.expectEqual(false, try kp2.verify(sig_der_1, &.{msg}));
}

test "copy secure #1" {
    const kp1 = EcdsaP256Sha256.KeyPair.generate();
    var cosep256 = Key.fromP256PrivPub(.Es256, kp1.secret_key, kp1.public_key);
    const cpy = cosep256.copySecure();
    try std.testing.expectEqual(cpy.P256.d, null);
}
