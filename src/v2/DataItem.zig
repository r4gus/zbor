const std = @import("std");

const Self = @This();

reader: *std.Io.Reader,
head: [9]u8,

/// The maximum length for text keys and enums;
pub const max_key_len = 1024;

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
        25 => @memcpy(head[1..3], try reader.take(2)),
        26 => @memcpy(head[1..5], try reader.take(4)),
        27 => @memcpy(head[1..9], try reader.take(8)),
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

pub fn toOwnedSlice(self: @This(), allocator: std.mem.Allocator) ![]u8 {
    var w = std.Io.Writer.Allocating.init(allocator);
    errdefer w.deinit();

    try self.skip(&w.writer);

    return try w.toOwnedSlice();
}

/// Get the major type of the data item
pub fn getMajorType(self: @This()) MajorType {
    return @fromBackingInt(@as(u3, @intCast(self.head[0] >> 5)));
}

pub fn getHeaderLength(self: @This()) usize {
    const ai: u5 = @intCast(self.head[0] & 0x1f);

    return switch (ai) {
        24 => 2,
        25 => 3,
        26 => 5,
        27 => 9,
        else => 1,
    };
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

/// Get a text or byte string from a data item by writing it
/// into a buffer.
///
/// This requires a data item of major type 2 or 3.
///
/// Use `getLength()` to get the length of the data item.
pub fn getStringSlice(self: @This(), buffer: []u8) ![]u8 {
    const mt = self.getMajorType();
    if (mt != .ByteString and mt != .TextString) return error.WrongMajorType;

    const len = try self.getLength();
    if (buffer.len < len) return error.BufferTooSmall;

    try self.reader.readSliceAll(buffer[0..len]);
    return buffer[0..len];
}

pub fn getStringSliceStrict(self: @This(), buffer: []u8) ![]u8 {
    const mt = self.getMajorType();
    if (mt != .ByteString and mt != .TextString) return error.WrongMajorType;

    const len = try self.getLength();
    if (buffer.len < len) return error.BufferTooSmall;
    if (buffer.len > len) return error.EndOfStream;

    try self.reader.readSliceAll(buffer[0..len]);
    return buffer[0..len];
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
    BufferTooSmall,
    Recursion,
};

/// Options to influence the behavior of the en-/decode method
pub const Settings = struct {
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
        /// Whether an array should be serialized as definite or indefinite
        /// In the case of indefinite arrays, a break marker will be added after the array to signal the end of the array.
        array_serialization_type: ArraySerializationType = .ArrayDefinite,
        /// Wheter a map/struct should be serialized as a definite or indefinite CBOR map.
        /// In the case of a indefinite map, a break marker 0xff will be added after the
        /// map to signal the end.
        map_serialization_type: MapSerializationType = .MapDefinite,
    } = .{},
};

pub const DecodeOptions = struct {
    allocator: ?std.mem.Allocator = null,
    depth: usize = 128,
};

