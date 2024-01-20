const zbor = @import("main.zig");
const std = @import("std");

const ROUNDS = 10_000;

test "fuzz DataItem.new" {
    const allocator = std.testing.allocator;

    //const Config = struct {
    //    vals: struct { testing: u8, production: u8 },
    //    uptime: u64,
    //};

    var i: usize = 0;
    while (i < ROUNDS) : (i += 1) {
        const bytes_to_allocate = std.crypto.random.intRangeAtMost(usize, 1, 128);
        var mem = try allocator.alloc(u8, bytes_to_allocate);
        defer allocator.free(mem);
        std.crypto.random.bytes(mem);

        _ = zbor.DataItem.new(mem) catch {
            continue;
        };
    }
}

test "fuzz parse(Config, ...)" {
    const allocator = std.testing.allocator;

    const Config = struct {
        vals: struct { testing: u8, production: u8 },
        uptime: u64,
    };

    var i: usize = 0;
    while (i < ROUNDS) : (i += 1) {
        const bytes_to_allocate = std.crypto.random.intRangeAtMost(usize, 1, 128);
        var mem = try allocator.alloc(u8, bytes_to_allocate);
        defer allocator.free(mem);
        std.crypto.random.bytes(mem);

        const di = zbor.DataItem{ .data = mem };

        _ = zbor.parse(Config, di, .{}) catch {
            continue;
        };
    }
}
