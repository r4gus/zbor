const std = @import("std");

const Self = @This();

reader: *std.Io.Reader,
head: [9]u8,

pub const MajorType = enum(u3) {
    UInt = 0,
    Int = 1,
    ByteString = 2,
    TextString = 3,
    Array = 4,
    Map = 5,
    Tag = 6,
    Float_Simple = 7,
};

pub const Type = enum {
    /// Integer in the range -2^64..2^64 - 1 (MT 0/1)
    Int,
    /// Byte string (MT 2)
    ByteString,
    /// UTF-8 text string (MT 3)
    TextString,
    /// Array of data items (MT 4)
    Array,
    /// Indefinite array of data items (MT 4)
    ArrayIndef,
    /// Map of pairs of data items (MT 5)
    Map,
    /// Indefinite map of pairs of data items (MT 5)
    MapIndef,
    /// False (MT 7)
    False,
    /// True (MT 7)
    True,
    /// Null (MT 7)
    Null,
    /// Undefined (MT 7)
    Undefined,
    /// Simple value (MT 7)
    Simple,
    /// Tagged data item whose tag number is an integer in the range 0..2^64 - 1 (MT 6)
    Tagged,
    /// Floating point value (MT 7)
    Float,
    /// Break (MT 7)
    Break,
    /// Unknown data item
    Unknown,
};

/// Create a new CBOR data item from a reader.
///
/// This will initially only fetch the head (up to 9 bytes) and
/// more data is only read if explicitly requested.
///
/// Returns an error if the `Reader` itself throws an error or
/// if the head is malformed;
pub fn new(reader: *std.Io.Reader) !@This() {
    // Thea head contains the first byte plus up to 8 bytes of
    // numeric data (either int or float).
    var head: [9]u8 = @splat(0);
    head[0] = try reader.takeByte();

    // first get the major type (upper 3 bits) and the additional
    // information (lower 5 bits)
    const mt: u8 = head[0] >> 5;
    const ai: u5 = @intCast(head[0] & 0x1f);

    switch (ai) {
        24 => head[1] = try reader.takeByte(),
        25 => try reader.readSliceAll(head[1..3]),
        26 => try reader.readSliceAll(head[1..5]),
        27 => try reader.readSliceAll(head[1..9]),
        28...30 => return error.Malformed,
        31 => {
            switch (mt) {
                0, 1, 6 => return error.Malformed,
                else => {},
            }
        },
        else => {},
    }

    return .{
        .reader = reader,
        .head = head,
    };
}

fn next(self: @This()) !@This() {
    return try @This().new(self.reader);
}

/// Get the major type of the data item
pub fn getMajorType(self: @This()) MajorType {
    return @fromBackingInt(@as(u3, @intCast(self.head[0] >> 5)));
}

/// Get a more detailed type (compared to the major type)
/// for a data item.
pub fn getType(self: @This()) Type {
    return switch (self.head[0]) {
        0x00...0x3b => .Int,
        0x40...0x5b => .ByteString,
        0x60...0x7b => .TextString,
        0x80...0x9b => .Array,
        0x9f => .ArrayIndef,
        0xa0...0xbb => .Map,
        0xbf => .MapIndef,
        0xf4 => .False,
        0xf5 => .True,
        0xf6 => .Null,
        0xf7 => .Undefined,
        0xe0...0xf3, 0xf8 => .Simple,
        0xc0...0xdb => .Tagged,
        0xf9...0xfb => .Float,
        0xff => .Break,
        else => .Unknown,
    };
}

/// Get the additional information of the given data item
pub fn getAdditionalInformation(self: @This()) u5 {
    return @intCast(self.head[0] & 0x1f);
}

/// Get the numeric value that follows the initial byte
/// of a data item.
pub fn getArgumentValue(self: @This()) !u64 {
    const ai = self.getAdditionalInformation();

    return switch (ai) {
        0x00...0x17 => @as(u64, @intCast(ai)),
        0x18 => @as(u64, @intCast(self.head[1])),
        0x19 => @as(u64, std.mem.readInt(u16, self.head[1..3], .big)),
        0x1a => @as(u64, std.mem.readInt(u32, self.head[1..5], .big)),
        0x1b => @as(u64, std.mem.readInt(u64, self.head[1..9], .big)),
        else => error.Malformed,
    };
}

/// Extract the unsigned integer (0..2⁶⁴-1) from the given data item.
///
/// This requires a data item of major type 0 (unsigned integer).
pub fn getUInt(self: @This()) !u64 {
    if (self.getMajorType() != .UInt) return error.WrongMajorType;
    return try self.getArgumentValue();
}

/// Extract the signed integer (-2⁶⁴..-1) from the given data item.
///
/// This requires a data item of major type 0 (unsigned integer).
pub fn getInt(self: @This()) !i65 {
    return switch (self.getMajorType()) {
        .Int => -@as(i65, @intCast(try self.getArgumentValue())) - 1,
        .UInt => @as(i65, @intCast(try self.getArgumentValue())),
        else => error.WrongMajorType,
    };
}

/// Tell if the given data item is a 16-bit IEEE 754 Half-Precision float
pub fn isF16(self: @This()) bool {
    return self.head[0] == 0xf9;
}

/// Tell if the given data item is a 32-bit IEEE 754 Single-Precision float
pub fn isF32(self: @This()) bool {
    return self.head[0] == 0xfa;
}

/// Tell if the given data item is a 64-bit IEEE 754 Double-Precision float
pub fn isF64(self: @This()) bool {
    return self.head[0] == 0xfb;
}

/// Extract the 16-bit IEEE 754 Half-Precision float from the given data item.
///
/// Use `isF16()` to check if the data item has the right type. This method
/// returns an error if `isF16() == false`.
pub fn getF16(self: @This()) !f16 {
    if (!self.isF16()) return error.WrongType;
    return self.getF16_();
}

fn getF16_(self: @This()) !f16 {
    return @floatCast(@as(f16, @bitCast(@as(u16, @intCast(try self.getArgumentValue())))));
}