pub fn decode(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    var options_ = options;
    if (options_.depth == 0) return error.Recursion;
    options_.depth -= 1;

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
                else => try self.decode(optionalInfo.child, options_),
            };
        },
        .@"enum" => |enumInfo| {
            break :blk switch (self.getMajorType()) {
                .UInt => std.enums.fromInt(T, try self.getUInt()) orelse error.InvalidEnumTag,
                .Int => std.enums.fromInt(T, try self.getInt()) orelse error.InvalidEnumTag,
                .TextString => inner: {
                    var buffer: [max_key_len]u8 = undefined;
                    const v = try self.getStringSlice(&buffer);

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
        .@"struct" => try self.decodeStruct(T, options_),
        .pointer => try self.decodePointer(T, options_),
        .array => try self.decodeArray(T, options_),
        .@"union" => try self.decodeUnion(T, options_),
        else => error.NotYetImplemented,
    };
}

fn decodeUnion(
    self: @This(),
    /// The type to decode to
    comptime T: type,
    options: DecodeOptions,
) DecodeError!T {
    const union_info = @typeInfo(T).@"union";

    const has_parse = comptime std.meta.hasFn(T, "cborDecode");
    if (has_parse) {
        return T.cborDecode(self);
    }

    if (union_info.tag_type) |_| {
        // We need to try out different union fields. This means we have
        // to store the data item somewhere for reuse.
        const a = options.allocator orelse return error.AllocatorRequired;

        var writer = std.Io.Writer.Allocating.init(a);
        defer writer.deinit();

        try self.skip(&writer.writer);

        // try each union field until we find one that matches
        inline for (0..union_info.field_names.len) |i| {
            const field_name = union_info.field_names[i];
            const field_type = union_info.field_types[i];

            var reader = std.Io.Reader.fixed(writer.written());
            var di = try @This().new(&reader);

            if (di.decode(field_type, options)) |v| {
                return @unionInit(T, field_name, v);
            } else |err| {
                // Bubble up error.OutOfMemory
                // Parsing some types won't have OutOfMemory in their
                // error-sets, for the condition to be valid, merge it in.
                if (@as(@TypeOf(err) || error{OutOfMemory}, err) == error.OutOfMemory) return err;
                // Bubble up AllocatorRequired, as it indicates missing option
                if (@as(@TypeOf(err) || error{AllocatorRequired}, err) == error.AllocatorRequired) return err;
                // otherwise continue through the `inline for`
            }
        }

        return error.NoUnionMemberMatched;
    } else {
        @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
    }
}

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

            _ = try self.getStringSliceStrict(r[0..]);

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
                    if (ptr_info.sentinel_ptr != null) {
                        s += 1;
                    }

                    var v = try allocator.alloc(u8, try std.math.add(usize, l, s));
                    _ = try self.getStringSlice(v[0..l]);
                    errdefer allocator.free(v);

                    if (ptr_info.sentinel_ptr) |sentinel| {
                        const sentinel_value = @as(*align(1) const ptr_info.child, @ptrCast(sentinel)).*;
                        v[v.len - 1] = sentinel_value;
                        break :blk v[0 .. v.len - 1 :sentinel_value];
                    }

                    break :blk v;
                },
                .Array, .ArrayIndef => {
                    const l = if (self.isIndef()) null else try self.getLength();

                    var arr: std.ArrayListUnmanaged(ptr_info.child) = .empty;
                    errdefer {
                        // TODO deinit children if possible. the only viable
                        // approach would be to see if the following method
                        // exists `fn deinit(Allocator) void`.
                        arr.deinit(allocator);
                    }
                    if (l) |l_| {
                        // We want to prevent unnecessary re-allocations but
                        // we also don't want untrusted data to force us to
                        // allocate large amounts of memory and therefore exhaust
                        // the available memory.
                        const bound = @max(256, self.reader.bufferedLen());
                        try arr.ensureTotalCapacity(allocator, @min(l_, bound));
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

    // Custom parse function overrides default behaviour
    const has_parse = comptime std.meta.hasFn(T, "cborDecode");
    if (has_parse) {
        return T.cborDecode(self);
    }

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

                var buffer: [max_key_len]u8 = undefined;
                const key: union(enum) { int: i65, str: []const u8 } = switch (key_.getType()) {
                    .Int => .{ .int = try key_.getInt() },
                    .ByteString, .TextString => .{ .str = try key_.getStringSlice(&buffer) },
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
    if (writer) |w| try w.writeAll(self.head[0..self.getHeaderLength()]);

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

fn encode_head(out: *std.Io.Writer, head: u8, v: u64) !void {
    switch (v) {
        0x00...0x17 => {
            try out.writeByte(head | @as(u8, @intCast(v)));
        },
        0x18...0xff => {
            try out.writeByte(head | 24);
            try out.writeByte(@as(u8, @intCast(v)));
        },
        0x0100...0xffff => try encode_head_2(out, head, v),
        0x00010000...0xffffffff => try encode_head_4(out, head, v),
        0x0000000100000000...0xffffffffffffffff => try encode_head_8(out, head, v),
    }
}

pub inline fn encode_head_2(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 25);
    try cbor.writeInt(u16, @as(u16, @intCast(v)), .big);
}

pub inline fn encode_head_4(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 26);
    try cbor.writeInt(u32, @as(u32, @intCast(v)), .big);
}

pub inline fn encode_head_8(cbor: anytype, head: u8, v: u64) !void {
    try cbor.writeByte(head | 27);
    try cbor.writeInt(u64, v, .big);
}

// ################################################################
// ###########            Encoding                #################
// ################################################################

pub const EncodeOptions = struct {
    allocator: ?std.mem.Allocator = null,
    /// What a enum value should be serialized to
    enum_serialization_type: SerializationType = .TextString,
    /// What a slice value should be serialized to
    slice_serialization_type: SerializationType = .ByteString,
    /// Whether an array should be serialized as definite or indefinite
    /// In the case of indefinite arrays, a break marker will be added after the array to signal the end of the array.
    array_serialization_type: ArraySerializationType = .ArrayDefinite,
    /// Wheter a map/struct should be serialized as a definite or indefinite CBOR map.
    /// In the case of a indefinite map, a break marker 0xff will be added after the
    /// map to signal the end.
    map_serialization_type: MapSerializationType = .MapDefinite,
};

pub const EncodeError = error{
    UnsupportedItem,
    InvalidPairCount,
    WriteFailed,
    OutOfMemory,
    BufferTooSmall,
};

pub fn encode(
    out: *std.Io.Writer,
    value: anytype,
    options: EncodeOptions,
) EncodeError!void {
    const T = @TypeOf(value);
    const TInf = @typeInfo(T);
    var head: u8 = 0;
    var v: u64 = 0;

    // I don't know if this is a good solution but it's
    // the easiest way to work around all the anyopaque
    // compiler errors. Makes no sense to serialize a
    // allocator but this allows storing a allocator
    // in a struct and then just skipping the field.
    if (T == std.mem.Allocator) return;

    const has_settings = comptime std.meta.hasFn(T, "cborSettings");
    const settings: Settings = if (has_settings) T.cborSettings() else .{};

    switch (TInf) {
        .int, .comptime_int => {
            head = if (value < 0) 0x20 else 0;
            v = @as(u64, @intCast(if (value < 0) -(value + 1) else value));
            try encode_head(out, head, v);
            return;
        },
        .float, .comptime_float => {
            head = 0xe0;
            switch (TInf) {
                .float => |float| {
                    switch (float.bits) {
                        16 => try encode_head_2(out, head, @as(u64, @intCast(@as(u16, @bitCast(value))))),
                        32 => try encode_head_4(out, head, @as(u64, @intCast(@as(u32, @bitCast(value))))),
                        64 => try encode_head_8(out, head, @as(u64, @intCast(@as(u64, @bitCast(value))))),
                        else => @compileError("Float must be 16, 32 or 64 Bits wide"),
                    }
                    return;
                },
                .comptime_float => {
                    // Comptime floats are always encoded as single precision floats
                    try encode_head_4(out, head, @as(u64, @intCast(@as(u32, @bitCast(@as(f32, @floatCast(value)))))));
                    return;
                },
                else => unreachable,
            }
        },
        .bool, .null => {
            head = 0xe0;
            v = switch (TInf) {
                .bool => if (value) 21 else 20,
                .null => 22,
                else => unreachable,
            };
            try encode_head(out, head, v);
            return;
        },
        .array => |arrayInfo| {
            if (arrayInfo.child == u8) {
                head = switch (options.slice_serialization_type) {
                    .TextString => blk: {
                        break :blk if (std.unicode.utf8ValidateSlice(value[0..])) 0x60 else 0x40;
                    },
                    // Otherwise it can only be ByteString or Integer (and Integer doesn't make sense in this context).
                    else => 0x40,
                };
            } else {
                if (options.array_serialization_type == .ArrayDefinite) {
                    head = 0x80;
                } else {
                    head = 0x9f;
                }
            }

            if (options.array_serialization_type == .ArrayDefinite) {
                // The length is only encoded for non indefinite length DIs.
                v = @as(u64, @intCast(value.len));
                try encode_head(out, head, v);
            } else {
                try out.writeByte(head);
            }

            if (arrayInfo.child == u8) {
                try out.writeAll(value[0..]);
            } else {
                for (value) |x| {
                    try encode(out, x, options);
                }
            }
            if (head == 0x9f and options.array_serialization_type == .ArrayIndefinite) {
                try out.writeByte(0xff);
            }
            return;
        },
        .@"struct" => |S| {
            // Custom encode function overrides default behaviour
            const has_encode = comptime std.meta.hasFn(T, "cborEncode");
            if (has_encode) {
                return value.cborEncode(out, options);
            }

            if (options.map_serialization_type == .MapDefinite) {
                head = 0xa0; // Struct becomes a Map.
            } else {
                head = 0xbf; // Struct becomes a indefinite-length map
            }

            // Count the number of fields that should be serialized
            inline for (0..S.field_names.len) |i| {
                const field_name = S.field_names[i];
                const field_type = S.field_types[i];

                // don't include void fields
                if (field_type == void) continue;

                var emit_field = true;

                var field_setting: ?FieldSettings = null;
                for (settings.field_settings) |fs| {
                    if (std.mem.eql(u8, field_name, fs.name)) {
                        field_setting = fs;
                    }
                }

                if (field_setting != null and field_setting.?.field_options.skip == .Skip) {
                    emit_field = false;
                }

                // dont't include (optional) null fields
                if (emit_field and @typeInfo(field_type) == .optional) {
                    if (((field_setting != null and field_setting.?.field_options.skip == .SkipIfNull) or field_setting == null) and @field(value, field_name) == null) {
                        emit_field = false;
                    }
                }

                if (emit_field) {
                    v += 1;
                }
            }

            if (options.map_serialization_type == .MapDefinite) {
                try encode_head(out, head, v);
            } else {
                try out.writeByte(head);
            }

            // Now serialize the actual fields
            inline for (0..S.field_names.len) |i| {
                const field_name = S.field_names[i];
                const field_type = S.field_types[i];

                // don't include void fields
                if (field_type == void) continue;

                var emit_field = true;
                var child_options = options;
                var name: []const u8 = field_name[0..];
                var name_st: SerializationType = .TextString;

                var field_setting: ?FieldSettings = null;
                for (settings.field_settings) |fs| {
                    if (std.mem.eql(u8, field_name, fs.name)) {
                        field_setting = fs;
                        break;
                    }
                }

                if (field_setting != null and field_setting.?.field_options.skip == .Skip) {
                    emit_field = false;
                }

                // dont't include (optional) null fields
                if (emit_field and @typeInfo(field_type) == .optional) {
                    if (((field_setting != null and field_setting.?.field_options.skip == .SkipIfNull) or field_setting == null) and @field(value, field_name) == null) {
                        emit_field = false;
                    }
                }

                if (field_setting != null) {
                    child_options.enum_serialization_type = field_setting.?.value_options.enum_serialization_type;
                    child_options.slice_serialization_type = field_setting.?.value_options.slice_serialization_type;
                    child_options.array_serialization_type = field_setting.?.value_options.array_serialization_type;
                    child_options.map_serialization_type = field_setting.?.value_options.map_serialization_type;

                    if (field_setting.?.field_options.alias) |alias| {
                        name = alias;
                    }

                    name_st = field_setting.?.field_options.serialization_type;
                }

                if (emit_field) {
                    const nr = s2n(name);
                    if (name_st == .Integer and nr != null) { // int key
                        try encode(out, nr.?, .{}); // key
                    } else { // str key
                        try encode(out, name, .{
                            .slice_serialization_type = name_st,
                        }); // key
                    }

                    try encode(out, @field(value, field_name), child_options); // value
                }
            }
            if (options.map_serialization_type == .MapIndefinite) try out.writeByte(0xff);
            return;
        },
        .optional => {
            if (value) |payload| {
                try encode(out, payload, options);
                return;
            } else {
                try encode(out, null, options);
                return;
            }
        },
        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => {
                if (ptr_info.child == u8) {
                    head = switch (options.slice_serialization_type) {
                        .TextString => blk: {
                            break :blk if (std.unicode.utf8ValidateSlice(value[0..])) 0x60 else 0x40;
                        },
                        // Otherwise it can only be ByteString or Integer (and Integer doesn't make sense in this context).
                        else => 0x40,
                    };
                } else {
                    if (options.array_serialization_type == .ArrayDefinite) {
                        head = 0x80;
                    } else {
                        head = 0x9f;
                    }
                }

                if (options.array_serialization_type == .ArrayDefinite) {
                    // The length is only encoded for non indefinite length DIs.
                    v = @as(u64, @intCast(value.len));
                    try encode_head(out, head, v);
                } else {
                    try out.writeByte(head);
                }

                if (ptr_info.child == u8) {
                    try out.writeAll(value);
                } else {
                    for (value) |x| {
                        try encode(out, x, options);
                    }
                }
                if (head == 0x9f and options.array_serialization_type == .ArrayIndefinite) {
                    try out.writeByte(0xff);
                }
                return;
            },
            .one => {
                try encode(out, value.*, options);
                return;
            },
            else => @compileError("Unable to encode type '" ++ @typeName(T) ++ "'"),
        },
        .@"enum" => |enumInfo| {
            if (options.enum_serialization_type == .TextString) {
                const tmp = @backingInt(value);
                inline for (enumInfo.field_names, enumInfo.field_values) |field_name, field_value| {
                    if (field_value == tmp) {
                        v = @as(u64, @intCast(field_name.len));
                        try encode_head(out, 0x60, v);
                        try out.writeAll(field_name);
                        return;
                    }
                }
            } else {
                const tmp = @backingInt(value);
                head = if (tmp < 0) 0x20 else 0;
                v = @as(u64, @intCast(if (tmp < 0) -(tmp + 1) else tmp));
                try encode_head(out, head, v);
                return;
            }
        },
        .@"union" => {
            // Custom encode function overrides default behaviour
            const has_encode = comptime std.meta.hasFn(T, "cborEncode");
            if (has_encode) {
                return value.cborEncode(out, options);
            }

            const info = @typeInfo(T).@"union";
            if (info.tag_type) |UnionTagType| {
                inline for (0..info.field_names.len) |i| {
                    const field_name = info.field_names[i];

                    if (value == @field(UnionTagType, field_name)) {
                        try encode(out, @field(value, field_name), options);
                        break;
                    }
                }
                return;
            } else {
                @compileError("Unable to encode untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        else => {
            return .UnsupportedItem;
        }, // TODO: add remaining options
    }
}

// ################################################################
// ###########         Encoding Primitives        #################
// ################################################################

/// Serialize an integer into a CBOR integer (major type 0 or 1).
pub fn writeInt(writer: *std.Io.Writer, value: i65) !void {
    const h: u8 = if (value < 0) 0x20 else 0;
    const v: u64 = @as(u64, @intCast(if (value < 0) -(value + 1) else value));
    try encode_head(writer, h, v);
}

/// Serialize a slice to a CBOR byte string (major type 2).
pub fn writeByteString(writer: *std.Io.Writer, value: []const u8) !void {
    const h: u8 = 0x40;
    const v: u64 = @as(u64, @intCast(value.len));
    try encode_head(writer, h, v);
    try writer.writeAll(value);
}

/// Serialize a slice to a CBOR text string (major type 3).
pub fn writeTextString(writer: *std.Io.Writer, value: []const u8) !void {
    const h: u8 = 0x60;
    const v: u64 = @as(u64, @intCast(value.len));
    try encode_head(writer, h, v);
    try writer.writeAll(value);
}

/// Serialize a tag.
///
/// You MUST serialize another data item right after calling this function.
pub fn writeTag(writer: *std.Io.Writer, tag: u64) !void {
    const h: u8 = 0xc0;
    const v: u64 = tag;
    try encode_head(writer, h, v);
}

/// Serialize a simple value.
pub fn writeSimple(writer: *std.Io.Writer, simple: u8) !void {
    if (24 <= simple and simple <= 31) return error.ReservedValue;
    const h: u8 = 0xe0;
    const v: u64 = @as(u64, @intCast(simple));
    try encode_head(writer, h, v);
}

pub fn writeTrue(writer: *std.Io.Writer) !void {
    try writeSimple(writer, 21);
}

pub fn writeFalse(writer: *std.Io.Writer) !void {
    try writeSimple(writer, 20);
}

pub fn writeFloat(writer: *std.Io.Writer, f: anytype) !void {
    const T = @TypeOf(f);
    const TInf = @typeInfo(T);

    switch (TInf) {
        .float => |float| {
            switch (float.bits) {
                16 => try encode_head_2(writer, 0xe0, @as(u64, @intCast(@as(u16, @bitCast(f))))),
                32 => try encode_head_4(writer, 0xe0, @as(u64, @intCast(@as(u32, @bitCast(f))))),
                64 => try encode_head_8(writer, 0xe0, @as(u64, @intCast(@as(u64, @bitCast(f))))),
                else => @compileError("Float must be 16, 32 or 64 Bits wide"),
            }
        },
        else => return error.NotAFloat,
    }
}

/// Write the header of an array to `writer`.
///
/// You must write exactly `len` data items to `writer` afterwards.
pub inline fn writeArray(writer: *std.Io.Writer, len: u64) !void {
    try encode_head(writer, 0x80, len);
}

pub inline fn writeArrayIndef(writer: *std.Io.Writer) !void {
    try writer.writeByte(0x9f);
}

/// Write the header of a map to `writer`.
///
/// You must write exactly `len` key-value pairs (data items) to `writer` afterwards.
pub inline fn writeMap(writer: *std.Io.Writer, len: u64) !void {
    try encode_head(writer, 0xa0, len);
}

pub inline fn writeMapIndef(writer: *std.Io.Writer) !void {
    try writer.writeByte(0xbf);
}

pub inline fn writeIndefBreak(writer: *std.Io.Writer) !void {
    try writer.writeByte(0xff);
}

// ################################################################
// ###########         Decoding Tests             #################
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

        var buffer: [1024]u8 = @splat(0);
        const value = try di.getStringSlice(&buffer);

        try std.testing.expectEqualSlices(u8, v.@"1", value);
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

test "skip with writer #1" {
    const s = "\x9f\x01\x02\x03\x04\x05\xff\x45\x01\x02\x03\x04\x05\x85\x01\xF6\x03\xF6\x05\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f";

    const e1 = "\x9f\x01\x02\x03\x04\x05\xff";
    const e2 = "\x45\x01\x02\x03\x04\x05";
    const e3 = "\x85\x01\xF6\x03\xF6\x05";
    const e4 = "\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B";
    const e5 = "\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4";
    const e6 = "\xa2\x64\x76\x61\x6c\x73\xa1\x67\x74\x65\x73\x74\x69\x6e\x67\x01\x66\x75\x70\x74\x69\x6d\x65\x19\x27\x0f";

    var reader = std.Io.Reader.fixed(s);

    var di1 = try Self.new(&reader);
    var w1 = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w1.deinit();
    try di1.skip(&w1.writer);
    try std.testing.expectEqualSlices(u8, e1, w1.written());

    var di2 = try di1.next();
    var w2 = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w2.deinit();
    try di2.skip(&w2.writer);
    try std.testing.expectEqualSlices(u8, e2, w2.written());

    var di3 = try di2.next();
    var w3 = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w3.deinit();
    try di3.skip(&w3.writer);
    try std.testing.expectEqualSlices(u8, e3, w3.written());

    var di4 = try di3.next();
    var w4 = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w4.deinit();
    try di4.skip(&w4.writer);
    try std.testing.expectEqualSlices(u8, e4, w4.written());

    var di5 = try di4.next();
    const v = try di5.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(v);
    try std.testing.expectEqualSlices(u8, e5, v);

    var di6 = try di5.next();
    var w6 = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w6.deinit();
    try di6.skip(&w6.writer);
    try std.testing.expectEqualSlices(u8, e6, w6.written());
}

test "decode union #1" {
    const ResponseTag = enum { ok, err };

    const Response = union(ResponseTag) {
        /// Slice containing the response message
        ok: []const u8,
        /// A CTAP status code
        err: u8,
    };

    const s1 = "\x65\x68\x65\x6C\x6C\x6F";
    var r1 = std.Io.Reader.fixed(s1);
    var di1 = try Self.new(&r1);
    const v1 = try di1.decode(Response, .{ .allocator = std.testing.allocator });
    defer std.testing.allocator.free(v1.ok);
    try std.testing.expectEqualSlices(u8, "hello", v1.ok);

    const s2 = "\x18\x40";
    var r2 = std.Io.Reader.fixed(s2);
    var di2 = try Self.new(&r2);
    const v2 = try di2.decode(Response, .{ .allocator = std.testing.allocator });
    try std.testing.expectEqual(@as(u8, 64), v2.err);
}

test "deserialize EcdsP256Key using alias 2" {
    const EcdsaP256Key = struct {
        /// kty:
        kty: u8 = 2,
        /// alg:
        alg: i8 = -7,
        /// crv:
        crv: u8 = 1,
        /// x-coordinate
        x: [32]u8,
        /// y-coordinate
        y: [32]u8,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "kty", .field_options = .{ .alias = "1", .serialization_type = .Integer } },
                    .{ .name = "alg", .field_options = .{ .alias = "3", .serialization_type = .Integer } },
                    .{ .name = "crv", .field_options = .{ .alias = "-1", .serialization_type = .Integer } },
                    .{ .name = "x", .field_options = .{ .alias = "-2", .serialization_type = .Integer } },
                    .{ .name = "y", .field_options = .{ .alias = "-3", .serialization_type = .Integer } },
                },
            };
        }
    };

    var r = std.Io.Reader.fixed("\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52");
    var di = try Self.new(&r);

    const x = try di.decode(EcdsaP256Key, .{});

    try std.testing.expectEqual(@as(u8, @intCast(2)), x.kty);
    try std.testing.expectEqual(@as(i8, @intCast(-7)), x.alg);
    try std.testing.expectEqual(@as(u8, @intCast(1)), x.crv);
    try std.testing.expectEqualSlices(u8, "\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e", &x.x);
    try std.testing.expectEqualSlices(u8, "\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", &x.y);
}

