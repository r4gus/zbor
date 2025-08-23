const std = @import("std");
const zbor = @import("zbor");

const User = struct {
    id: []const u8,
    name: []const u8,
    displayName: []const u8,

    pub fn cborStringify(self: *const @This(), options: zbor.Options, out: anytype) !void {
        return zbor.stringify(self, .{
            .allocator = options.allocator,
            .ignore_override = true,
            .field_settings = &.{
                .{ .name = "id", .value_options = .{ .slice_serialization_type = .ByteString } },
                .{ .name = "name", .value_options = .{ .slice_serialization_type = .TextString } },
                .{ .name = "displayName", .value_options = .{ .slice_serialization_type = .TextString } },
            },
        }, out);
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

pub fn main() !void {
    const user = User{
        .id = "\x01\x23\x45\x67",
        .name = "bob@example.com",
        .displayName = "Bob",
    };

    const expected = "\xa3\x62\x69\x64\x44\x01\x23\x45\x67\x64\x6e\x61\x6d\x65\x6f\x62\x6f\x62\x40\x65\x78\x61\x6d\x70\x6c\x65\x2e\x63\x6f\x6d\x6b\x64\x69\x73\x70\x6c\x61\x79\x4e\x61\x6d\x65\x63\x42\x6f\x62";

    var di = std.array_list.Managed(u8).init(allocator);
    defer di.deinit();
    const writer = di.writer();

    try zbor.stringify(user, .{}, writer);

    try stdout.print("expected: {x}\ngot: {x}\nmatches: {any}\n", .{
        expected,
        di.items,
        std.mem.eql(u8, expected, di.items),
    });

    try stdout.flush();
}