/// Extract the 32-bit IEEE 754 Single-Precision float from the given data item.
///
/// Use `isF32()` to check if the data item has the right type. This method
/// returns an error if `isF32() == false`.
pub fn getF32(self: @This()) !f32 {
    if (!self.isF32()) return error.WrongType;
    return self.getF32_();
}

fn getF32_(self: @This()) !f32 {
    return @floatCast(@as(f32, @bitCast(@as(u32, @intCast(try self.getArgumentValue())))));
}

/// Extract the 32-bit IEEE 754 Double-Precision float from the given data item.
///
/// Use `isF64()` to check if the data item has the right type. This method
/// returns an error if `isF64() == false`.
pub fn getF64(self: @This()) !f64 {
    if (!self.isF64()) return error.WrongType;
    return self.getF64_();
}

fn getF64_(self: @This()) !f64 {
    return @floatCast(@as(f64, @bitCast(try self.getArgumentValue())));
}

/// Tell if the given data item is a IEEE 754 Half-, Single- or Double-Precision float
pub fn isFloat(self: @This()) bool {
    const v = switch (self.head[0]) {
        0xf9, 0xfa, 0xfb => true,
        else => false,
    };
    return v;
}

/// Decode the given data item as float, returning the largest possible
/// representation, i.e., IEEE 754 Double-Precision.
///
/// This method will return an error if the given data item is not a float.
pub fn getFloat(self: @This()) !f64 {
    return switch (self.head[0]) {
        0xf9 => @as(f64, try self.getF16_()),
        0xfa => @as(f64, try self.getF32_()),
        0xfb => try self.getF64_(),
        else => error.NotAFloat,
    };
}

/// Get a text or byte string from a data item.
///
/// This requires a data item of major type 2 or 3.
///
/// The returned data is only valid as long as no other method, except for
/// `getMajorType()`, `getAdditionalInformation()`, `getInt()` or `getUInt()`,
/// is called on a given instance as this might advance the reader and therefore
/// invalidate the slice.
///
/// If you need to keep the data around, please copy it to a memory location
/// you own or call `getStringAlloc()` directly.
pub fn getString(self: @This()) ![]const u8 {
    const mt = self.getMajorType();
    if (mt != .ByteString and mt != .TextString) return error.WrongMajorType;

    const len = try self.getArgumentValue();

    return try self.reader.take(@intCast(len));
}

pub fn getStringSlice(self: @This(), buffer: []u8) !void {
    const mt = self.getMajorType();
    if (mt != .ByteString and mt != .TextString) return error.WrongMajorType;

    try self.reader.readSliceAll(buffer);
}

/// Get a text or byte string from a data item.
///
/// This requires a data item of major type 2 or 3.
///
/// Returns a slice owned by the caller.
pub fn getStringAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {
    const mt = self.getMajorType();
    if (mt != .ByteString and mt != .TextString) return error.WrongMajorType;

    const len = try self.getArgumentValue();

    return try self.reader.readAllocAll(allocator, len);
}

/// Get the length of a data item.
///
/// This is only relevant for arrays and maps to determine
/// how many data items should follow after the head.
///
/// * arrays: the returned length is the number of data items
/// * maps: the returned length is the number of data item pairs
pub fn getLength(self: @This()) !usize {
    return try self.getArgumentValue();
}

/// Check if a data item is indefinite.
///
/// This is only relevant for arrays and maps. Use this
/// in combination with `getMajorType()` to distinguish between
/// definite and indefinite arrays and maps.
pub fn isIndef(self: @This()) bool {
    return switch (self.head[0]) {
        0x9f, 0xbf => true,
        else => false,
    };
}

/// Check if the given data item is a break code that
/// terminates a indefinite length data item.
pub fn isBreakCode(self: @This()) bool {
    return self.head[0] == 0xff;
}

// ################################################################
// ###########            Parsing                 #################
// ################################################################

pub const DecodeError = error{
    UnsupportedType,
    UnexpectedItem,
    UnexpectedItemValue,
    InvalidKeyType,
    InvalidEnumTag,
    DuplicateCborField,
    UnknownField,
    MissingField,
    AllocatorRequired,
    Overflow,
    OutOfMemory,
    Malformed,
    NoUnionMemberMatched,
    FieldParsingDependencyNotSeenYet,
    NotYetImplemented,
    InvalidCharacter,
    NotAFloat,
    WrongMajorType,
    EndOfStream,
    ReadFailed,
    WriteFailed,
};

/// Options to influence the behavior of the en-/decode method
pub const Settings = struct {
    /// Whether an array should be serialized as definite or indefinite
    /// In the case of indefinite arrays, a break marker will be added after the array to signal the end of the array.
    array_serialization_type: ArraySerializationType = .ArrayDefinite,
    /// Wheter a map/struct should be serialized as a definite or indefinite CBOR map.
    /// In the case of a indefinite map, a break marker 0xff will be added after the
    /// map to signal the end.
    map_serialization_type: MapSerializationType = .MapDefinite,
    /// Pass an optional allocator. This is required different things, including
    /// parsing slices of unknown length.
    allocator: ?std.mem.Allocator = null,
    /// Settings for specific fields that override the default options
    field_settings: []const FieldSettings = &.{},
    /// How to behave if a CBOR map has two or more keys with
    /// the same value
    duplicate_field_behavior: enum {
        /// Use the first one
        UseFirst,
        /// Don't allow duplicates
        Error,
    } = .Error,
    /// Ignore CBOR map keys that were not expected
    ignore_unknown_fields: bool = true,
};

pub const SerializationType = enum {
    ByteString,
    TextString,
    Integer,
};

pub const ArraySerializationType = enum {
    ArrayDefinite,
    ArrayIndefinite,
};

pub const MapSerializationType = enum {
    MapDefinite,
    MapIndefinite,
};

pub const SkipBehavior = enum {
    /// Don't skip (default)
    None,
    /// Skip only if the field is null
    SkipIfNull,
    /// Always skip (e.g. fields of type std.mem.Allocator)
    Skip,
};