test "parse get assertion request 1" {
    const GetAssertionParam = struct {
        rpId: [:0]const u8,
        clientDataHash: []const u8,
        allowList: ?[]const struct {
            id: []const u8,
            type: [:0]const u8,
            transports: ?[]const [:0]const u8 = null,
        } = null,
        options: ?struct {
            up: bool = true,
            rk: bool = true,
            uv: bool = false,
        } = null,
        pinUvAuthParam: ?[32]u8 = null,
        pinUvAuthProtocol: ?u8 = null,

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.rpId);
            allocator.free(self.clientDataHash);
            if (self.allowList) |pkcds| {
                for (pkcds) |pkcd| {
                    allocator.free(pkcd.id);
                    allocator.free(pkcd.type);
                    if (pkcd.transports) |trans| {
                        for (trans) |t| {
                            allocator.free(t);
                        }
                        allocator.free(trans);
                    }
                }
                allocator.free(pkcds);
            }
        }

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "rpId", .field_options = .{ .alias = "1", .serialization_type = .Integer } },
                    .{ .name = "clientDataHash", .field_options = .{ .alias = "2", .serialization_type = .Integer } },
                    .{ .name = "allowList", .field_options = .{ .alias = "3", .serialization_type = .Integer } },
                    .{ .name = "options", .field_options = .{ .alias = "5", .serialization_type = .Integer } },
                    .{ .name = "pinUvAuthParam", .field_options = .{ .alias = "6", .serialization_type = .Integer } },
                    .{ .name = "pinUvAuthProtocol", .field_options = .{ .alias = "7", .serialization_type = .Integer } },
                },
            };
        }
    };

    const allocator = std.testing.allocator;

    // {1: "webauthn.io", 2: h'6E0CB5F97CAEB8BF797A6214C7191C808FE5A55021F9FB766E8183CD8A0D550B', 3: [{"id": h'F9FFFFFF95EA72742FA603C3519F9C17C0FF81C45DBB46E23CFF6FC1D0D5B3646D495CB11B80E57888BFBAE3898D6985FC196C43FDFC2E8018AC2D5BB379A1F0', "type": "public-key"}], 5: {"up": false}, 6: h'305B382D1CD9B9714D519830E5B002CB6C3825BC05F87EF1BCDA364D2D4DB910', 7: 2}
    const payload = "\xa6\x01\x6b\x77\x65\x62\x61\x75\x74\x68\x6e\x2e\x69\x6f\x02\x58\x20\x6e\x0c\xb5\xf9\x7c\xae\xb8\xbf\x79\x7a\x62\x14\xc7\x19\x1c\x80\x8f\xe5\xa5\x50\x21\xf9\xfb\x76\x6e\x81\x83\xcd\x8a\x0d\x55\x0b\x03\x81\xa2\x62\x69\x64\x58\x40\xf9\xff\xff\xff\x95\xea\x72\x74\x2f\xa6\x03\xc3\x51\x9f\x9c\x17\xc0\xff\x81\xc4\x5d\xbb\x46\xe2\x3c\xff\x6f\xc1\xd0\xd5\xb3\x64\x6d\x49\x5c\xb1\x1b\x80\xe5\x78\x88\xbf\xba\xe3\x89\x8d\x69\x85\xfc\x19\x6c\x43\xfd\xfc\x2e\x80\x18\xac\x2d\x5b\xb3\x79\xa1\xf0\x64\x74\x79\x70\x65\x6a\x70\x75\x62\x6c\x69\x63\x2d\x6b\x65\x79\x05\xa1\x62\x75\x70\xf4\x06\x58\x20\x30\x5b\x38\x2d\x1c\xd9\xb9\x71\x4d\x51\x98\x30\xe5\xb0\x02\xcb\x6c\x38\x25\xbc\x05\xf8\x7e\xf1\xbc\xda\x36\x4d\x2d\x4d\xb9\x10\x07\x02";

    var r = std.Io.Reader.fixed(payload);
    var di = try Self.new(&r);

    const get_assertion_param = try di.decode(
        GetAssertionParam,
        .{ .allocator = allocator },
    );
    defer get_assertion_param.deinit(allocator);

    try std.testing.expectEqual(false, get_assertion_param.options.?.up);
    try std.testing.expectEqualSlices(u8, "webauthn.io", get_assertion_param.rpId);
    try std.testing.expectEqualSlices(u8, "\x6e\x0c\xb5\xf9\x7c\xae\xb8\xbf\x79\x7a\x62\x14\xc7\x19\x1c\x80\x8f\xe5\xa5\x50\x21\xf9\xfb\x76\x6e\x81\x83\xcd\x8a\x0d\x55\x0b", get_assertion_param.clientDataHash);
    try std.testing.expectEqualSlices(u8, "\xf9\xff\xff\xff\x95\xea\x72\x74\x2f\xa6\x03\xc3\x51\x9f\x9c\x17\xc0\xff\x81\xc4\x5d\xbb\x46\xe2\x3c\xff\x6f\xc1\xd0\xd5\xb3\x64\x6d\x49\x5c\xb1\x1b\x80\xe5\x78\x88\xbf\xba\xe3\x89\x8d\x69\x85\xfc\x19\x6c\x43\xfd\xfc\x2e\x80\x18\xac\x2d\x5b\xb3\x79\xa1\xf0", get_assertion_param.allowList.?[0].id);
}

