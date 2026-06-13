//! This container defines a set of common COSE header parameters
//!
//! https://datatracker.ietf.org/doc/html/rfc8152#section-3

const std = @import("std");
const cbor = @import("../cbor.zig");
const cose = @import("../cose.zig");
const parse_ = @import("../parse.zig");
const Options = parse_.Options;
const stringify = parse_.stringify;
const parse = parse_.parse;

/// This parameter is used to indicate the algorithm used for the
/// security processing.  This parameter MUST be authenticated where
/// the ability to do so exists. This support is provided by AEAD
/// algorithms or construction (COSE_Sign, COSE_Sign0, COSE_Mac, and
/// COSE_Mac0).  This authentication can be done either by placing the
/// header in the protected header bucket or as part of the externally
/// supplied data.  The value is taken from the "COSE Algorithms"
alg: ?cose.Algorithm = null,
///This parameter identifies one piece of data that can be used as
///input to find the needed cryptographic key.  The value of this
///parameter can be matched against the 'kid' member in a COSE_Key
///structure.  Other methods of key distribution can define an
///equivalent field to be matched.  Applications MUST NOT assume that
///'kid' values are unique.  There may be more than one key with the
///same 'kid' value, so all of the keys associated with this 'kid'
///may need to be checked.  The internal structure of 'kid' values is
///not defined and cannot be relied on by applications.  Key
///identifier values are hints about which key to use.  This is not a
///security-critical field.  For this reason, it can be placed in the
///unprotected headers bucket.
kid: ?[]const u8 = null,
/// This parameter holds the Initialization Vector (IV) value.  For
/// some symmetric encryption algorithms, this may be referred to as a
/// nonce.  The IV can be placed in the unprotected header as
/// modifying the IV will cause the decryption to yield plaintext that
/// is readily detectable as garbled.
iv: ?[]const u8 = null,

pub fn cborStringify(self: *const @This(), options: Options, out: anytype) !void {
    _ = options;
    return stringify(self, .{
        .ignore_override = true,
        .field_settings = &.{
            .{
                .name = "alg",
                .field_options = .{
                    .alias = "1",
                    .serialization_type = .Integer,
                },
                .value_options = .{ .enum_serialization_type = .Integer },
            },
            .{ .name = "kid", .field_options = .{
                .alias = "4",
                .serialization_type = .Integer,
            } },
            .{ .name = "iv", .field_options = .{
                .alias = "5",
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
                .name = "alg",
                .field_options = .{
                    .alias = "1",
                    .serialization_type = .Integer,
                },
                .value_options = .{ .enum_serialization_type = .Integer },
            },
            .{ .name = "kid", .field_options = .{
                .alias = "4",
                .serialization_type = .Integer,
            } },
            .{ .name = "iv", .field_options = .{
                .alias = "5",
                .serialization_type = .Integer,
            } },
        },
    });
}