/// Options for a specific field specified by `name`
pub const FieldSettings = struct {
    /// The name of the field
    name: []const u8,
    /// Options for the field name
    field_options: struct {
        /// The alternative name of the field
        alias: ?[]const u8 = null,
        /// What the field name should be serialized to
        ///
        /// Please note that ByteString and TextString will always succeed
        /// while Integer might fail if the string can't be interpreted as
        /// a number.
        serialization_type: SerializationType = .TextString,
        skip: SkipBehavior = .SkipIfNull,
    } = .{},
    /// Options specific for the given field
    value_options: struct {
        /// What a enum value should be serialized to
        enum_serialization_type: SerializationType = .TextString,
        /// What a slice value should be serialized to
        slice_serialization_type: SerializationType = .ByteString,
    } = .{},
};

pub const DecodeOptions = struct {
    allocator: ?std.mem.Allocator = null,
};

pub fn decode(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    return blk: switch (@typeInfo(T)) {
        .bool => {
            break :blk switch (self.getType()) {
                .False => false,
                .True => true,
                else => error.UnexpectedItem,
            };
        },
        .float, .comptime_float => {
            break :blk switch (self.getType()) {
                .Float => @as(T, @floatCast(try self.getFloat())),
                else => error.UnexpectedItem,
            };
        },
        .int, .comptime_int => {
            break :blk switch (self.getMajorType()) {
                .UInt => inner: {
                    const v = try self.getUInt();

                    if (v > std.math.maxInt(T))
                        break :inner error.Overflow;

                    break :inner @as(T, @intCast(v));
                },
                .Int => inner: {
                    const v = try self.getInt();

                    if (v > std.math.maxInt(T) or v < std.math.minInt(T))
                        break :inner error.Overflow;

                    break :inner @as(T, @intCast(v));
                },
                else => error.UnexpectedItem,
            };
        },
        .optional => |optionalInfo| {
            break :blk switch (self.getType()) {
                .Null, .Undefined => null,
                else => try self.decode(optionalInfo.child, options),
            };
        },
        .@"enum" => |enumInfo| {
            break :blk switch (self.getMajorType()) {
                .UInt => std.enums.fromInt(T, try self.getUInt()) orelse error.InvalidEnumTag,
                .Int => std.enums.fromInt(T, try self.getInt()) orelse error.InvalidEnumTag,
                .TextString => inner: {
                    const v = try self.getString();

                    inline for (enumInfo.field_names) |field_name| {
                        if (std.mem.eql(u8, field_name, v)) {
                            break :inner @field(T, field_name);
                        }
                    }
                    break :inner error.InvalidEnumTag;
                },
                else => error.UnexpectedItem,
            };
        },
        .@"struct" => try self.decodeStruct(T, options),
        .pointer => try self.decodePointer(T, options),
        .array => try self.decodeArray(T, options),
        //.@"union" => try self.decodeUnion(T, options),
        else => error.NotYetImplemented,
    };
}

//fn decodeUnion(
//    self: @This(),
//    /// The type to decode to
//    comptime T: type,
//    options: DecodeOptions,
//) DecodeError!T {
//    const union_info = @typeInfo(T).@"union";
//
//    if (union_info.tag_type) |_| {
//
//        // try each union field until we find one that matches
//        inline for (0..union_info.field_names.len) |i| {
//            const field_name = union_info.field_names[i];
//            const field_type = union_info.field_types[i];
//
//            if (parse(field_type, item, options)) |value| {
//                return @unionInit(T, field_name, value);
//            } else |err| {
//                // Bubble up error.OutOfMemory
//                // Parsing some types won't have OutOfMemory in their
//                // error-sets, for the condition to be valid, merge it in.
//                if (@as(@TypeOf(err) || error{OutOfMemory}, err) == error.OutOfMemory) return err;
//                // Bubble up AllocatorRequired, as it indicates missing option
//                if (@as(@TypeOf(err) || error{AllocatorRequired}, err) == error.AllocatorRequired) return err;
//                // otherwise continue through the `inline for`
//            }
//        }
//        return ParseError.NoUnionMemberMatched;
//    } else {
//        @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
//    }
//}

fn decodeArray(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    const array_info = @typeInfo(T).array;

    return blk: switch (self.getType()) {
        .Array, .ArrayIndef => {
            const l = if (self.isIndef()) null else try self.getLength();
            var r: T = undefined;

            var i: usize = 0;
            while (true) : (i += 1) {
                if (l != null and i >= l.?) break;

                var child = try self.next();
                if (l == null and child.isBreakCode()) break;

                if (i >= r[0..].len) break :blk error.Overflow;
                r[i] = try child.decode(array_info.child, options);
            }

            if (i != r[0..].len) break :blk error.EndOfStream;

            break :blk r;
        },
        .ByteString, .TextString => {
            if (array_info.child != u8) break :blk error.UnexpectedItem;

            var r: T = @splat(0);

            const l = try self.getLength();
            if (l > r[0..].len) break :blk error.Overflow;

            try self.getStringSlice(r[0..]);

            break :blk r;
        },
        else => error.UnexpectedItem,
    };
}

