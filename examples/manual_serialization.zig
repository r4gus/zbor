const std = @import("std");
const zbor = @import("zbor");

const User = struct {
    id: []const u8,
    name: []const u8,
    displayName: []const u8,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var stdout = std.io.getStdOut();

pub fn main() !void {
    const user = User{
        .id = "\x01\x23\x45\x67",
        .name = "bob@example.com",
        .displayName = "Bob",
    };

    const expected = "\xa3\x62\x69\x64\x44\x01\x23\x45\x67\x64\x6e\x61\x6d\x65\x6f\x62\x6f\x62\x40\x65\x78\x61\x6d\x70\x6c\x65\x2e\x63\x6f\x6d\x6b\x64\x69\x73\x70\x6c\x61\x79\x4e\x61\x6d\x65\x63\x42\x6f\x62";

    var di = std.ArrayList(u8).init(allocator);
    defer di.deinit();
    const writer = di.writer();

    try zbor.builder.writeMap(writer, 3);
    try zbor.builder.writeTextString(writer, "id");
    try zbor.builder.writeByteString(writer, user.id);
    try zbor.builder.writeTextString(writer, "name");
    try zbor.builder.writeTextString(writer, user.name);
    try zbor.builder.writeTextString(writer, "displayName");
    try zbor.builder.writeTextString(writer, user.displayName);

    try stdout.writer().print("expected: {s}\ngot: {s}\nmatches: {any}\n", .{
        std.fmt.fmtSliceHexLower(expected),
        std.fmt.fmtSliceHexLower(di.items),
        std.mem.eql(u8, expected, di.items),
    });
}