test "assign allocator to allocator fields #1" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: []u8,
        b: std.mem.Allocator,
    };

    var r = std.Io.Reader.fixed("\xa1\x61\x61\x65\x61\x62\x63\x64\x65");
    var di = try Self.new(&r);

    const x = try di.decode(S, .{ .allocator = allocator });
    defer allocator.free(x.a);

    try std.testing.expectEqualSlices(u8, "abcde", x.a);
}

test "parse indefinite-length map {_ 'a': 1, 'b': [_ 2, 3]}" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: u16,
        b: []const u8,
    };

    var r = std.Io.Reader.fixed("\xbf\x61\x61\x01\x61\x62\x9f\x02\x03\xff\xff");
    var di = try Self.new(&r);

    const s = try di.decode(S, .{ .allocator = allocator });
    defer allocator.free(s.b);

    try std.testing.expectEqual(@as(u16, 1), s.a);
    try std.testing.expectEqualSlices(u8, &.{ 2, 3 }, s.b);
}

test "parse indefinite-length map {_ 'Fun': true, 'Amt': -2}" {
    const S = struct {
        Fun: bool,
        Amt: i16,
    };

    var r = std.Io.Reader.fixed("\xbf\x63\x46\x75\x6e\xf5\x63\x41\x6d\x74\x21\xff");
    var di = try Self.new(&r);

    const s = try di.decode(S, .{});

    try std.testing.expectEqual(true, s.Fun);
    try std.testing.expectEqual(@as(i16, -2), s.Amt);
}