fn decodePointer(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    const allocator = options.allocator orelse return error.AllocatorRequired;

    const ptr_info = @typeInfo(T).pointer;

    return blk: switch (ptr_info.size) {
        .one => {
            // We use *ptrInfo.child instead of T to allow const and non-const types
            const r: *ptr_info.child = try allocator.create(ptr_info.child);
            errdefer allocator.destroy(r);
            r.* = try self.decode(ptr_info.child, options);
            break :blk r;
        },
        .slice => {
            switch (self.getType()) {
                .ByteString, .TextString => {
                    if (ptr_info.child != u8)
                        break :blk error.UnexpectedItem;

                    const l = try self.getLength();
                    var s: usize = 0;
                    if (ptr_info.sentinel_ptr != null)
                        s += 1;

                    var v = try allocator.alloc(u8, l + s);
                    try self.getStringSlice(v[0..l]);
                    errdefer allocator.free(v);

                    if (ptr_info.sentinel_ptr) |sentinel| {
                        const sentinel_value = @as(*align(1) const ptr_info.child, @ptrCast(sentinel)).*;
                        v[v.len - 1] = sentinel_value;
                        break :blk v[0 .. v.len - 1 :sentinel_value];
                    }

                    break :blk v;
                },
                .Array, .ArrayIndef => {
                    var l = if (self.isIndef()) null else try self.getLength();
                    if (ptr_info.sentinel_ptr != null) l += 1;

                    var arr: std.ArrayListUnmanaged(ptr_info.child) = .empty;
                    if (l) |l_| {
                        try arr.ensureTotalCapacity(allocator, l_);
                    }
                    errdefer {
                        // TODO deinit children if possible. the only viable
                        // approach would be to see if the following method
                        // exists `fn deinit(Allocator) void`.
                        arr.deinit(allocator);
                    }

                    var i: usize = 0;
                    while (true) : (i += 1) {
                        if (l != null and i >= l.?) break;

                        var child = try self.next();
                        if (l == null and child.isBreakCode()) break;

                        try arr.append(
                            allocator,
                            try child.decode(ptr_info.child, options),
                        );
                    }

                    if (ptr_info.sentinel_ptr) |sentinel| {
                        const sentinel_value = @as(*align(1) const ptr_info.child, @ptrCast(sentinel)).*;
                        try arr.append(allocator, sentinel_value);
                        break :blk try arr.toOwnedSliceSentinel(allocator, sentinel_value);
                    }

                    break :blk try arr.toOwnedSlice(allocator);
                },
                else => break :blk error.UnexpectedItem,
            }
        },
        else => break :blk error.UnsupportedType,
    };
}

