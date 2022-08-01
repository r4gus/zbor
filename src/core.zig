const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CborError = error{
    /// Values are reserved for future additions to the CBOR format.
    /// In the present version of CBOR, the encoded item is not well-formed.
    ReservedAdditionalInformation,
    /// Simple values 24..31 currently reserved.
    ReservedSimpleValue,
    /// The encoder doesn't support indefinite-length items.
    IndefiniteLength,
    /// The given CBOR string is malformed.
    Malformed,
    /// A unsupported type has been encounterd.
    Unassigned,
    OutOfMemory,
};

/// A (key, value) pair used with DataItem.map (major type 5).
pub const Pair = struct {
    key: DataItem,
    value: DataItem,

    /// Create data item pair.
    pub fn new(k: DataItem, v: DataItem) @This() {
        return Pair{ .key = k, .value = v };
    }
};

/// A DataItem that is tagged by a number (major type 6).
pub const Tag = struct {
    number: u64,
    content: *DataItem,

    /// Returns true if the tagged data item is a unsigned bignum (tag = 2, type = byte string).
    pub fn isUnsignedBignum(self: *const @This()) bool {
        return self.number == 2 and @as(DataItemTag, self.content.*) == .bytes;
    }

    /// Returns true if the tagged data item is a signed bignum (tag = 3, type = byte string).
    pub fn isSignedBignum(self: *const @This()) bool {
        return self.number == 3 and @as(DataItemTag, self.content.*) == .bytes;
    }

    pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, out_stream: anytype) @TypeOf(out_stream).Error!void {
        _ = options;

        if ((value.number == 2 or value.number == 3 or value.number == 21) and
            @as(DataItemTag, value.content.*) == .bytes)
        {
            // A bignum is represented by encoding its byte string in base64url
            // without padding and becomes a JSON string.
            const i: usize = if (value.isSignedBignum()) 1 else 0;
            var base64url = std.base64.url_safe_no_pad;

            var buffer = try out_stream.context.allocator.alloc(u8, base64url.Encoder.calcSize(value.content.bytes.len) + i);
            defer out_stream.context.allocator.free(buffer);

            // For tag number 3 (signed bignum) a '~' (ASCII tilde) is inserted
            // before the base-encoded value.
            if (value.isSignedBignum()) {
                buffer[0] = '~';
            }
            _ = base64url.Encoder.encode(buffer[i..], value.content.bytes);
            try std.json.stringify(buffer, .{}, out_stream);
        } else if (value.number == 22 and @as(DataItemTag, value.content.*) == .bytes) {
            // A byte string is represented by encoding it in base64.
            var base64 = std.base64.standard;

            var buffer = try out_stream.context.allocator.alloc(u8, base64.Encoder.calcSize(value.content.bytes.len));
            defer out_stream.context.allocator.free(buffer);

            _ = base64.Encoder.encode(buffer, value.content.bytes);
            try std.json.stringify(buffer, .{}, out_stream);
        } else if (value.number == 23 and @as(DataItemTag, value.content.*) == .bytes) {
            // Base16 encoding
            try out_stream.print("\"{s}\"", .{std.fmt.fmtSliceHexUpper(value.content.bytes)});
        } else {
            // For all other tags, the tag content is represented as a JSON value;
            // the tag number is ignored;
            try std.json.stringify(value.content, .{}, out_stream);
        }
    }
};

/// Tag for a 16-, 32- or 64-bit floating point value.
pub const FloatTag = enum { float16, float32, float64 };

/// A 16-, 32- or 64-bit floating point value (major type 7).
pub const Float = union(FloatTag) {
    /// IEEE 754 Half-Precision Float (16 bits follow)
    float16: f16,
    /// IEEE 754 Single-Precision Float (32 bits follow)
    float32: f32,
    /// IEEE 754 Double-Precision Float (64 bits follow)
    float64: f64,
};

/// A simple value (major type 7).
pub const SimpleValue = enum(u8) { False = 20, True = 21, Null = 22, Undefined = 23 };

