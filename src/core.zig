const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CborError = error{
    // Indicates that one of the reserved values 28, 29 or 30 has been used.
    ReservedAdditionalInformation,
    // The given CBOR string is malformed.
    Malformed,
    // A unsupported type has been encounterd.
    Unsupported,
    OutOfMemory,
};

/// A (key, value) pair used with DataItem.map (major type 5).
pub const Pair = struct { key: DataItem, value: DataItem };

/// A DataItem that is tagged by a number (major type 6).
pub const Tag = struct { number: u64, content: *DataItem, allocator: Allocator };

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
    bytes: std.ArrayList(u8),
    /// Major type 3: A text string encoded as utf-8.
    text: std.ArrayList(u8),
    /// Major type 4: An array of data items.
    array: std.ArrayList(DataItem),
    /// Major type 5: A map of pairs of data items.
    map: std.ArrayList(Pair),
    /// Major type 6: A tagged data item.
    tag: Tag,
    /// Major type 7: IEEE 754 Half-, Single-, or Double-Precision float.
    float: Float,
    /// Major type 7: Simple value [false, true, null]
    simple: SimpleValue,

    pub fn bytes(allocator: Allocator, value: []const u8) CborError!@This() {
        var di = DataItem{ .bytes = std.ArrayList(u8).init(allocator) };
        try di.bytes.appendSlice(value);
        return di;
    }

    pub fn deinit(self: @This()) void {
        switch (self) {
            .int => |_| {},
            .bytes => |list| list.deinit(),
            .text => |list| list.deinit(),
            .array => |arr| {
                // We must deinitialize each item of the given array...
                for (arr.items) |item| {
                    item.deinit();
                }
                // ...before deinitializing the ArrayList itself.
                arr.deinit();
            },
            .map => |m| {
                for (m.items) |item| {
                    item.key.deinit();
                    item.value.deinit();
                }
                m.deinit();
            },
            .tag => |t| {
                // First free the allocated memory of the nested data items...
                t.content.*.deinit();
                // ...then free the memory of the content.
                t.allocator.destroy(t.content);
            },
            .float => |_| {},
            .simple => |_| {},
        }
    }

    pub fn equal(self: *const @This(), other: *const @This()) bool {
        // self and other hold different types, i.e. can't be equal.
        if (@as(DataItemTag, self.*) != @as(DataItemTag, other.*)) {
            return false;
        }

        switch (self.*) {
            .int => |value| return value == other.*.int,
            .bytes => |list| return std.mem.eql(u8, list.items, other.*.bytes.items),
            .text => |list| return std.mem.eql(u8, list.items, other.*.text.items),
            .array => |arr| {
                if (arr.items.len != other.*.array.items.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < arr.items.len) : (i += 1) {
                    if (!arr.items[i].equal(&other.*.array.items[i])) {
                        return false;
                    }
                }

                return true;
            },
            .map => |m| {
                if (m.items.len != other.*.map.items.len) {
                    return false;
                }

                var i: usize = 0;
                while (i < m.items.len) : (i += 1) {
                    if (!m.items[i].key.equal(&other.*.map.items[i].key) or
                        !m.items[i].value.equal(&other.*.map.items[i].value))
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

    /// Get the value at the specified index from an array.
    ///
    /// Returns null if the DataItem is not an array or if the
    /// given index is out of bounds.
    pub fn get(self: *@This(), index: usize) ?*DataItem {
        if (@as(DataItemTag, self.*) != DataItemTag.array) {
            return null;
        }

        if (index < self.array.items.len) {
            return &self.array.items[index];
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

        for (self.map.items) |*pair| {
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

        for (self.map.items) |*pair| {
            if (@as(DataItemTag, pair.*.key) == .text) {
                if (std.mem.eql(u8, pair.*.key.text.items, key)) {
                    return &pair.*.value;
                }
            }
        }

        return null;
    }

    /// Returns true if the given DataItem is an integer, false otherwise.
    pub fn isInt(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .int;
    }

    /// Returns true if the given DataItem is a byte string, false otherwise.
    pub fn isBytes(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .bytes;
    }

    /// Returns true if the given DataItem is a text string, false otherwise.
    pub fn isText(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .text;
    }

    /// Returns true if the given DataItem is an array of DataItems, false otherwise.
    pub fn isArray(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .array;
    }

    /// Returns true if the given DataItem is a map, false otherwise.
    pub fn isMap(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .map;
    }

    /// Returns true if the given DataItem is a tagged DataItem, false otherwise.
    pub fn isTagged(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .tag;
    }

    /// Returns true if the given DataItem is a float, false otherwise.
    pub fn isFloat(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .float;
    }

    /// Returns true if the given DataItem is a simple value, false otherwise.
    pub fn isSimple(self: *@This()) bool {
        return @as(DataItemTag, self.*) == .simple;
    }

    pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, out_stream: anytype) @TypeOf(out_stream).Error!void {
        _ = options;

        switch (value) {
            // An integer (major type 0 or 1) becomes a JSON number.
            .int => |v| try out_stream.print("{d}", .{v}),
            // A byte string is encoded in base64url without padding and
            // becomes a JSON string.
            .bytes => |v| {
                _ = v;
                var base64url = std.base64.url_safe_no_pad;
                var buffer = try v.allocator.alloc(u8, base64url.Encoder.calcSize(v.items.len));
                defer v.allocator.free(buffer);
                _ = base64url.Encoder.encode(buffer, v.items);
                try std.json.stringify(buffer, .{}, out_stream);
            },
            else => unreachable,
        }
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
                    if (v1.items.len < v2.items.len) {
                        return true;
                    } else if (v1.items.len > v2.items.len) {
                        return false;
                    } else {
                        // if two keys have the same lengt, the one with the
                        // lower value in (byte-wise) lexical order sorts earlier.
                        return std.mem.lessThan(u8, v1.items, v2.items);
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
                    if (v1.items.len < v2.items.len) {
                        return true;
                    } else if (v1.items.len > v2.items.len) {
                        return false;
                    } else {
                        // if two keys have the same lengt, the one with the
                        // lower value in (byte-wise) lexical order sorts earlier.
                        return std.mem.lessThan(u8, v1.items, v2.items);
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