fn decodeStruct(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    const struct_info = @typeInfo(T).@"struct";

    // The field settings can influence how a map is translated into a struct, e.g.,
    // using alternative names for fields.
    const has_settings = comptime std.meta.hasFn(T, "cborSettings");
    const settings: ?Settings = if (has_settings) T.cborSettings() else null;

    return switch (self.getType()) {
        .Map, .MapIndef => {
            var r: T = undefined;
            var fields_seen: [struct_info.field_names.len]bool = @splat(false);

            const len = if (self.isIndef()) null else try self.getLength();

            var i: usize = 0;
            while (true) : (i += 1) {
                if (len != null and i >= len.?) break;

                var found = false;

                // We expect either a key-value pair or a break code
                const key_ = try self.next();
                if (len == null and key_.getType() == .Break) break;

                const key: union(enum) { int: i65, str: []const u8 } = switch (key_.getType()) {
                    .Int => .{ .int = try key_.getInt() },
                    .ByteString, .TextString => .{ .str = try key_.getString() },
                    else => return error.InvalidKeyType,
                };

                inline for (0..struct_info.field_names.len) |j| {
                    var match = false;
                    var name: []const u8 = struct_info.field_names[j];

                    // std.mem.Allocator contains anyopaque which isn't
                    // possible to parse.
                    if (struct_info.field_types[j] == std.mem.Allocator) continue;

                    // Is there an alias specified?
                    if (settings) |settings_| {
                        for (settings_.field_settings) |fs| {
                            if (std.mem.eql(u8, name, fs.name)) {
                                if (fs.field_options.alias) |alias| {
                                    name = alias;
                                }

                                break;
                            }
                        }
                    }

                    switch (key) {
                        .int => |x| match = x == s2n(name),
                        .str => |x| match = std.mem.eql(u8, name, x),
                    }

                    if (match) {
                        if (fields_seen[j] and settings != null and settings.?.duplicate_field_behavior == .Error) return error.DuplicateCborField;
                        if (fields_seen[j] and (settings == null or settings != null and settings.?.duplicate_field_behavior == .UseFirst)) {
                            found = true;
                            break;
                        }

                        var value = try self.next();

                        @field(r, struct_info.field_names[j]) =
                            try value.decode(
                                struct_info.field_types[j],
                                options,
                            );

                        errdefer {
                            // TODO: add error defer to free memory
                            const I = @typeInfo(@TypeOf(@field(r, struct_info.field_names[j])));

                            switch (I) {
                                .pointer => |ptrInfo| {
                                    _ = ptrInfo;
                                },
                                else => {},
                            }
                        }

                        fields_seen[j] = true;
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    if (settings != null and !settings.?.ignore_unknown_fields) {
                        return error.UnknownField;
                    }

                    // Discard the value so we don't get "out of sync"
                    var di = try self.next();
                    try di.skip(null);
                }
            }

            inline for (0..struct_info.field_names.len) |j| {
                const field_type = struct_info.field_types[j];
                const field_name = struct_info.field_names[j];
                const field_attr = struct_info.field_attrs[j];

                if (!fields_seen[j]) {
                    switch (@typeInfo(field_type)) {
                        .optional => @field(r, field_name) = null,
                        else => {
                            if (field_type == std.mem.Allocator and options.allocator != null) {
                                // Assign the allocator that was provided by the caller
                                @field(r, field_name) = options.allocator.?;
                            } else if (field_attr.default_value_ptr) |default_ptr| {
                                if (!field_attr.@"comptime") {
                                    const default = @as(*align(1) const field_type, @ptrCast(default_ptr)).*;
                                    @field(r, field_name) = default;
                                }
                            } else {
                                return error.MissingField;
                            }
                        },
                    }
                }
            }

            return r;
        },
        else => error.UnexpectedItem,
    };
}

// ################################################################
// ###########            Helper                  #################
// ################################################################

fn s2n(s: []const u8) ?i65 {
    if (s.len < 1) return null;
    const start: usize = if (s[0] == '-') 1 else 0;

    var x: i64 = 0;

    for (s[start..]) |c| {
        if (c > 57 or c < 48) return null;
        x *= 10;
        x += @as(i64, @intCast(c - 48));
    }

    return if (start == 1) -x else x;
}

fn skip(self: @This(), writer: ?*std.Io.Writer) !void {
    switch (self.head[0]) {
        0x40...0x5b, 0x60...0x7b => { // string
            if (writer) |w| {
                const l = try self.getLength();
                try self.reader.streamExact(w, l);
            } else {
                const l = try self.getLength();
                try self.reader.discardAll(l);
            }
        },
        0x80...0x9b => { // Array
            const l = try self.getLength();
            for (0..l) |_| {
                var child = try self.next();
                try child.skip(writer);
            }
        },
        0x9f, 0xbf => { // indef
            while (true) {
                var child = try self.next();
                if (child.getType() == .Break) {
                    if (writer) |w| try w.writeByte('\xff');
                    break;
                }
                try child.skip(writer);
            }
        },
        0xa0...0xbb => { // Map
            const l = try self.getLength();
            for (0..l) |_| {
                var key = try self.next();
                try key.skip(writer);

                var value = try self.next();
                try value.skip(writer);
            }
        },
        0xc0...0xdb => { // tag
            var child = try self.next();
            try child.skip(writer);
        },
        else => {},
    }
}

// ################################################################
// ###########            Tests                   #################
// ################################################################

test "decode unsigned (major type 0)" {
    const V = struct { []const u8, u64 };
    const test_vector = [_]V{
        .{ "\x00", 0 },
        .{ "\x01", 1 },
        .{ "\x17", 23 },
        .{ "\x18\x18", 24 },
        .{ "\x18\x64", 100 },
        .{ "\x19\x03\xe8", 1000 },
        .{ "\x1a\x00\x0f\x42\x40", 1000000 },
        .{ "\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00", 1000000000000 },
        .{ "\x1b\xff\xff\xff\xff\xff\xff\xff\xff", 18446744073709551615 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(MajorType.UInt, di.getMajorType());
        try std.testing.expectEqual(v.@"1", try di.getUInt());
    }
}

test "decode signed (major type 1)" {
    const V = struct { []const u8, i65 };
    const test_vector = [_]V{
        .{ "\x20", -1 },
        .{ "\x29", -10 },
        .{ "\x38\x63", -100 },
        .{ "\x39\x03\xe7", -1000 },
        .{ "\x3b\xff\xff\xff\xff\xff\xff\xff\xff", -18446744073709551616 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(MajorType.Int, di.getMajorType());
        try std.testing.expectEqual(v.@"1", try di.getInt());
    }
}

test "decode strings (major type 2 or 3)" {
    const V = struct { []const u8, []const u8, MajorType };
    const test_vector = [_]V{
        .{ "\x40", "", MajorType.ByteString },
        .{ "\x44\x01\x02\x03\x04", "\x01\x02\x03\x04", MajorType.ByteString },
        .{ "\x60", "", MajorType.TextString },
        .{ "\x61\x61", "a", MajorType.TextString },
        .{ "\x64\x49\x45\x54\x46", "IETF", MajorType.TextString },
        .{ "\x62\x22\x5c", "\"\\", MajorType.TextString },
        .{ "\x62\xc3\xbc", "ü", MajorType.TextString },
        .{ "\x63\xe6\xb0\xb4", "水", MajorType.TextString },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(v.@"2", di.getMajorType());
        try std.testing.expectEqualSlices(u8, v.@"1", try di.getString());
    }
}

test "decode strings with allocation (major type 2 or 3)" {
    const V = struct { []const u8, []const u8, MajorType };
    const test_vector = [_]V{
        .{ "\x40", "", MajorType.ByteString },
        .{ "\x44\x01\x02\x03\x04", "\x01\x02\x03\x04", MajorType.ByteString },
        .{ "\x60", "", MajorType.TextString },
        .{ "\x61\x61", "a", MajorType.TextString },
        .{ "\x64\x49\x45\x54\x46", "IETF", MajorType.TextString },
        .{ "\x62\x22\x5c", "\"\\", MajorType.TextString },
        .{ "\x62\xc3\xbc", "ü", MajorType.TextString },
        .{ "\x63\xe6\xb0\xb4", "水", MajorType.TextString },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(v.@"2", di.getMajorType());

        const s = try di.getStringAlloc(std.testing.allocator);
        defer std.testing.allocator.free(s);
        try std.testing.expectEqualSlices(u8, v.@"1", s);
    }
}

test "decode float (major type 7)" {
    const V = struct { []const u8, f64 };
    const test_vector = [_]V{
        .{ "\xfb\x3f\xf1\x99\x99\x99\x99\x99\x9a", 1.1 },
        .{ "\xf9\x3e\x00", 1.5 },
        .{ "\xf9\x80\x00", -0.0 },
        .{ "\xfb\x7e\x37\xe4\x3c\x88\x00\x75\x9c", 1.0e+300 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(MajorType.Float_Simple, di.getMajorType());
        try std.testing.expect(di.isFloat());

        try std.testing.expectApproxEqAbs(
            v.@"1",
            try di.getFloat(),
            0.000000001,
        );
    }
}

test "decode float (major type 7) #2" {
    const V = struct { []const u8, ?f16, ?f32, ?f64 };
    const test_vector = [_]V{
        .{ "\xf9\x00\x00", 0.0, null, null },
        .{ "\xf9\x80\x00", -0.0, null, null },
        .{ "\xf9\x7b\xff", 65504.0, null, null },
        .{ "\xfa\x7f\x7f\xff\xff", null, 3.4028234663852886e+38, null },
        .{ "\xfb\xc0\x10\x66\x66\x66\x66\x66\x66", null, null, -4.1 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(MajorType.Float_Simple, di.getMajorType());
        try std.testing.expect(di.isFloat());

        if (v.@"1") |e| {
            try std.testing.expect(di.isF16());
            try std.testing.expect(!di.isF32());
            try std.testing.expect(!di.isF64());

            try std.testing.expectEqual(
                e,
                try di.getF16(),
            );
        }

        if (v.@"2") |e| {
            try std.testing.expect(!di.isF16());
            try std.testing.expect(di.isF32());
            try std.testing.expect(!di.isF64());

            try std.testing.expectEqual(
                e,
                try di.getF32(),
            );
        }

        if (v.@"3") |e| {
            try std.testing.expect(!di.isF16());
            try std.testing.expect(!di.isF32());
            try std.testing.expect(di.isF64());

            try std.testing.expectEqual(
                e,
                try di.getF64(),
            );
        }
    }
}

test "deserialize array #1" {
    var reader = std.Io.Reader.fixed("\x80");
    var di = try Self.new(&reader);

    try std.testing.expectEqual(MajorType.Array, di.getMajorType());

    try std.testing.expectError(error.EndOfStream, Self.new(&reader));
}

test "deserialize array #2" {
    var reader = std.Io.Reader.fixed("\x83\x01\x02\x03");
    var di = try Self.new(&reader);

    try std.testing.expectEqual(MajorType.Array, di.getMajorType());
    try std.testing.expectEqual(@as(usize, 3), try di.getLength());

    for (1..4) |i| {
        var child = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child.getMajorType());
        try std.testing.expectEqual(@as(u64, @intCast(i)), try child.getUInt());
    }

    // There shouldn't be more data items left
    try std.testing.expectError(error.EndOfStream, Self.new(&reader));
}

test "deserialize array #3" {
    var reader = std.Io.Reader.fixed("\x98\x19\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19");
    var di = try Self.new(&reader);

    // To parse a array do the following:

    // 1) Check that it's an array
    try std.testing.expectEqual(MajorType.Array, di.getMajorType());

    // 2) Get the length of the array
    try std.testing.expectEqual(@as(usize, 25), try di.getLength());

    for (1..26) |i| {
        // For every child, create a new data item from the reader and read the data.
        var child = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child.getMajorType());
        try std.testing.expectEqual(@as(u64, @intCast(i)), try child.getUInt());
    }

    // There shouldn't be more data items left
    try std.testing.expectError(error.EndOfStream, Self.new(&reader));
}

test "deserialize nested array " {
    var reader = std.Io.Reader.fixed("\x83\x01\x82\x02\x03\x82\x04\x05");
    var di = try Self.new(&reader);

    try std.testing.expectEqual(MajorType.Array, di.getMajorType());
    try std.testing.expectEqual(@as(usize, 3), try di.getLength());

    var child1 = try Self.new(&reader);
    try std.testing.expectEqual(MajorType.UInt, child1.getMajorType());
    try std.testing.expectEqual(@as(u64, 1), try child1.getUInt());

    var child2 = try Self.new(&reader);
    try std.testing.expectEqual(MajorType.Array, child2.getMajorType());
    try std.testing.expectEqual(@as(usize, 2), try child2.getLength());
    {
        var child2_1 = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child2_1.getMajorType());
        try std.testing.expectEqual(@as(u64, 2), try child2_1.getUInt());

        var child2_2 = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child2_2.getMajorType());
        try std.testing.expectEqual(@as(u64, 3), try child2_2.getUInt());
    }

    var child3 = try Self.new(&reader);
    try std.testing.expectEqual(MajorType.Array, child3.getMajorType());
    try std.testing.expectEqual(@as(usize, 2), try child3.getLength());
    {
        var child3_1 = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child3_1.getMajorType());
        try std.testing.expectEqual(@as(u64, 4), try child3_1.getUInt());

        var child3_2 = try Self.new(&reader);
        try std.testing.expectEqual(MajorType.UInt, child3_2.getMajorType());
        try std.testing.expectEqual(@as(u64, 5), try child3_2.getUInt());
    }
}

