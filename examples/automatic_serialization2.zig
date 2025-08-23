const std = @import("std");
const cbor = @import("zbor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var original_msg = Message.new("stack_id", "hello", "there");

    // serialize the message
    var bytes = std.array_list.Managed(u8).init(allocator);
    defer bytes.deinit();

    original_msg.headers.token = "my cool client token that totally is awesome";
    try original_msg.cborStringify(.{}, bytes.writer());

    const expected = "\xa5\x00\x68\x73\x74\x61\x63\x6b\x5f\x69\x64\x01\x00\x02\x65\x68\x65\x6c\x6c\x6f\x03\x65\x74\x68\x65\x72\x65\x05\xa1\x00\x78\x2c\x6d\x79\x20\x63\x6f\x6f\x6c\x20\x63\x6c\x69\x65\x6e\x74\x20\x74\x6f\x6b\x65\x6e\x20\x74\x68\x61\x74\x20\x74\x6f\x74\x61\x6c\x6c\x79\x20\x69\x73\x20\x61\x77\x65\x73\x6f\x6d\x65";
    if (!std.mem.eql(u8, expected, bytes.items)) {
        std.log.err("serialization failure! expected '{x}' but got '{x}'", .{
            expected,
            bytes.items,
        });
    }

    const di: cbor.DataItem = try cbor.DataItem.new(bytes.items);
    const parsed_msg = try Message.cborParse(di, .{ .allocator = allocator });

    std.debug.print("msg {any}\n", .{parsed_msg});
}

pub const MessageType = enum(u8) {
    Undefined,
};

pub const Message = struct {
    const Self = @This();

    id: []const u8,
    message_type: u8,
    topic: []const u8,
    content: ?[]const u8 = null,
    tx_id: ?[]const u8 = null,
    headers: Headers,

    // return a stack Message
    pub fn new(id: []const u8, topic: []const u8, content: []const u8) Message {
        return Message{
            .id = id,
            .topic = topic,
            .message_type = @intFromEnum(MessageType.Undefined),
            .content = content,
            .tx_id = null,
            .headers = Headers.new(null),
        };
    }

    // return a heap Message
    pub fn create(allocator: std.mem.Allocator, id: []const u8, topic: []const u8, content: []const u8) !*Message {
        const ptr = try allocator.create(Message);
        ptr.* = Message.new(id, topic, content);

        return ptr;
    }

    pub fn cborStringify(self: Self, o: cbor.Options, out: anytype) !void {
        try cbor.stringify(self, .{
            .ignore_override = true,
            .field_settings = &.{
                .{
                    .name = "id", // the name of the affected struct field
                    .field_options = .{ .alias = "0", .serialization_type = .Integer }, // replace "id" with "0" and treat "0" as an integer
                    .value_options = .{ .slice_serialization_type = .TextString }, // serialize the value of "id" as text string (major type 3)
                },
                .{
                    .name = "message_type",
                    .field_options = .{ .alias = "1", .serialization_type = .Integer },
                },
                .{
                    .name = "topic",
                    .field_options = .{ .alias = "2", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "content",
                    .field_options = .{ .alias = "3", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "tx_id",
                    .field_options = .{ .alias = "4", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "headers",
                    .field_options = .{ .alias = "5", .serialization_type = .Integer },
                },
            },
            .allocator = o.allocator,
        }, out);
    }

    pub fn cborParse(item: cbor.DataItem, o: cbor.Options) !Self {
        return try cbor.parse(Self, item, .{
            .ignore_override = true, // prevent infinite loops
            .field_settings = &.{
                .{
                    .name = "id", // the name of the affected struct field
                    .field_options = .{ .alias = "0", .serialization_type = .Integer }, // replace "id" with "0" and treat "0" as an integer
                    .value_options = .{ .slice_serialization_type = .TextString }, // serialize the value of "id" as text string (major type 3)
                },
                .{
                    .name = "message_type",
                    .field_options = .{ .alias = "1", .serialization_type = .Integer },
                },
                .{
                    .name = "topic",
                    .field_options = .{ .alias = "2", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "content",
                    .field_options = .{ .alias = "3", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "tx_id",
                    .field_options = .{ .alias = "4", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
                .{
                    .name = "headers",
                    .field_options = .{ .alias = "5", .serialization_type = .Integer },
                },
            },
            .allocator = o.allocator,
        });
    }
};

pub const Headers = struct {
    const Self = @This();

    token: ?[]const u8,

    pub fn new(token: ?[]const u8) Self {
        return Headers{
            .token = token,
        };
    }

    pub fn create(allocator: std.mem.Allocator, token: ?[]const u8) !*Self {
        const ptr = try allocator.create(Headers);
        ptr.* = Headers.new(token);

        return ptr;
    }

    pub fn cborStringify(self: Self, o: cbor.Options, out: anytype) !void {
        try cbor.stringify(self, .{
            .ignore_override = true,
            .field_settings = &.{
                .{
                    .name = "token",
                    .field_options = .{ .alias = "0", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
            },
            .allocator = o.allocator,
        }, out);
    }

    pub fn cborParse(item: cbor.DataItem, o: cbor.Options) !Self {
        return try cbor.parse(Self, item, .{
            .ignore_override = true, // prevent infinite loops
            .field_settings = &.{
                .{
                    .name = "token",
                    .field_options = .{ .alias = "0", .serialization_type = .Integer },
                    .value_options = .{ .slice_serialization_type = .TextString },
                },
            },
            .allocator = o.allocator,
        });
    }
};
