const std = @import("std");
const zbor = @import("zbor");

const User = struct {
    id: []const u8,
    name: []const u8,
    displayName: []const u8,
};

var gpa = std.heap.DebugAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main(init: std.process.Init) !void {
    const user = User{
        .id = "\x01\x23\x45\x67",
        .name = "bob@example.com",
        .displayName = "Bob",
    };

    const expected = "\xa3\x62\x69\x64\x44\x01\x23\x45\x67\x64\x6e\x61\x6d\x65\x6f\x62\x6f\x62\x40\x65\x78\x61\x6d\x70\x6c\x65\x2e\x63\x6f\x6d\x6b\x64\x69\x73\x70\x6c\x61\x79\x4e\x61\x6d\x65\x63\x42\x6f\x62";

    var di = std.Io.Writer.Allocating.init(allocator);
    defer di.deinit();
    const writer = &di.writer;

    try zbor.DataItem.writeMap(writer, 3);
    try zbor.DataItem.writeTextString(writer, "id");
    try zbor.DataItem.writeByteString(writer, user.id);
    try zbor.DataItem.writeTextString(writer, "name");
    try zbor.DataItem.writeTextString(writer, user.name);
    try zbor.DataItem.writeTextString(writer, "displayName");
    try zbor.DataItem.writeTextString(writer, user.displayName);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("expected: {x}\ngot: {x}\nmatches: {any}\n", .{
        expected,
        di.written(),
        std.mem.eql(u8, expected, di.written()),
    });

    try stdout.flush();
}