test "decode boolean" {
    const V = struct { []const u8, ?bool };
    const test_vector = [_]V{
        .{ "\xf5", true },
        .{ "\xf4", false },
        .{ "\xf7", null },
        .{ "\x0b", null },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        if (v.@"1") |value| {
            try std.testing.expectEqual(
                value,
                try di.decode(bool, .{}),
            );
        } else {
            try std.testing.expectError(
                DecodeError.UnexpectedItem,
                di.decode(bool, .{}),
            );
        }
    }
}

test "decode float" {
    const V = struct { []const u8, ?f16, ?f32, ?f64 };
    const test_vector = [_]V{
        .{ "\xfb\x3f\xf1\x99\x99\x99\x99\x99\x9a", 1.1, null, null },
        .{ "\xFB\x40\x1D\x67\x86\xC2\x26\x80\x9D", 7.3511, 7.3511, null },
        .{ "\xFB\xC0\x28\x1E\xB8\x51\xEB\x85\x1F", null, -12.06, -12.06 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        if (v.@"1") |value| {
            try std.testing.expectApproxEqRel(
                value,
                try di.decode(f16, .{}),
                0.01,
            );
        }

        if (v.@"2") |value| {
            try std.testing.expectApproxEqRel(
                value,
                try di.decode(f32, .{}),
                0.01,
            );
        }

        if (v.@"3") |value| {
            try std.testing.expectApproxEqRel(
                value,
                try di.decode(f64, .{}),
                0.01,
            );
        }
    }
}

test "decode int" {
    const V = struct { []const u8, ?u8, ?u32, ?u64, ?i65 };
    const test_vector = [_]V{
        .{ "\x00", 0, 0, 0, 0 },
        .{ "\x01", 1, 1, 1, 1 },
        .{ "\x0a", 10, 10, 10, 10 },
        .{ "\x17", 23, 23, 23, 23 },
        .{ "\x18\x18", 24, 24, 24, 24 },
        .{ "\x18\x19", 25, 25, 25, 25 },
        .{ "\x18\x64", 100, 100, 100, 100 },
        .{ "\x18\x7b", 123, 123, 123, 123 },
        .{ "\x19\x03\xe8", null, 1000, 1000, 1000 },
        .{ "\x19\x04\xd2", null, 1234, 1234, 1234 },
        .{ "\x1a\x00\x01\xe2\x40", null, 123456, 123456, 123456 },
        .{ "\x1a\x00\x0f\x42\x40", null, 1000000, 1000000, 1000000 },
        .{ "\x1b\x00\x00\x00\x02\xdf\xdc\x1c\x34", null, null, 12345678900, 12345678900 },
        .{ "\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00", null, null, 1000000000000, 1000000000000 },
        .{ "\x1b\xff\xff\xff\xff\xff\xff\xff\xff", null, null, 18446744073709551615, 18446744073709551615 },
        .{ "\x20", null, null, null, -1 },
        .{ "\x22", null, null, null, -3 },
        .{ "\x38\x63", null, null, null, -100 },
        .{ "\x39\x01\xf3", null, null, null, -500 },
        .{ "\x39\x03\xe7", null, null, null, -1000 },
        .{ "\x3a\x00\x0f\x3d\xdc", null, null, null, -998877 },
        .{ "\x3b\x00\x00\x00\x02\x53\x60\xa2\xce", null, null, null, -9988776655 },
        .{ "\x3b\xff\xff\xff\xff\xff\xff\xff\xff", null, null, null, -18446744073709551616 },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        if (v.@"1") |value| {
            try std.testing.expectEqual(
                value,
                try di.decode(u8, .{}),
            );
        }

        if (v.@"2") |value| {
            try std.testing.expectEqual(
                value,
                try di.decode(u32, .{}),
            );
        }

        if (v.@"3") |value| {
            try std.testing.expectEqual(
                value,
                try di.decode(u64, .{}),
            );
        }

        if (v.@"4") |value| {
            try std.testing.expectEqual(
                value,
                try di.decode(i65, .{}),
            );
        }
    }
}

test "decode null value" {
    const V = struct { []const u8, ?u32 };
    const test_vector = [_]V{
        .{ "\x19\x04\xD2", 1234 },
        .{ "\xf6", null },
        .{ "\xf7", null },
    };

    for (test_vector) |v| {
        var reader = std.Io.Reader.fixed(v.@"0");
        var di = try Self.new(&reader);

        try std.testing.expectEqual(
            v.@"1",
            try di.decode(?u32, .{}),
        );
    }
}

test "decode enum #1" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    var reader1 = std.Io.Reader.fixed("\x64\x68\x69\x67\x68");
    var di1 = try Self.new(&reader1);
    const x1 = try di1.decode(Level, .{});
    try std.testing.expectEqual(Level.high, x1);

    var reader2 = std.Io.Reader.fixed("\x63\x6C\x6F\x77");
    var di2 = try Self.new(&reader2);
    const x2 = try di2.decode(Level, .{});
    try std.testing.expectEqual(Level.low, x2);
}