test "parse indefinite-length map {_ 'a': 1, 'b': {_ 'c': 2, 'd': 3}, 'e': 'hello'}" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: u8,
        b: struct {
            c: u8,
            d: u8,
        },
        e: []const u8,
    };

    const raw = "\xbf\x61\x61\x01\x61\x62\xbf\x61\x63\x02\x61\x64\x03\xff\x61\x65\x65\x68\x65\x6c\x6c\x6f\xff";

    var r = std.Io.Reader.fixed(raw);
    var di = try Self.new(&r);

    const s = try di.decode(
        S,
        .{ .allocator = allocator },
    );
    defer allocator.free(s.e);

    try std.testing.expectEqual(@as(u8, 1), s.a);
    try std.testing.expectEqual(@as(u8, 2), s.b.c);
    try std.testing.expectEqual(@as(u8, 3), s.b.d);
    try std.testing.expectEqualSlices(u8, "hello", s.e);
}

test "parse array indefinite: 3, we want more than is present" {
    var r = std.Io.Reader.fixed("\x9f\x01\x02\x03\xff");
    var di = try Self.new(&r);

    // We expect five items, but the indefinite array contains three.
    try std.testing.expectError(DecodeError.EndOfStream, di.decode([5]u8, .{}));
}

test "parse array from string: length must match" {
    var r1 = std.Io.Reader.fixed("\x43\x01\x02\x03");
    var di1 = try Self.new(&r1);
    try std.testing.expectEqualSlices(u8, "\x01\x02\x03", &(try di1.decode([3]u8, .{})));

    var r2 = std.Io.Reader.fixed("\x63abc");
    var di2 = try Self.new(&r2);
    try std.testing.expectEqualSlices(u8, "abc", &(try di2.decode([3]u8, .{})));

    //try std.testing.expectError(ParseError.Overflow, parse([3]u8, try DataItem.new("\x44\x01\x02\x03\x04"), .{}));
    //try std.testing.expectError(ParseError.Malformed, parse([3]u8, try DataItem.new("\x42\x01\x02"), .{}));
    //try std.testing.expectError(ParseError.Malformed, parse([3]u8, try DataItem.new("\x40"), .{}));
    //try std.testing.expectError(ParseError.Malformed, parse([3]u8, try DataItem.new("\x62ab"), .{}));
}

