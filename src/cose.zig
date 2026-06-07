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

    pub fn getPrivKey(self: *const @This()) ?[]const u8 {
        return switch (self.kty) {
            .Ec2 => self.d,
            .AKP => self.priv,
            else => null, // TODO
        };
    }

    pub fn generateDeterministic(
        alg: Algorithm,
        seed: []const u8,
        allocator: std.mem.Allocator,
    ) !@This() {
        return switch (alg) {
            .Es256 => blk: {
                if (seed.len != EcdsaP256Sha256.KeyPair.seed_length) return error.InvalidSeedLength;
                const kp = try EcdsaP256Sha256.KeyPair.generateDeterministic(seed[0..EcdsaP256Sha256.KeyPair.seed_length].*);
                const sec1 = kp.public_key.toUncompressedSec1();
                const pk = kp.secret_key.toBytes();
                break :blk .{
                    .kty = .Ec2,
                    .alg = .Es256,
                    .crv = .P256,
                    .x = try allocator.dupe(u8, sec1[1..33]),
                    .y = try allocator.dupe(u8, sec1[33..65]),
                    .d = try allocator.dupe(u8, &pk),
                };
            },
            .@"ML-DSA-87" => blk: {
                const e = std.crypto.sign.mldsa.MLDSA87;

                if (seed.len != e.KeyPair.seed_length) return error.InvalidSeedLength;

                // The generate() function in std calls it the same, i.e.
                // unreachable is fine.
                const kp = e.KeyPair.generateDeterministic(seed[0..e.KeyPair.seed_length].*) catch unreachable;
                break :blk .{
                    .kty = .AKP,
                    .alg = alg,
                    .@"pub" = try allocator.dupe(u8, &kp.public_key.toBytes()),
                    .priv = try allocator.dupe(u8, seed),
                };
            },
            .@"ML-DSA-65" => blk: {
                const e = std.crypto.sign.mldsa.MLDSA65;

                if (seed.len != e.KeyPair.seed_length) return error.InvalidSeedLength;

                // The generate() function in std calls it the same, i.e.
                // unreachable is fine.
                const kp = e.KeyPair.generateDeterministic(seed[0..e.KeyPair.seed_length].*) catch unreachable;

                break :blk .{
                    .kty = .AKP,
                    .alg = alg,
                    .@"pub" = try allocator.dupe(u8, &kp.public_key.toBytes()),
                    .priv = try allocator.dupe(u8, seed),
                };
            },
            .@"ML-DSA-44" => blk: {
                const e = std.crypto.sign.mldsa.MLDSA44;

                if (seed.len != e.KeyPair.seed_length) return error.InvalidSeedLength;

                // The generate() function in std calls it the same, i.e.
                // unreachable is fine.
                const kp = e.KeyPair.generateDeterministic(seed[0..e.KeyPair.seed_length].*) catch unreachable;

                break :blk .{
                    .kty = .AKP,
                    .alg = alg,
                    .@"pub" = try allocator.dupe(u8, &kp.public_key.toBytes()),
                    .priv = try allocator.dupe(u8, seed),
                };
            },
            else => error.UnsupportedAlgorithm,
        };
    }

    pub fn generate(
        alg: Algorithm,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) !@This() {
        return switch (alg) {
            .Es256 => blk: {
                var random_seed: [EcdsaP256Sha256.KeyPair.seed_length]u8 = undefined;
                while (true) {
                    io.random(&random_seed);
                    break :blk generateDeterministic(
                        alg,
                        &random_seed,
                        allocator,
                    ) catch |e| {
                        if (e == error.IdentityElement) {
                            @branchHint(.unlikely);
                            continue;
                        } else return e;
                    };
                }
            },
            .@"ML-DSA-87", .@"ML-DSA-65", .@"ML-DSA-44" => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try generateDeterministic(
                    alg,
                    &seed,
                    allocator,
                );
            },
            else => error.UnsupportedAlgorithm,
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
            .@"ML-DSA-87" => {
                const e = std.crypto.sign.mldsa.MLDSA87;

                if (self.priv == null) return error.MissingPrivateKey;

                var kp = try e.KeyPair.generateDeterministic(self.priv.?[0..32].*);
                var signer = try kp.signer(null);

                for (data_seq) |data| {
                    signer.update(data);
                }

                const sig = signer.finalize();
                return try allocator.dupe(u8, &sig.toBytes());
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
            },
            .@"ML-DSA-87" => {
                const e = std.crypto.sign.mldsa.MLDSA87;

                if (self.@"pub" == null) return error.MissingPub;
                if (signature.len != e.Signature.encoded_length) return error.WrongSignatureLength;

                const k = try e.PublicKey.fromBytes(self.@"pub".?[0..e.PublicKey.encoded_length].*);

                const sig = try e.Signature.fromBytes(signature[0..e.Signature.encoded_length].*);

                var verifier = try sig.verifier(k);
                for (data_seq) |data| {
                    verifier.update(data);
                }

                verifier.verify() catch {
                    return false;
                };
            },
            else => return error.UnsupportedAlgorithm,
        }

        return true;
    }

    /// TDOO: this is experimental!
    /// use it with extreme care!!!
    fn is_valid_key(
        ctx: *const anyopaque,
        key: []const u8,
        fields: []const bool,
        seen: *const fn ([]const u8, []const bool) bool,
    ) bool {
        // TODO: what is a sane default here?
        // Returning true at this point is probably the only
        // sane solution we have...
        if (!seen("kty", fields)) return true;

        const self: *const @This() = @ptrCast(@alignCast(ctx));

        if (std.mem.eql(u8, key, "crv") or std.mem.eql(u8, key, "x") or std.mem.eql(u8, key, "y") or std.mem.eql(u8, key, "d")) {
            return self.kty == .Ec2;
        } else if (std.mem.eql(u8, key, "pub") or std.mem.eql(u8, key, "priv")) {
            return self.kty == .AKP;
        } else {
            return true;
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
            .is_valid_key = &is_valid_key,
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
    var kp2 = try Key.generate(.Es256, std.testing.allocator, std.testing.io);
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
    const kp = try Key.generate(
        .@"ML-DSA-87",
        std.testing.allocator,
        std.testing.io,
    );
    defer kp.deinit(std.testing.allocator);

    const sig = try kp.sign(&.{"zig is awesome!"}, std.testing.allocator);
    defer std.testing.allocator.free(sig);

    try std.testing.expectEqual(true, try kp.verify(sig, &.{"zig is awesome!"}));
    try std.testing.expectEqual(false, try kp.verify(sig, &.{"zig is awesom!"}));
}

test "ML-DSA-87 #2" {
    const allocator = std.testing.allocator;
    const expected = "\xa4\x01\x07\x03\x38\x31\x20\x59\x0a\x20\x14\x10\x2e\x98\x6b\xb1\x3e\x4d\xa0\x22\x6a\xc1\x4f\x32\x2d\x74\xe4\xed\x56\xe9\x9d\xeb\x36\x5d\x9a\x25\x04\x6e\xfa\xdd\x2d\xfb\x87\x72\x89\xd9\x0f\x36\xbd\xb4\x02\x4c\xde\xb0\xfc\x64\xca\xff\xa6\x6b\x51\x50\xf4\x58\xdc\xaa\x9a\xcc\x7b\xc5\xa3\xd8\x20\x5a\xee\xa5\x7d\xe7\xbb\x51\xee\x23\x94\x3d\x3d\x98\xa3\x63\x99\x95\x76\xf2\xd0\x2f\x75\x63\x5d\x43\x39\x35\x3e\x10\x7c\xf0\x38\x6c\x7f\x67\x52\x08\x53\xe1\x6e\x3b\x12\xc2\x83\xdc\xbb\x18\xdc\xf9\x52\x0b\x4f\xff\x9e\x07\x1a\xc3\x3f\xfb\x27\xc9\x89\xd4\x95\x08\x4c\x0a\xda\xae\xc2\x51\x02\x1f\x8f\xfd\xa7\x8b\xcf\xdd\x70\xa3\xdd\x09\x6f\x25\xf7\x49\x19\x8d\x23\xf7\x08\xa7\xde\xb0\xbe\x00\x53\x0a\x9c\xee\x01\xca\x29\xc6\xb7\xd6\x15\xeb\xf7\xe2\x86\x9c\xe6\x31\xcc\x68\xc0\x4d\xe7\x93\xdf\xde\xdd\x9a\x40\x31\x48\xcc\x3a\x0a\x4c\x33\x72\xfa\x9f\xf0\xf3\xc7\x17\x8b\x9c\xce\x73\x9b\xbb\x4d\xf7\xca\x1c\x56\x07\x65\x56\x28\xd8\x55\xf1\xe2\x97\xda\xb6\x96\xa9\x8e\xa2\x75\xca\x76\xcc\xcb\x3e\xd7\xbe\x6a\x8f\xa6\xad\x91\x5b\x81\x74\x32\xe7\x11\x9d\x67\x57\x51\x04\xab\x6b\x30\x10\xd0\x4e\xf1\x9f\x3d\x8a\xaf\x3f\xea\x37\x1c\x52\xb7\x19\x55\x27\xf5\x5a\x9c\x3c\x97\x2c\x0d\xd8\x5e\xfa\xd3\xde\x4c\xd2\x47\xdf\xe9\x88\xbd\x18\x92\x2e\x38\xa6\x48\x97\x4d\xa3\x36\xc0\x2c\x4c\xd7\xd3\xe6\xa6\xd6\xf5\xcd\x42\xad\x28\x29\x60\x8c\x71\xab\x10\xc1\x94\x92\x60\xfd\xf0\xa8\x00\xc4\x0c\x84\x99\x9c\xfb\x47\xe7\x3b\xc3\x49\xa1\x84\x9a\xbe\xa7\x22\x22\xb3\x6e\x57\xb5\x90\x8a\x1d\xe9\xb6\x88\x97\x48\x52\x6c\x76\xed\x5b\x51\x89\x9d\x0e\x4c\xa3\x79\x39\x24\xde\x2c\x47\xce\x51\x3d\x37\x98\xd0\x8b\x42\x28\x31\x79\xaf\xa4\x3f\x49\x6e\xce\xa5\x81\x82\x17\xe2\x22\x28\x7c\xe9\x5c\xdd\x0b\xe2\x33\x66\x0d\xae\x61\x1d\xfb\x6f\x86\x3a\x72\x93\x75\xbc\xcb\xcf\x6d\xa9\x08\x9b\xee\x50\x84\xd8\x33\xda\xde\x52\x45\xde\x8d\x1d\xa3\x09\xb5\x8e\xd5\xa0\xa3\x07\xb5\x50\x63\x25\x84\xa9\xd1\xed\xf7\xab\x22\x5f\xfe\x8b\xd1\xbe\xba\x36\x1c\xab\x5f\xf1\xb7\x1c\xff\x03\x56\x21\x78\x37\xc3\x78\x45\x21\x55\x3c\x1f\x45\xf9\x25\xca\x54\xe0\x49\xd2\x01\x78\x32\x97\x57\x43\xcd\x8f\xf4\x02\xb8\x64\xc0\xf3\xf9\x75\x48\x63\xff\x2d\x98\x48\xb7\xd8\xe5\x15\xe0\x1a\x94\x86\x39\xa7\xa7\x68\xb4\x52\x90\x3f\xfc\x77\x9f\x33\xb2\x78\x17\x7e\xe5\x12\x82\x94\x58\x2c\x0a\x69\x63\xed\x11\x52\x81\x07\x73\xb2\x55\x1d\x9d\xc6\x11\x90\xbf\x02\xe8\x2d\x57\xdc\xd3\xab\x49\x55\x99\xb7\x9d\xe3\xd9\xa3\xa8\x47\xc1\x17\xfe\x6c\x6e\xd0\x2e\xfd\xab\xe4\x2a\x0b\x10\x08\x81\x3d\xd9\x26\xe9\x52\x5c\x18\x30\x93\x80\x77\xa0\xb8\x71\x1f\xce\xfd\x8f\x2e\x2f\x72\xbf\x4c\xe1\xe9\xd0\x19\x27\x43\x6b\x82\xd9\xef\xc5\xda\x93\x08\xd6\x14\xa8\x9d\x81\x54\xfa\xc0\x0c\xbd\xea\xdf\x0e\x0a\x65\xc7\x89\x3d\x52\xe6\x61\xf3\xcd\x0f\x65\xed\xab\xc7\x0a\x01\xed\x4f\xc9\x27\x6f\x87\x7f\x6a\x3e\x54\xd6\xdc\x96\x67\x45\xae\x90\x02\xc5\xa9\x7f\x74\x75\x63\xb6\x13\x6b\x27\xb0\x32\x4f\xda\xc2\x05\x28\xc7\xda\xd3\x1d\x70\x3b\x82\xeb\x22\x45\x41\x5b\xca\x43\xee\x6e\x53\x27\xdb\x42\xd4\x08\xf9\xe5\x38\xf5\x11\xe2\x95\xbc\xe7\xbf\x12\x4b\xd5\xce\x55\x43\x07\xa4\x47\x68\xfc\x03\x5d\x25\x4a\x6b\x1c\xcf\x0d\xf7\xf1\x89\xa4\xa6\xcc\x67\xe1\xe3\x4a\x92\x01\x08\x9f\xd5\x14\x5b\xfb\xe6\x12\xcd\xb8\xbd\x5f\x0e\x97\xf3\x8b\x11\x83\xcf\xc4\xe9\x44\xb8\x7e\x1a\x4a\xec\x8c\x44\x83\xe4\xd7\x02\xa0\x59\x79\x54\xbd\x45\xd1\x39\xaa\x93\x8b\xa7\x9e\xbc\xa5\xa5\x2f\xaf\xa5\x0e\xc8\x96\x09\x75\x4f\x14\x57\xd7\x90\xa5\xc5\x4f\x37\x8a\x2d\x04\xd2\x51\xd8\x17\xad\xd2\xe3\xd6\x27\xb6\x74\x41\x2b\x53\xa4\x35\x40\x60\xe5\x7e\xf3\x8e\xd7\xc1\x36\xd7\x80\xe5\x7f\x7f\xb3\xe4\xc2\x36\xca\x61\xb3\x93\xa5\xa0\x7d\x74\xd5\x0e\x14\x82\x18\x4d\xc0\x5b\xb2\x8c\x3d\x35\x2a\x6a\x01\xaa\x28\xfc\x8c\x64\x9b\x5c\xb5\xbe\x25\xaa\x0a\x1f\xe0\x60\x0b\x85\x05\x3a\xf4\xe2\x0b\xd1\xf1\xfc\xe6\xfd\x22\x03\x72\x96\x40\x40\x69\xe8\xa7\x3a\x00\xad\x0a\x9d\x26\xcf\x45\x6d\x31\x2b\x58\x11\x15\xb8\x68\x70\x1f\xa5\xe7\x1a\x56\x18\x3a\xf4\x94\xd1\x9c\x22\x3c\x6b\x2d\xb8\xe6\xee\xdd\x2b\xad\x82\xd0\x4f\xbb\xc9\x27\x18\xbf\x39\x53\x8a\xf9\xb0\x76\x58\x14\x09\x17\x3f\x33\xdd\xc0\x63\x6a\x06\xff\xba\xb2\xee\x76\x33\x55\xe0\x69\x9e\x18\xb6\x89\x2a\x33\xe9\x31\x03\x42\x83\x24\x4f\x86\x23\x78\xef\x29\xc3\xc8\xd3\x3d\xeb\xc8\x33\xa1\x7b\xe5\x53\x54\x10\x9b\x92\x0a\x4a\x36\xa4\x05\x00\x2a\x02\x95\x88\x56\x49\xea\xe7\xa4\x6d\xe1\x41\x08\xcf\xdb\x6b\xf1\xbf\x52\xa6\xa1\xc4\x1f\xfe\xac\xf9\x89\x01\xef\x11\x0d\x29\xe3\xb0\x40\x23\x26\xd4\xed\x53\x78\x35\x28\xc2\x62\xc2\x98\x91\xb3\x7d\x8f\x22\xb8\x44\x77\xea\x02\xc0\x87\x49\x01\xf2\xc4\x5d\x9f\x4a\x8a\xab\xf8\x24\xc0\xd2\x69\x5e\x95\x62\xcf\xa4\xfa\x2e\x8c\x3f\x45\x8e\x0e\x2f\x25\x74\xe3\x40\xb1\x1d\x02\xcb\xdc\x52\x76\x1c\xb4\x64\x28\xc1\x44\x85\x10\x4e\xc6\x9e\x8f\xe2\x40\x78\xa6\x53\xf0\x31\x0f\xe6\x0c\x3b\x2d\xa3\xf4\xb0\xba\xde\xb2\xfc\xd5\x8f\x61\xdc\x72\x53\x54\x32\x73\x91\xe7\xa4\x73\x52\x74\xa7\xde\xba\x65\xe8\x6a\x4e\x1b\x6c\x04\xbd\x76\xb3\x02\x21\x52\x6a\xb4\xd5\xe1\x73\x25\xc1\x82\xcc\xb9\x59\x43\xc5\xd7\x1a\x63\x17\x8c\xfb\x4e\xbb\x64\x98\x1a\xd1\x9d\x38\x00\x1c\xa1\x52\xbf\xd5\x86\xb6\x80\x10\xa5\x7d\x28\xb0\x5a\x41\x0e\xc4\xde\x72\xc8\x9e\x57\x31\xf7\x40\x00\xcb\x4b\x8d\x43\x9e\xd2\x9e\x3a\xa2\xaa\xb5\xf3\xd8\x00\xce\x39\x3e\xee\xa5\xb8\xcc\x1b\x18\x8b\xf5\xc0\x98\x18\x8d\x71\xf9\xfa\xd5\x73\x52\x27\x21\xeb\x67\x57\x20\x4d\x4b\xee\xdc\x74\xa5\x64\x84\x58\x80\x4c\xa8\xc7\x67\xdd\x23\xb8\x84\x99\x25\xb7\xff\x24\x1f\x48\x96\x3d\x8e\x55\xdf\x82\xcb\x3c\x5b\x66\xfa\xb5\x84\xd6\x81\xc1\xed\xa8\xd2\x84\x66\x23\xf6\xf8\x15\xab\xd9\x2d\x61\xdb\xbf\x40\x4e\xc3\x20\xc4\xac\x73\x92\xdb\xab\xa7\x68\xd5\x8f\x32\x2e\x52\xc6\xce\x22\x04\x5a\x70\x36\x14\x38\xd9\x65\xf4\x27\x06\x0a\x68\xed\x9a\x6f\xe7\x36\x4f\x38\x01\xce\x78\x1e\xf8\xbe\xc7\xda\xe4\xd6\xf5\x73\x86\x66\x82\x54\xba\xd1\xd2\xea\xeb\x8b\x38\x7f\x21\x35\xfa\x55\xd0\x06\x5f\xc4\x90\x8b\x6c\x9b\xb1\xb5\xd7\x63\xec\x6e\xcf\x83\x0d\xd0\x88\x41\x5e\x16\xd8\xfd\x1f\xdd\x24\x04\x94\x50\xf9\x7c\x6a\x0b\xda\x31\x17\xa5\x57\x06\x63\xb9\x8e\xb0\x88\xfa\x4e\x63\xbc\xa8\xd4\x7b\x52\xbe\x51\xec\x2d\x20\x65\xbd\x99\x76\xd8\x8b\x8b\xb6\x2f\x88\x68\x83\xc7\x57\x94\x54\x00\xa2\x1e\xda\x5e\xc4\x09\x81\x57\xc9\x0d\x85\x2f\x75\x85\xcb\xc9\x7e\x0a\x66\xc2\x89\xff\x4c\x1a\x3e\x3a\xfd\xd9\x66\x39\x49\xcf\xf2\xf1\x54\x58\x9e\x2b\x68\x13\x60\x98\xf0\x39\xa7\x98\xd8\xd5\x47\xa2\xb5\x64\x41\x0a\x47\x2c\x31\x6b\xd7\xb6\x82\xd2\x83\x7e\xb4\x49\x2c\xe2\x6c\xf4\x7b\xc8\xc6\xb9\x1d\x0a\xc4\xc1\xd8\x4b\x76\x58\x54\xe2\x9d\x5d\x0a\xf1\xf0\x5a\xc3\xa0\x2e\x19\x1b\xf8\x49\x45\xeb\x82\x95\x04\x25\x9b\xde\x71\xbf\xa3\x26\x64\xfc\xa8\x52\x73\xe0\xd7\x05\x90\x8b\xe5\xca\x6b\x84\x15\x34\x22\x2b\xa7\xe7\xca\x82\xf0\xfe\xf6\x85\x42\x1f\x85\xbd\xb3\x92\x73\x55\x0b\x2e\x61\xde\x55\x1d\x26\x72\xc2\x06\x47\x63\xbd\x3d\xc4\x02\xff\x5d\xb8\xbe\x8e\x49\x59\x89\x70\x4a\x4a\x7a\x7f\x03\xe8\x36\x5c\x89\xf0\x9f\x21\x2a\x7f\x0d\x86\x13\x43\x90\xa3\xf3\x76\x05\x07\x02\x9c\x7e\x8d\xfd\x5c\x07\x02\x92\xea\xf2\xa1\x26\xec\xce\x6a\x07\x7a\x09\x41\x6a\x34\x32\x5b\x5c\xe4\x1a\x67\x7b\x92\xf6\x54\x28\x59\x4a\xdc\xbc\xe6\x07\xfb\x54\x7d\xbf\x58\x32\x0f\x27\x4e\x6c\x24\xea\xf2\xc3\xa1\x2e\x60\x27\xe8\x35\x75\x38\xbc\xdf\x5a\x9e\x99\x85\x2c\xba\xdb\x05\xf5\x6d\x33\xd8\xbf\xfc\x2c\xe6\xa8\xba\x83\x83\x9d\x45\x5c\x7e\xf7\xde\x87\xcc\x01\x52\x42\x35\x1c\xa4\x82\x0d\x69\x51\xbd\x75\x9f\x9e\x4b\xea\xcf\x82\x75\xd6\x08\x95\x3b\xd9\xec\xe6\xc7\x45\xf2\xe4\x49\x69\xe8\x69\xad\xe2\x6a\x88\x2e\x34\xd5\x63\x7f\xc4\xce\x09\x49\xb8\xaa\x43\x1e\xf7\x97\xa3\xe5\xf6\x9c\x69\x32\x80\xfc\x3c\x0f\x30\x04\x57\xbe\x7d\x8f\xdb\x2f\xe4\x17\xa4\xeb\xe3\xb2\x9c\xb7\xd1\x8d\xc5\x7e\x86\x6d\x9f\x92\x8f\x11\xa4\xac\xed\x5e\xc3\xda\x8d\x51\x23\x33\x88\x2d\xbd\x7d\xba\x17\xea\xa4\x6a\x5d\x10\xbc\x1c\x61\x0c\xf2\x1b\x90\xa2\xd5\x3d\x52\xfd\x89\x94\xa9\x03\xb2\x14\xcb\x28\xe1\x3c\xf7\xc5\x0f\xf2\x8e\xe9\xe5\x28\x72\x2a\x40\xe0\x3b\x3c\x4d\x6f\x76\xc3\x7d\x33\x02\xca\xae\x4c\x15\xa8\xa4\x63\x89\xd2\x2e\xb6\x97\x13\x93\x5c\x45\xc7\xb7\xe0\xd2\x9d\xa9\x66\x71\x24\x90\xbc\x39\xf4\xec\xbc\xfb\x19\xb1\xbb\x3f\x62\xa0\x07\x1f\x57\x7d\x5d\x97\x35\x8f\x13\xa2\xe2\x87\x33\x85\xa1\xf4\xcb\x96\xa6\xab\xac\xa8\xd2\x3a\x67\x6f\x0d\x0a\xd8\xa9\xaf\xf2\x3c\xe1\x70\xb1\x53\x59\xc3\xba\xe5\xbd\x77\xa8\x04\x03\x60\x19\x6e\x20\xe4\x64\x88\x8b\x55\xb2\xac\xd9\x3c\x51\x1a\xbb\xdd\x42\x8c\x6b\x4c\xf4\x4e\x56\xb5\xbf\x30\x5e\x5d\x0a\x0d\x9e\xf4\x35\xfb\x4e\x05\x66\x42\x3f\xbc\x74\x6a\x26\xba\x4a\xbb\x20\x12\xc3\x40\x3a\x69\xc9\x5a\x36\xef\x55\x19\x50\x8d\x96\x58\x9d\x8e\xc7\x0f\x89\x66\xcd\x5a\x0a\x3c\x51\x38\x57\xa5\x12\xac\x43\x0a\x8e\xfc\x2a\x48\x01\x98\x29\xcd\x9e\x82\xf2\x34\xb4\x72\xca\x71\xc5\x53\xce\xe3\xda\x5c\xb5\xaf\x66\x9b\xde\xd1\xdd\x97\xf9\x0a\xfc\xdf\x0b\xc3\xc1\x3f\x63\x36\x58\x4e\x1d\x59\x9f\xe4\x57\x9e\x66\xff\x40\x99\x01\x6b\x76\x4e\xe0\x4c\xfe\x19\xe6\xc3\xdb\x02\xe8\xe2\x53\x59\xa9\x00\x22\xea\x64\xc1\x4b\xbf\x9e\xb3\x00\xfc\x01\xee\x93\x5a\x32\x5f\xd0\xe4\xc9\x5f\xee\x15\x46\xf2\x68\xb6\x3d\x2f\xc9\x72\x10\xdf\x7e\x62\x80\xf8\xac\x0b\x8b\x76\x87\xdf\x3d\x42\x5a\x1f\x33\x9e\x76\xee\xf7\x01\x13\x27\xd3\x33\x0a\xe2\xf7\xea\x90\x51\x57\xd7\xc6\x54\xdf\xdd\x5c\x5c\x98\x3b\xb2\xd9\xd6\x39\xff\xa7\xee\xe9\x23\x09\x97\x7d\x7e\x3a\x1d\xc0\x99\xc7\x63\x78\x67\xfb\xb1\xdf\x44\xac\x42\xb6\x15\xff\x2c\x30\x4d\x25\x7b\x16\xdc\x48\x37\x3c\xfa\x1d\xd1\x28\x34\x4a\x5b\x1b\x83\xa4\x59\xfa\x30\xcc\x15\x1d\x29\xc5\x06\xce\x67\x2e\xcc\x92\x89\xec\x0e\xc4\x66\x68\x90\xf7\xee\x21\x5b\x72\x24\x72\xae\xcb\x0b\x79\xce\x2f\x66\xdc\xdc\xa1\xef\x59\x18\x0b\xf9\xee\xdf\x11\xbc\x1a\x56\x5b\xac\x37\x87\x5b\xc5\x3c\x0b\xb6\x3f\xd5\xba\x4e\x88\x04\x1e\x9a\xdc\x0f\xbf\x12\xf8\x66\xf5\xf9\x52\x76\xc4\xd3\xb4\x26\x0e\x7b\x4a\x0d\x01\xcc\x73\x1d\x5f\x24\xd8\xbd\xdc\xa0\xaa\x5a\x9d\xc2\xe1\x7c\x79\xb3\x9e\x75\x16\x83\x52\x33\xe1\xb2\x0a\x77\xe0\x36\x06\xf4\x44\xf1\x5a\xa7\x4a\x91\xbf\x5c\x43\x82\x53\x98\x62\x06\xf2\xe7\x43\xc6\xa3\xc3\xe0\x6e\x42\xff\xc9\x21\x66\x9a\x83\xbb\x77\xfd\x9e\x15\x0e\x4b\x1d\xd1\x8d\x21\x47\x4d\xb9\x0f\x5b\x61\x0e\x9f\x4e\xd9\x08\x94\xe3\x2f\x64\xda\x23\x4f\x5a\x85\x0f\x4a\xc3\xcb\x1d\x9c\x7a\xf3\xc4\xde\x54\xf0\xd5\xf5\x6f\x1a\xfb\xc0\x4b\x8e\x9a\xeb\xcc\x16\x4d\xe2\xb8\x8e\xed\x13\x84\xcd\x31\x32\xb5\xa8\x42\x86\x64\x04\xd5\x6f\xc1\x8d\x64\x1d\x36\x77\x7f\xc5\xd0\xe3\x93\x9f\x82\x4e\x95\x5c\x69\x14\x62\x53\xec\xa0\xb8\x55\xa0\xc8\xa3\x3c\xd8\xc9\xf0\x60\xec\x9a\x8b\xfc\xe2\x24\x6f\x4e\xf2\x20\x54\x28\x24\x9c\x3f\xd1\x82\xfe\xa6\xe3\xa9\xa1\x94\x5c\x96\xe1\xbd\xe5\x21\x16\x9c\x67\xc7\xf5\xec\x15\x32\x0a\x35\x8e\x16\x68\x53\xd9\xfb\x72\x51\x43\x56\x99\xeb\xbb\xc6\x68\xfb\xf9\xaa\x5f\xde\x3e\x57\x42\x3a\x68\x6f\xb3\x21\x58\x20\xf4\xb4\x75\xb7\x9e\xba\xb8\x88\xa3\x55\x6e\x6f\xcd\x43\x69\x9f\x0e\xe9\xd1\xb5\x88\xc7\x48\x0a\x76\xb9\xca\x92\xa3\xd6\x21\xa3";

    const priv = "\xf4\xb4\x75\xb7\x9e\xba\xb8\x88\xa3\x55\x6e\x6f\xcd\x43\x69\x9f\x0e\xe9\xd1\xb5\x88\xc7\x48\x0a\x76\xb9\xca\x92\xa3\xd6\x21\xa3";

    // Create a key pair and sign a message with it
    const kp = try Key.generateDeterministic(
        .@"ML-DSA-87",
        priv,
        allocator,
    );
    defer kp.deinit(allocator);

    const sig = try kp.sign(&.{"zig is awesome!"}, allocator);
    defer allocator.free(sig);

    // Now serialize the data
    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try stringify(kp, .{}, &str.writer);

    try std.testing.expectEqualSlices(u8, expected, str.written());

    // Now deserialize the data
    const di = try DataItem.new(str.written());

    const key = try parse(Key, di, .{
        .allocator = allocator,
    });
    defer key.deinit(allocator);

    try std.testing.expectEqual(true, try key.verify(sig, &.{"zig is awesome!"}));
}