test "decode enum #2" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    var reader1 = std.Io.Reader.fixed("\x07");
    var di1 = try Self.new(&reader1);
    const x1 = try di1.decode(Level, .{});
    try std.testing.expectEqual(Level.high, x1);

    var reader2 = std.Io.Reader.fixed("\x0b");
    var di2 = try Self.new(&reader2);
    const x2 = try di2.decode(Level, .{});
    try std.testing.expectEqual(Level.low, x2);
}

test "decode enum #3" {
    const Level = enum(i8) {
        high = -7,
        low = -11,
    };

    var reader1 = std.Io.Reader.fixed("\x26");
    var di1 = try Self.new(&reader1);
    const x1 = try di1.decode(Level, .{});
    try std.testing.expectEqual(Level.high, x1);

    var reader2 = std.Io.Reader.fixed("\x2a");
    var di2 = try Self.new(&reader2);
    const x2 = try di2.decode(Level, .{});
    try std.testing.expectEqual(Level.low, x2);
}

test "decode struct #1" {
    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    var reader = std.Io.Reader.fixed("\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");
    var di = try Self.new(&reader);

    const c = try di.decode(Config, .{});

    try std.testing.expectEqual(c.uptime, 9999);
    try std.testing.expectEqual(c.vals.testing, 1);
    try std.testing.expectEqual(c.vals.production, 42);
}

test "parse struct #2 (optional missing field)" {
    const Config = struct {
        vals: struct { testing: u8, production: ?u8 },
        uptime: u64,
    };

    var reader = std.Io.Reader.fixed("\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");
    var di = try Self.new(&reader);

    const c = try di.decode(Config, .{});

    try std.testing.expectEqual(c.uptime, 9999);
    try std.testing.expectEqual(c.vals.testing, 1);
    try std.testing.expectEqual(c.vals.production, null);
}