test "recursion #1" {}

// ################################################################
// ###########         Encoding Tests             #################
// ################################################################

fn testStringify(e: []const u8, v: anytype, o: EncodeOptions) !void {
    const allocator = std.testing.allocator;
    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try encode(&str.writer, v, o);
    try std.testing.expectEqualSlices(u8, e, str.written());
}

test "encode float" {
    try testStringify("\xf9\x00\x00", @as(f16, @floatCast(0.0)), .{});
    try testStringify("\xf9\x80\x00", @as(f16, @floatCast(-0.0)), .{});
    try testStringify("\xf9\x3c\x00", @as(f16, @floatCast(1.0)), .{});
    try testStringify("\xf9\x3e\x00", @as(f16, @floatCast(1.5)), .{});
    try testStringify("\xf9\x7b\xff", @as(f16, @floatCast(65504.0)), .{});
    try testStringify("\xfa\x47\xc3\x50\x00", @as(f32, @floatCast(100000.0)), .{});
    try testStringify("\xfa\x7f\x7f\xff\xff", @as(f32, @floatCast(3.4028234663852886e+38)), .{});
    try testStringify("\xfb\x7e\x37\xe4\x3c\x88\x00\x75\x9c", @as(f64, @floatCast(1.0e+300)), .{});
    try testStringify("\xfb\xc0\x10\x66\x66\x66\x66\x66\x66", @as(f64, @floatCast(-4.1)), .{});

    try testStringify("\xfa\x47\xc3\x50\x00", 100000.0, .{});
}

test "encode int" {
    try testStringify("\x00", 0, .{});
    try testStringify("\x01", 1, .{});
    try testStringify("\x0a", 10, .{});
    try testStringify("\x17", 23, .{});
    try testStringify("\x18\x18", 24, .{});
    try testStringify("\x18\x19", 25, .{});
    try testStringify("\x18\x64", 100, .{});
    try testStringify("\x18\x7b", 123, .{});
    try testStringify("\x19\x03\xe8", 1000, .{});
    try testStringify("\x19\x04\xd2", 1234, .{});
    try testStringify("\x1a\x00\x01\xe2\x40", 123456, .{});
    try testStringify("\x1a\x00\x0f\x42\x40", 1000000, .{});
    try testStringify("\x1b\x00\x00\x00\x02\xdf\xdc\x1c\x34", 12345678900, .{});
    try testStringify("\x1b\x00\x00\x00\xe8\xd4\xa5\x10\x00", 1000000000000, .{});
    try testStringify("\x1b\xff\xff\xff\xff\xff\xff\xff\xff", 18446744073709551615, .{});

    try testStringify("\x20", -1, .{});
    try testStringify("\x22", -3, .{});
    try testStringify("\x38\x63", -100, .{});
    try testStringify("\x39\x01\xf3", -500, .{});
    try testStringify("\x39\x03\xe7", -1000, .{});
    try testStringify("\x3a\x00\x0f\x3d\xdc", -998877, .{});
    try testStringify("\x3b\x00\x00\x00\x02\x53\x60\xa2\xce", -9988776655, .{});
    try testStringify("\x3b\xff\xff\xff\xff\xff\xff\xff\xff", -18446744073709551616, .{});
}

test "encode optional value" {
    const e1: ?u32 = 1234;
    const e2: ?u32 = null;

    try testStringify("\xf6", e2, .{});
    try testStringify("\x19\x04\xd2", e1, .{});
}

test "encode to fixed writer" {
    var array: [3]u8 = undefined;
    var writer = std.Io.Writer.fixed(&array);
    const value: i16 = -32700;
    const expected: []const u8 = &.{ 0x39, 0x7f, 0xbb };
    try encode(&writer, value, .{});
    try std.testing.expectEqualSlices(u8, expected, writer.buffered());
}

test "encode simple value" {
    try testStringify("\xf4", false, .{});
    try testStringify("\xf5", true, .{});
    try testStringify("\xf6", null, .{});
}