/// Tag for a data item type.
pub const DataItemTag = enum { int, bytes, text, array, map, tag, float, simple };

/// A single piece of CBOR data.
///
/// The structure of a DataItem may contain zero, one, or more nested DataItems.
pub const DataItem = union(DataItemTag) {
    /// Major type 0 and 1: An integer in the range -2^64..2^64-1
    int: i128,
    /// Major type 2: A byte string.
    bytes: []u8,
    /// Major type 3: A text string encoded as utf-8.
    text: []u8,
    /// Major type 4: An array of data items.
    array: []DataItem,
    /// Major type 5: A map of pairs of data items.
    map: []Pair,
    /// Major type 6: A tagged data item.
    tag: Tag,
    /// Major type 7: IEEE 754 Half-, Single-, or Double-Precision float.
    float: Float,
    /// Major type 7: Simple value [false, true, null]
    simple: SimpleValue,

    /// Create a new data item of type int.
    pub fn int(value: i128) @This() {
        return DataItem{ .int = value };
    }

    /// Create a new data item of type byte string.
    pub fn bytes(allocator: Allocator, value: []const u8) CborError!@This() {
        var di = DataItem{ .bytes = try allocator.alloc(u8, value.len) };
        std.mem.copy(u8, di.bytes, value);
        return di;
    }

    /// Create a new data item of type text string.
    pub fn text(allocator: Allocator, value: []const u8) CborError!@This() {
        var di = DataItem{ .text = try allocator.alloc(u8, value.len) };
        std.mem.copy(u8, di.text, value);
        return di;
    }

    /// Create a new data item of type array.
    pub fn array(allocator: Allocator, value: []const DataItem) CborError!@This() {
        var di = DataItem{ .array = try allocator.alloc(DataItem, value.len) };
        std.mem.copy(DataItem, di.array, value);
        return di;
    }

    /// Create a new data item of type map.
    pub fn map(allocator: Allocator, value: []const Pair) CborError!@This() {
        var di = DataItem{ .map = try allocator.alloc(Pair, value.len) };
        std.mem.copy(Pair, di.map, value);
        return di;
    }

    /// Create a new tagged data item.
    pub fn tagged(allocator: Allocator, tag: u64, value: DataItem) CborError!@This() {
        var di = DataItem{ .tag = Tag{ .number = tag, .content = try allocator.create(DataItem) } };
        di.tag.content.* = value;
        return di;
    }

    /// Create the simple value True.
    pub fn True() @This() {
        return DataItem{ .simple = SimpleValue.True };
    }

    /// Create the simple value False.
    pub fn False() @This() {
        return DataItem{ .simple = SimpleValue.False };
    }

    /// Create the simple value Null.
    pub fn Null() @This() {
        return DataItem{ .simple = SimpleValue.Null };
    }

    /// Create the simple value Undefined.
    pub fn Undefined() @This() {
        return DataItem{ .simple = SimpleValue.Undefined };
    }

    /// Create a IEEE 754 half-precision floating point value.
    pub fn float16(v: f16) @This() {
        return DataItem{ .float = Float{ .float16 = v } };
    }

    /// Create a IEEE 754 single-precision floating point value.
    pub fn float32(v: f32) @This() {
        return DataItem{ .float = Float{ .float32 = v } };
    }

    /// Create a IEEE 754 double-precision floating point value.
    pub fn float64(v: f64) @This() {
        return DataItem{ .float = Float{ .float64 = v } };
    }

    /// Create a unsigned bignum (tag = 2, type = byte string).
    /// The bignum is represented in network byte order (big endian, i.e. the
    /// lowest memory address holds the most significant byte).
    pub fn unsignedBignum(allocator: Allocator, value: []const u8) CborError!@This() {
        return try DataItem.tagged(allocator, 2, try DataItem.bytes(allocator, value));
    }

    /// Create a signed bignum (tag = 3, type = byte string).
    /// The bignum is represented in network byte order (big endian, i.e. the
    /// lowest memory address holds the most significant byte).
    pub fn signedBignum(allocator: Allocator, value: []const u8) CborError!@This() {
        return try DataItem.tagged(allocator, 3, try DataItem.bytes(allocator, value));
    }

    /// Recursively free all allocated memory.
    /// The given allocator must be the one used for creating the DataItem and
    /// its children.
    pub fn deinit(self: @This(), allocator: Allocator) void {
        switch (self) {
            .int, .float, .simple => {},
            .bytes => |list| allocator.free(list),
            .text => |list| allocator.free(list),
            .array => |arr| {
                // We must deinitialize each item of the given array...
                for (arr) |item| {
                    item.deinit(allocator);
                }
                // ...before deinitializing the ArrayList itself.
                allocator.free(arr);
            },
            .map => |m| {
                for (m) |item| {
                    item.key.deinit(allocator);
                    item.value.deinit(allocator);
                }
                allocator.free(m);
            },
            .tag => |t| {
                // First free the allocated memory of the nested data items...
                t.content.*.deinit(allocator);
                // ...then free the memory of the content.
                allocator.destroy(t.content);
            },
        }
    }

    /// Returns true if the given DataItem is an integer, false otherwise.
    pub fn isInt(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .int;
    }

    /// Returns true if the given DataItem is a byte string, false otherwise.
    pub fn isBytes(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .bytes;
    }

    /// Returns true if the given DataItem is a text string, false otherwise.
    pub fn isText(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .text;
    }

    /// Returns true if the given DataItem is an array of DataItems, false otherwise.
    pub fn isArray(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .array;
    }

    /// Returns true if the given DataItem is a map, false otherwise.
    pub fn isMap(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .map;
    }

    /// Returns true if the given DataItem is a tagged DataItem, false otherwise.
    pub fn isTagged(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .tag;
    }

    /// Returns true if the given DataItem is a float, false otherwise.
    pub fn isFloat(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .float;
    }

    /// Returns true if the given DataItem is a simple value, false otherwise.
    pub fn isSimple(self: *const @This()) bool {
        return @as(DataItemTag, self.*) == .simple;
    }

    /// Get the value at the specified index from an array.
    ///
    /// Returns null if the DataItem is not an array or if the
    /// given index is out of bounds.
    pub fn get(self: *@This(), index: usize) ?*DataItem {
        if (@as(DataItemTag, self.*) != DataItemTag.array) {
            return null;
        }

        if (index < self.array.len) {
            return &self.array[index];
        } else {
            return null;
        }
    }

    /// Get the value associated with the given key from a map.
    ///
    /// Retruns null if the DataItem is not a map or if the key couldn't
    /// be found; a pointer to the associated value otherwise.
    pub fn getValue(self: *@This(), key: *const DataItem) ?*DataItem {
        if (@as(DataItemTag, self.*) != DataItemTag.map) {
            return null;
        }

        for (self.map) |*pair| {
            if (@as(DataItemTag, pair.*.key) == @as(DataItemTag, key.*)) {
                if (pair.*.key.equal(key)) {
                    return &pair.*.value;
                }
            }
        }

        return null;
    }

    /// Get the value associated with the given key from a map.
    ///
    /// Retruns null if the DataItem is not a map or if the key couldn't
    /// be found; a pointer to the associated value otherwise.
    pub fn getValueByString(self: *@This(), key: []const u8) ?*DataItem {
        if (@as(DataItemTag, self.*) != DataItemTag.map) {
            return null;
        }

        for (self.map) |*pair| {
            if (@as(DataItemTag, pair.*.key) == .text) {
                if (std.mem.eql(u8, pair.*.key.text, key)) {
                    return &pair.*.value;
                }
            }
        }

        return null;
    }

    /// Compare two DataItems for equality.
    pub fn equal(self: *const @This(), other: *const @This()) bool {
        // self and other hold different types, i.e. can't be equal.
        if (@as(DataItemTag, self.*) != @as(DataItemTag, other.*)) {
            return false;
        }

        switch (self.*) {
            .int => |value| return value == other.*.int,
            .bytes => |list| return std.mem.eql(u8, list, other.*.bytes),
            .text => |list| return std.mem.eql(u8, list, other.*.text),
            .array => |arr| {
                if (arr.len != other.*.array.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < arr.len) : (i += 1) {
                    if (!arr[i].equal(&other.*.array[i])) {
                        return false;
                    }
                }

                return true;
            },
            .map => |m| {
                if (m.len != other.*.map.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < m.len) : (i += 1) {
                    if (!m[i].key.equal(&other.*.map[i].key) or
                        !m[i].value.equal(&other.*.map[i].value))
                    {
                        return false;
                    }
                }

                return true;
            },
            .tag => |t| {
                return t.number == other.tag.number and
                    t.content.*.equal(other.tag.content);
            },
            .float => |f| {
                if (@as(FloatTag, f) != @as(FloatTag, other.float)) {
                    return false;
                }

                switch (f) {
                    .float16 => |fv| return fv == other.float.float16,
                    .float32 => |fv| return fv == other.float.float32,
                    .float64 => |fv| return fv == other.float.float64,
                }
            },
            .simple => |s| {
                return s == other.simple;
            },
        }
    }

    pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, out_stream: anytype) @TypeOf(out_stream).Error!void {
        _ = options;

        switch (value) {
            // An integer (major type 0 or 1) becomes a JSON number.
            .int => |v| try out_stream.print("{d}", .{v}),
            // A byte string is encoded in base64url without padding and
            // becomes a JSON string.
            .bytes => |v| {
                var base64url = std.base64.url_safe_no_pad;
                var buffer = try out_stream.context.allocator.alloc(u8, base64url.Encoder.calcSize(v.len));
                defer out_stream.context.allocator.free(buffer);
                _ = base64url.Encoder.encode(buffer, v);
                try std.json.stringify(buffer, .{}, out_stream);
            },
            .text => |v| {
                // TODO: Certain UTF-8 characters must be escaped.
                // see: https://www.rfc-editor.org/rfc/rfc8259#section-7
                try std.json.stringify(v, .{}, out_stream);
            },
            // An array becomes a JSON array.
            .array => |v| {
                try std.json.stringify(v, .{ .string = .Array }, out_stream);
            },
            // A map becomes a JSON object. This is possible directly only if all
            // keys are UTF-8 strings.
            .map => |v| {
                try out_stream.writeAll("{");
                for (v) |pair, index| {
                    // Just ignore all pairs where the key is not a text string.
                    if (pair.key.isText()) {
                        try std.json.stringify(pair.key, .{}, out_stream);
                        try out_stream.writeAll(":");
                        try std.json.stringify(pair.value, .{}, out_stream);

                        if (index < v.len - 1) {
                            // stupid comma
                            try out_stream.writeAll(",");
                        }
                    }
                }
                try out_stream.writeAll("}");
            },
            .tag => |v| try std.json.stringify(v, .{}, out_stream),
            // A float becomes a JSON number if its finite.
            .float => |v| {
                switch (v) {
                    .float16 => |f| try std.json.stringify(f, .{}, out_stream),
                    .float32 => |f| try std.json.stringify(f, .{}, out_stream),
                    .float64 => |f| try std.json.stringify(f, .{}, out_stream),
                }
            },
            .simple => |v| {
                switch (v) {
                    .False => try out_stream.writeAll("false"),
                    .True => try out_stream.writeAll("true"),
                    .Null => try out_stream.writeAll("null"),
                    // Any other simple value is represented by the
                    // substitue value.
                    else => try out_stream.writeAll("null"),
                }
            },
        }
    }

    /// Convert the given DataItem to JSON.
    pub fn toJson(self: *const @This(), allocator: Allocator) !std.ArrayList(u8) {
        var json = std.ArrayList(u8).init(allocator);
        try std.json.stringify(self, .{}, json.writer());
        return json;
    }
};