test "decode struct #3 (missing field)" {
    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    var reader = std.Io.Reader.fixed("\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.MissingField, di.decode(Config, .{}));
}

test "decode struct #4 (unknown field)" {
    const Config = struct {
        vals: struct {
            testing: u8,

            pub fn cborSettings() Settings {
                return .{
                    .ignore_unknown_fields = false,
                };
            }
        },
        uptime: u64,
    };

    var reader = std.Io.Reader.fixed("\xa2\x64\x76\x61\x6c\x73\xa2\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x6a\x70\x72\x6f\x64\x75\x63\x74\x69\x6f\x6e\x18\x2a\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.UnknownField, di.decode(Config, .{}));
}

test "parse struct #5" {
    const Config = struct {
        @"1": struct { @"1": u8, @"2": u8 },
        @"2": u64,
    };

    var reader = std.Io.Reader.fixed("\xA2\x01\xA2\x01\x01\x02\x18\x2A\x02\x19\x27\x0F");
    var di = try Self.new(&reader);

    const c = try di.decode(Config, .{});

    try std.testing.expectEqual(c.@"2", 9999);
    try std.testing.expectEqual(c.@"1".@"1", 1);
    try std.testing.expectEqual(c.@"1".@"2", 42);
}

test "decode struct #6" {
    const allocator = std.testing.allocator;

    const Info = struct {
        @"1": []const []const u8,
        @"2": []const []const u8,
        @"3": []const u8,
        @"4": struct {
            plat: bool,
            rk: bool,
            clientPin: ?bool,
            up: bool,
            uv: ?bool,
        },
        @"5": ?u64,
        @"6": ?[]const u64,
    };

    var reader = std.Io.Reader.fixed("\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4");
    var di = try Self.new(&reader);

    const i = try di.decode(Info, .{ .allocator = allocator });
    defer {
        allocator.free(i.@"1"[0]);
        allocator.free(i.@"1");
        allocator.free(i.@"2");
        allocator.free(i.@"3");
    }

    try std.testing.expectEqual(@as(usize, 1), i.@"1".len);
    try std.testing.expectEqualStrings("FIDO_2_0", i.@"1"[0]);
    try std.testing.expectEqual(@as(usize, 0), i.@"2".len);
    try std.testing.expectEqualStrings("\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F", i.@"3");
    try std.testing.expectEqual(true, i.@"4".plat);
    try std.testing.expectEqual(true, i.@"4".rk);
    try std.testing.expectEqual(true, i.@"4".up);
    try std.testing.expectEqual(false, i.@"4".uv);
}

test "decode struct #7" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const Info = struct {
        x: Level,
        y: Level,
    };

    var reader = std.Io.Reader.fixed("\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B");
    var di = try Self.new(&reader);

    const x = try di.decode(Info, .{});

    try std.testing.expectEqual(x.x, Level.high);
    try std.testing.expectEqual(x.y, Level.low);
}

test "decode array #1" {
    const e = [5]u8{ 1, 2, 3, 4, 5 };

    var reader = std.Io.Reader.fixed("\x85\x01\x02\x03\x04\x05");
    var di = try Self.new(&reader);

    const x = try di.decode([5]u8, .{});

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "decode array #2" {
    const e = [5]?u8{ 1, null, 3, null, 5 };

    var reader = std.Io.Reader.fixed("\x85\x01\xF6\x03\xF6\x05");
    var di = try Self.new(&reader);

    const x = try di.decode([5]?u8, .{});

    try std.testing.expectEqualSlices(?u8, e[0..], x[0..]);
}

test "decode array #3" {
    const e = [5]u8{ 1, 2, 3, 4, 5 };

    var reader = std.Io.Reader.fixed("\x9f\x01\x02\x03\x04\x05\xff");
    var di = try Self.new(&reader);

    const x = try di.decode([5]u8, .{});

    try std.testing.expectEqualSlices(u8, e[0..], x[0..]);
}

test "decode array #4" {
    var reader = std.Io.Reader.fixed("\x9f\x01\x02\x03\x04\x05\xff");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.Overflow, di.decode([3]u8, .{}));
}

test "decode array from string #1" {
    var reader = std.Io.Reader.fixed("\x43\x01\x02\x03");
    var di = try Self.new(&reader);

    const x = try di.decode([3]u8, .{});

    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, &x);
}

test "decode array from string #2" {
    var reader = std.Io.Reader.fixed("\x63abc");
    var di = try Self.new(&reader);

    const x = try di.decode([3]u8, .{});

    try std.testing.expectEqualSlices(u8, "abc", &x);
}

test "decode array from string #3" {
    var reader = std.Io.Reader.fixed("\x9f\x01\x02\x03\x04\x05\xff");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.Overflow, di.decode([3]u8, .{}));
}

test "decode array from string #4" {
    var reader = std.Io.Reader.fixed("\x42\x01\x02");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.EndOfStream, di.decode([3]u8, .{}));
}

test "decode array from string #5" {
    var reader = std.Io.Reader.fixed("\x62ab");
    var di = try Self.new(&reader);

    try std.testing.expectError(error.EndOfStream, di.decode([3]u8, .{}));
}

test "decode pointer #1" {
    const allocator = std.testing.allocator;

    const e1_1: u32 = 1234;
    const e1: *const u32 = &e1_1;
    var reader = std.Io.Reader.fixed("\x19\x04\xD2");
    var di = try Self.new(&reader);
    const c1 = try di.decode(*const u32, .{ .allocator = allocator });
    defer allocator.destroy(c1);
    try std.testing.expectEqual(e1.*, c1.*);

    var e2_1: u32 = 1234;
    const e2: *u32 = &e2_1;
    var reader2 = std.Io.Reader.fixed("\x19\x04\xD2");
    var di2 = try Self.new(&reader2);
    const c2 = try di2.decode(*u32, .{ .allocator = allocator });
    defer allocator.destroy(c2);
    try std.testing.expectEqual(e2.*, c2.*);
}

test "decode slice #1" {
    const allocator = std.testing.allocator;

    const e1: []const u8 = &.{ 1, 2, 3, 4, 5 };
    var reader = std.Io.Reader.fixed("\x45\x01\x02\x03\x04\x05");
    var di1 = try Self.new(&reader);
    const c1 = try di1.decode([]const u8, .{ .allocator = allocator });
    defer allocator.free(c1);
    try std.testing.expectEqualSlices(u8, e1, c1);

    var e2 = [5]u8{ 1, 2, 3, 4, 5 };
    var reader2 = std.Io.Reader.fixed("\x45\x01\x02\x03\x04\x05");
    var di2 = try Self.new(&reader2);
    const c2 = try di2.decode([]u8, .{ .allocator = allocator });
    defer allocator.free(c2);
    try std.testing.expectEqualSlices(u8, e2[0..], c2);
}

test "decode slice #2" {
    const allocator = std.testing.allocator;

    const e1: []const u8 = &.{ 1, 2, 3, 4, 5 };
    var reader = std.Io.Reader.fixed("\x9f\x01\x02\x03\x04\x05\xff");
    var di = try Self.new(&reader);
    const c1 = try di.decode([]const u8, .{ .allocator = allocator });
    defer allocator.free(c1);
    try std.testing.expectEqualSlices(u8, e1, c1);
}

test "decode slice #3" {
    const allocator = std.testing.allocator;
    var random = std.Random.DefaultPrng.init(std.testing.random_seed);
    // Generate a random indefinite length array
    var bytes = std.Io.Writer.Allocating.init(allocator);
    defer bytes.deinit();
    try bytes.writer.writeAll("\x9f");
    while (random.random().int(u8) % 200 != 0) {
        const byte = random.random().int(u8) % 10;
        try bytes.writer.writeByte(byte);
    }
    try bytes.writer.writeAll("\xff");

    var reader = std.Io.Reader.fixed(bytes.written());
    var di = try Self.new(&reader);

    const c1 = try di.decode([]const u8, .{ .allocator = allocator });
    defer allocator.free(c1);
    // No assert, we just want to make sure it doesn't crash
}