test "encode pointer" {
    const x1: u32 = 1234;
    const x1p: *const u32 = &x1;
    const x2: i65 = -18446744073709551616; // this is -2^64
    const x2p: *const i65 = &x2;

    try testStringify("\x19\x04\xd2", x1p, .{});
    try testStringify("\x3b\xff\xff\xff\xff\xff\xff\xff\xff", x2p, .{});
}

test "encode slice" {
    const s1: []const u8 = "a";
    try testStringify("\x61\x61", s1, .{ .slice_serialization_type = .TextString });

    const s2: []const u8 = "IETF";
    try testStringify("\x64\x49\x45\x54\x46", s2, .{ .slice_serialization_type = .TextString });

    const s3: []const u8 = "\"\\";
    try testStringify("\x62\x22\x5c", s3, .{ .slice_serialization_type = .TextString });

    const b1: []const u8 = &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 };
    try testStringify(&.{ 0x58, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19 }, b1, .{ .slice_serialization_type = .ByteString });

    const b2: []const u8 = "\x10\x11\x12\x13\x14";
    try testStringify("\x45\x10\x11\x12\x13\x14", b2, .{ .slice_serialization_type = .ByteString });
}

test "encode struct: 1" {
    const Info = struct {
        versions: []const []const u8,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{
                        .name = "versions",
                        .value_options = .{ .slice_serialization_type = .TextString },
                    },
                },
            };
        }
    };

    const i = Info{
        .versions = &.{"FIDO_2_0"},
    };

    try testStringify("\xa1\x68\x76\x65\x72\x73\x69\x6f\x6e\x73\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
}

test "encode struct: 2" {
    const Info = struct {
        @"1": []const []const u8,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{
                        .name = "1",
                        .field_options = .{ .serialization_type = .Integer },
                        .value_options = .{ .slice_serialization_type = .TextString },
                    },
                },
            };
        }
    };

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
    };

    try testStringify("\xa1\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30", i, .{});
}

test "encode struct: 3" {
    const Info = struct {
        @"1": []const []const u8,
        @"2": []const []const u8,
        @"3": []const u8,

        pub fn cborSettings() Settings {
            return .{ .field_settings = &.{
                .{ .name = "1", .field_options = .{ .serialization_type = .Integer }, .value_options = .{ .slice_serialization_type = .TextString } },
                .{ .name = "2", .field_options = .{ .serialization_type = .Integer }, .value_options = .{ .slice_serialization_type = .TextString } },
                .{ .name = "3", .field_options = .{ .serialization_type = .Integer }, .value_options = .{} },
            } };
        }
    };

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
        .@"2" = &.{},
        .@"3" = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    };

    try testStringify("\xa3\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f", i, .{});
}

test "encode struct: 4" {
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

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "1", .field_options = .{ .serialization_type = .Integer }, .value_options = .{ .slice_serialization_type = .TextString } },
                    .{ .name = "2", .field_options = .{ .serialization_type = .Integer }, .value_options = .{ .slice_serialization_type = .TextString } },
                    .{ .name = "3", .field_options = .{ .serialization_type = .Integer }, .value_options = .{} },
                    .{ .name = "4", .field_options = .{ .serialization_type = .Integer }, .value_options = .{} },
                    .{ .name = "5", .field_options = .{ .serialization_type = .Integer }, .value_options = .{} },
                    .{ .name = "6", .field_options = .{ .serialization_type = .Integer }, .value_options = .{} },
                },
            };
        }
    };

    const i = Info{
        .@"1" = &.{"FIDO_2_0"},
        .@"2" = &.{},
        .@"3" = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
        .@"4" = .{
            .plat = true,
            .rk = true,
            .clientPin = null,
            .up = true,
            .uv = false,
        },
        .@"5" = null,
        .@"6" = null,
    };

    try testStringify("\xa4\x01\x81\x68\x46\x49\x44\x4f\x5f\x32\x5f\x30\x02\x80\x03\x50\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x04\xa4\x64\x70\x6c\x61\x74\xf5\x62\x72\x6b\xf5\x62\x75\x70\xf5\x62\x75\x76\xf4", i, .{});
}

test "encode struct: 5" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const Info = struct {
        x: Level,
        y: Level,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "y", .value_options = .{ .enum_serialization_type = .Integer } },
                },
            };
        }
    };

    const x = Info{
        .x = Level.high,
        .y = Level.low,
    };

    try testStringify("\xA2\x61\x78\x64\x68\x69\x67\x68\x61\x79\x0B", x, .{});
}

test "encode enum: 1" {
    const Level = enum(u8) {
        high = 7,
        low = 11,
    };

    const high = Level.high;
    const low = Level.low;

    try testStringify("\x07", high, .{ .enum_serialization_type = .Integer });
    try testStringify("\x0b", low, .{ .enum_serialization_type = .Integer });

    try testStringify("\x64\x68\x69\x67\x68", Level.high, .{});
    try testStringify("\x63\x6C\x6F\x77", Level.low, .{});
}

test "encode enum: 2" {
    const Level = enum(i8) {
        high = -7,
        low = -11,
    };

    try testStringify("\x26", Level.high, .{ .enum_serialization_type = .Integer });
    try testStringify("\x2a", Level.low, .{ .enum_serialization_type = .Integer });
}

test "encode array: definite and indefinite" {
    const array1 = [_]u16{ 500, 2 };
    try testStringify("\x82\x19\x01\xf4\x02", array1, .{ .array_serialization_type = .ArrayDefinite });
    try testStringify("\x9f\x19\x01\xf4\x02\xff", array1, .{ .array_serialization_type = .ArrayIndefinite });

    const array2 = [_]u16{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 };
    try testStringify("\x9f\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19\x18\x1a\x18\x1b\x18\x1c\x18\x1d\x18\x1e\x18\x1f\xff", array2, .{ .array_serialization_type = .ArrayIndefinite });

    const slice1: []const u32 = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
    try testStringify("\x9f\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x18\x18\x19\xff", slice1, .{ .array_serialization_type = .ArrayIndefinite });

    const slice2: []const u32 = &.{};
    try testStringify("\x9f\xff", slice2, .{ .array_serialization_type = .ArrayIndefinite });

    const nested = [2][2]u16{ .{ 500, 2 }, .{ 500, 7 } };
    try testStringify("\x82\x82\x19\x01\xf4\x02\x82\x19\x01\xf4\x07", nested, .{ .array_serialization_type = .ArrayDefinite });
    try testStringify("\x9f\x9f\x19\x01\xf4\x02\xff\x9f\x19\x01\xf4\x07\xff\xff", nested, .{ .array_serialization_type = .ArrayIndefinite });
}