pub fn pair_asc(context: void, lhs: Pair, rhs: Pair) bool {
    _ = context;
    return data_item_asc({}, lhs.key, rhs.key);
}

/// Comparator function for a DataItem, e.g. `sort(DataItem, slice, {}, data_item_asc)`.
///
/// This function aims to represent the CTAP2 canonical CBOR sorting rules
/// for keys (see: https://fidoalliance.org/specs/fido-v2.0-ps-20190130/
/// fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-
/// canonical-cbor-encoding-form).
///
/// - If the major types are different, the one with the lower value in
///   numerical order sorts earlier.
/// - If two keys have different lengths, the shorter one sorts earlier;
/// - If two keys have the same length, the one with the lower value in
///   (byte-wise) lexical order sorts earlier.
///
/// Length and value are only taken into account for integers, strings and
/// simple values. Always returns true if lhs and rhs have the same major
/// type between 4 and 6.
pub fn data_item_asc(context: void, lhs: DataItem, rhs: DataItem) bool {
    _ = context;

    // If the major types are different, the one with the lower value in
    // numerical order sorts earlier.
    switch (lhs) {
        .int => |v1| {
            switch (rhs) {
                .int => |v2| {
                    if (v1 < 0 and v2 >= 0) {
                        // mt1 > mt0
                        return false;
                    } else if (v1 >= 0 and v2 < 0) {
                        // mt0 < mt1
                        return true;
                    } else {
                        // both mt0 or mt1. The one with the lower value
                        // sorts earlier.
                        return v1 < v2;
                    }
                },
                else => return true,
            }
        },
        .bytes => |v1| {
            switch (rhs) {
                // mt0/1 < mt2
                .int => |_| return false,
                .bytes => |v2| {
                    // If two keys have different lengths, the shorter one
                    // sorts earlier.
                    if (v1.len < v2.len) {
                        return true;
                    } else if (v1.len > v2.len) {
                        return false;
                    } else {
                        // if two keys have the same lengt, the one with the
                        // lower value in (byte-wise) lexical order sorts earlier.
                        return std.mem.lessThan(u8, v1, v2);
                    }
                },
                else => return true,
            }
        },
        .text => |v1| {
            switch (rhs) {
                .int, .bytes => return false,
                .text => |v2| {
                    // If two keys have different lengths, the shorter one
                    // sorts earlier.
                    if (v1.len < v2.len) {
                        return true;
                    } else if (v1.len > v2.len) {
                        return false;
                    } else {
                        // if two keys have the same lengt, the one with the
                        // lower value in (byte-wise) lexical order sorts earlier.
                        return std.mem.lessThan(u8, v1, v2);
                    }
                },
                else => return true,
            }
        },
        .array => |_| {
            switch (rhs) {
                .int, .bytes, .text => return false,
                else => return true,
            }
        },
        .map => |_| {
            switch (rhs) {
                .int, .bytes, .text, .array => return false,
                else => return true,
            }
        },
        .tag => |_| {
            switch (rhs) {
                .int, .bytes, .text, .array, .map => return false,
                else => return true,
            }
        },
        .float => |v1| {
            switch (rhs) {
                .int, .bytes, .text, .array, .map, .tag => return false,
                .float => |v2| {
                    switch (v1) {
                        .float16 => |f1| {
                            switch (v2) {
                                .float16 => |f2| return f1 < f2,
                                else => return false,
                            }
                        },
                        .float32 => |f1| {
                            switch (v2) {
                                .float16 => return true,
                                .float32 => |f2| return f1 < f2,
                                else => return false,
                            }
                        },
                        .float64 => |f1| {
                            switch (v2) {
                                .float16, .float32 => return true,
                                .float64 => |f2| return f1 < f2,
                            }
                        },
                    }
                },
                else => return true,
            }
        },
        .simple => |v1| {
            switch (rhs) {
                .int, .bytes, .text, .array, .map, .tag => return false,
                .simple => |v2| return @enumToInt(v1) < @enumToInt(v2),
                .float => |_| return true,
            }
        },
    }
}