test "serialize EcdsaP256Key" {
    const EcdsaP256 = std.crypto.sign.ecdsa.EcdsaP256Sha256;

    const EcdsaP256Key = struct {
        /// kty:
        kty: u8 = 2,
        /// alg:
        alg: i8 = -7,
        /// crv:
        crv: u8 = 1,
        /// x-coordinate
        x: [32]u8,
        /// y-coordinate
        y: [32]u8,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "kty", .field_options = .{ .alias = "1", .serialization_type = .Integer } },
                    .{ .name = "alg", .field_options = .{ .alias = "3", .serialization_type = .Integer } },
                    .{ .name = "crv", .field_options = .{ .alias = "-1", .serialization_type = .Integer } },
                    .{ .name = "x", .field_options = .{ .alias = "-2", .serialization_type = .Integer } },
                    .{ .name = "y", .field_options = .{ .alias = "-3", .serialization_type = .Integer } },
                },
            };
        }

        pub fn new(k: EcdsaP256.PublicKey) @This() {
            const xy = k.toUncompressedSec1();
            return .{
                .x = xy[1..33].*,
                .y = xy[33..65].*,
            };
        }
    };

    const k = EcdsaP256Key.new(try EcdsaP256.PublicKey.fromSec1("\x04\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52"));

    const allocator = std.testing.allocator;
    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try encode(&str.writer, k, .{});

    try std.testing.expectEqualSlices(u8, "\xa5\x01\x02\x03\x26\x20\x01\x21\x58\x20\xd9\xf4\xc2\xa3\x52\x13\x6f\x19\xc9\xa9\x5d\xa8\x82\x4a\xb5\xcd\xc4\xd5\x63\x1e\xbc\xfd\x5b\xdb\xb0\xbf\xff\x25\x36\x09\x12\x9e\x22\x58\x20\xef\x40\x4b\x88\x07\x65\x57\x60\x07\x88\x8a\x3e\xd6\xab\xff\xb4\x25\x7b\x71\x23\x55\x33\x25\xd4\x50\x61\x3c\xb5\xbc\x9a\x3a\x52", str.written());
}

test "serialize tagged union: 1" {
    const AttStmtTag = enum { none };
    const AttStmt = union(AttStmtTag) {
        none: struct {},
    };

    const a = AttStmt{ .none = .{} };

    try testStringify("\xa0", a, .{});
}

test "overload struct 1" {
    const Foo = struct {
        x: u32 = 1234,
        y: struct {
            a: []const u8 = "public-key",
            b: u64 = 0x1122334455667788,

            pub fn cborSettings() Settings {
                return .{
                    .field_settings = &.{
                        .{ .name = "a", .value_options = .{ .slice_serialization_type = .TextString } },
                    },
                };
            }
        },

        pub fn cborEncode(self: *const @This(), out: *std.Io.Writer, options: EncodeOptions) !void {
            _ = options;

            // First encode the 'y' struct
            const allocator = std.testing.allocator;
            var o = std.Io.Writer.Allocating.init(allocator);
            defer o.deinit();
            try encode(
                &o.writer,
                self.y,
                .{},
            );

            try writeMap(out, 2);
            {
                try writeTextString(out, "x");
                try writeInt(out, @intCast(self.x));

                try writeTextString(out, "y");
                try writeByteString(out, o.written());
            }
        }
    };

    const x = Foo{ .y = .{} };
    try testStringify("\xa2\x61\x78\x19\x04\xd2\x61\x79\x58\x19\xa2\x61\x61\x6a\x70\x75\x62\x6c\x69\x63\x2d\x6b\x65\x79\x61\x62\x1b\x11\x22\x33\x44\x55\x66\x77\x88", x, .{});
}

test "skip serializing field #1" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: i32,
        b: bool,
        c: [5]u8,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "b", .field_options = .{ .skip = .Skip } },
                    .{ .name = "c", .value_options = .{ .slice_serialization_type = .TextString } },
                },
            };
        }
    };

    const s = S{
        .a = 32,
        .b = true,
        .c = "abcde".*,
    };

    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try encode(&str.writer, s, .{});

    try std.testing.expectEqualSlices(u8, "\xa2\x61\x61\x18\x20\x61\x63\x65\x61\x62\x63\x64\x65", str.written());
}

test "skip serializing field #2" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: []u8,
        b: std.mem.Allocator,

        pub fn cborSettings() Settings {
            return .{
                .field_settings = &.{
                    .{ .name = "a", .value_options = .{ .slice_serialization_type = .TextString } },
                    .{ .name = "b", .field_options = .{ .skip = .Skip } },
                },
            };
        }
    };

    const s = S{
        .a = try allocator.alloc(u8, 5),
        .b = allocator,
    };
    @memcpy(s.a, "abcde");
    defer allocator.free(s.a);

    var str = std.Io.Writer.Allocating.init(allocator);
    defer str.deinit();

    try encode(&str.writer, s, .{});

    try std.testing.expectEqualSlices(u8, "\xa1\x61\x61\x65\x61\x62\x63\x64\x65", str.written());
}

test "serialize indefinite-length map {_ 'a': 1, 'b': [_ 2, 3]}" {
    const allocator = std.testing.allocator;

    const S = struct {
        a: u16,
        b: []const u16,
    };

    const s = S{
        .a = 1,
        .b = &.{ 2, 3 },
    };

    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try encode(
        &arr.writer,
        s,
        .{
            .allocator = allocator,
            .map_serialization_type = .MapIndefinite,
            .array_serialization_type = .ArrayIndefinite,
        },
    );

    try std.testing.expectEqualSlices(u8, "\xbf\x61\x61\x01\x61\x62\x9f\x02\x03\xff\xff", arr.written());
}

test "serialize indefinite-length map {_ 'Fun': true, 'Amt': -2}" {
    const allocator = std.testing.allocator;

    const S = struct {
        Fun: bool,
        Amt: i16,
    };

    const s = S{
        .Fun = true,
        .Amt = -2,
    };

    var arr = std.Io.Writer.Allocating.init(allocator);
    defer arr.deinit();

    try encode(
        &arr.writer,
        s,
        .{
            .allocator = allocator,
            .map_serialization_type = .MapIndefinite,
        },
    );

    try std.testing.expectEqualSlices(u8, "\xbf\x63\x46\x75\x6e\xf5\x63\x41\x6d\x74\x21\xff", arr.written());
}

const tests = @import("tests.zig");

test {
    _ = tests;
}
