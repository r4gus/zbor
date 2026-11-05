//! Standalone micro-benchmarks for zbor.
//!
//! Run with:
//!
//!     zig build bench                 # all benchmarks
//!     zig build bench -- parse nested # only benchmarks whose name contains a filter
//!
//! The `bench` step always builds in ReleaseFast. Every benchmark is run for a
//! number of samples; the median sample is reported as time per operation and,
//! where meaningful, throughput over the encoded CBOR input.

const std = @import("std");
const zbor = @import("zbor");

const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Minimum wall time spent in a single sample.
const sample_target_ns: i96 = 50 * std.time.ns_per_ms;
/// Number of samples per benchmark; the median is reported.
const sample_count: usize = 11;

// ---------------------------------------------------------------------------
// Workload data
// ---------------------------------------------------------------------------

const Document = struct {
    version: u32,
    records: []const Record,

    const Record = struct {
        id: u64,
        score: i32,
        ratio: f64,
        active: bool,
        name: []const u8,
        tag: ?[]const u8,
    };

    fn new(allocator: Allocator, n: usize) !@This() {
        const records = try allocator.alloc(Record, n);
        for (records, 0..) |*r, k| {
            r.* = .{
                .id = 1_000_000 + k,
                .score = @as(i32, @intCast(k % 2000)) - 1000,
                .ratio = @as(f64, @floatFromInt(k)) / 7.0,
                .active = k % 3 == 0,
                .name = "a-reasonably-sized-record-name",
                .tag = if (k % 2 == 0) "even" else null,
            };
        }
        return .{ .version = 3, .records = records };
    }
};

fn encode(allocator: Allocator, value: anytype) ![]u8 {
    var w = Io.Writer.Allocating.init(allocator);
    errdefer w.deinit();
    try zbor.stringify(value, .{}, &w.writer);
    return w.toOwnedSlice();
}

/// `levels` nested single-element arrays around the integer 0.
fn makeNested(allocator: Allocator, levels: usize) ![]u8 {
    const buf = try allocator.alloc(u8, levels + 1);
    @memset(buf[0..levels], 0x81);
    buf[levels] = 0x00;
    return buf;
}

// ---------------------------------------------------------------------------
// Benchmarks
// ---------------------------------------------------------------------------

const Ctx = struct {
    gpa: Allocator,
    doc: Document,
    doc_cbor: []const u8,
    nested_cbor: []const u8,

    pub fn docBytes(self: *const @This()) usize {
        return self.doc_cbor.len;
    }

    fn nestedBytes(self: *const @This()) usize {
        return self.nested_cbor.len;
    }

    fn noBytes(_: *const @This()) usize {
        return 0;
    }

    fn benchValidate(self: *const @This()) !usize {
        // DataItem.new runs the full well-formedness check over the input.
        const di = try zbor.DataItem.new(self.doc_cbor);
        return di.data.len;
    }

    fn benchIterate(ctx: *const @This()) !usize {
        // Walk every record and touch every key/value without allocating.
        const di = zbor.DataItem{ .data = ctx.doc_cbor };
        var top = di.map() orelse return error.Malformed;
        var sum: usize = 0;
        while (top.next()) |kv| {
            var records = kv.value.array() orelse continue;
            while (records.next()) |rec| {
                var fields = rec.map() orelse return error.Malformed;
                while (fields.next()) |f| sum +%= f.value.data.len;
            }
        }
        return sum;
    }

    fn benchParse(ctx: *const @This()) !usize {
        var arena = std.heap.ArenaAllocator.init(ctx.gpa);
        defer arena.deinit();
        const doc = try zbor.parse(Document, .{ .data = ctx.doc_cbor }, .{ .allocator = arena.allocator() });
        return doc.records.len;
    }

    fn benchStringify(ctx: *const @This()) !usize {
        var buf = Io.Writer.Allocating.init(ctx.gpa);
        defer buf.deinit();
        try buf.ensureUnusedCapacity(ctx.doc_cbor.len);
        try zbor.stringify(ctx.doc, .{}, &buf.writer);
        return buf.written().len;
    }

    fn benchBuilder(ctx: *const @This()) !usize {
        var b = try zbor.Builder.withType(ctx.gpa, .Map);
        try b.pushTextString("version");
        try b.pushInt(ctx.doc.version);
        try b.pushTextString("records");
        try b.enter(.Array);
        for (ctx.doc.records) |r| {
            try b.enter(.Map);
            try b.pushTextString("id");
            try b.pushInt(r.id);
            try b.pushTextString("score");
            try b.pushInt(r.score);
            try b.pushTextString("name");
            try b.pushTextString(r.name);
            try b.leave();
        }
        try b.leave();
        const out = try b.finish();
        defer ctx.gpa.free(out);
        return out.len;
    }

    fn benchNestedWalk(ctx: *const @This()) !usize {
        var di = zbor.DataItem{ .data = ctx.nested_cbor };
        var depth: usize = 0;
        while (di.array()) |a| {
            var it = a;
            di = it.next() orelse return error.Malformed;
            depth += 1;
        }
        return depth;
    }

    fn benchReadAlloc(ctx: *const @This()) !usize {
        var reader = Io.Reader.fixed(ctx.doc_cbor);
        const di = try zbor.DataItem.readAlloc(&reader, ctx.gpa);
        defer di.deinit(ctx.gpa);
        return di.data.len;
    }
};

/// Each benchmark performs one operation and returns a value that is fed to
/// `doNotOptimizeAway` so the work cannot be elided.
const Benchmark = struct {
    name: []const u8,
    /// Bytes of CBOR processed per operation (0 = don't report throughput).
    bytes: *const fn (ctx: *const Ctx) usize,
    run: *const fn (ctx: *const Ctx) anyerror!usize,
};

const benchmarks = [_]Benchmark{
    .{ .name = "validate", .bytes = Ctx.docBytes, .run = Ctx.benchValidate },
    .{ .name = "iterate", .bytes = Ctx.docBytes, .run = Ctx.benchIterate },
    .{ .name = "parse", .bytes = Ctx.docBytes, .run = Ctx.benchParse },
    .{ .name = "stringify", .bytes = Ctx.docBytes, .run = Ctx.benchStringify },
    .{ .name = "builder", .bytes = Ctx.noBytes, .run = Ctx.benchBuilder },
    .{ .name = "read-alloc", .bytes = Ctx.docBytes, .run = Ctx.benchReadAlloc },
    .{ .name = "nested-walk", .bytes = Ctx.nestedBytes, .run = Ctx.benchNestedWalk },
};

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

fn now(io: Io) Io.Timestamp {
    return Io.Timestamp.now(io, .awake);
}

/// Returns the median nanoseconds per operation.
fn measure(io: Io, ctx: *const Ctx, b: Benchmark) !f64 {
    // Warm up and calibrate the number of iterations per sample.
    var iters: usize = 1;
    while (true) {
        const start = now(io);
        for (0..iters) |_| std.mem.doNotOptimizeAway(try b.run(ctx));
        const elapsed = start.untilNow(io, .awake).nanoseconds;
        if (elapsed >= sample_target_ns) break;
        iters *= 2;
    }

    var samples: [sample_count]f64 = undefined;
    for (&samples) |*s| {
        const start = now(io);
        for (0..iters) |_| std.mem.doNotOptimizeAway(try b.run(ctx));
        const elapsed = start.untilNow(io, .awake).nanoseconds;
        s.* = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iters));
    }
    std.mem.sort(f64, &samples, {}, std.sort.asc(f64));
    return samples[sample_count / 2];
}

fn matches(name: []const u8, filters: []const [:0]const u8) bool {
    if (filters.len == 0) return true;
    for (filters) |f| if (std.mem.indexOf(u8, name, f) != null) return true;
    return false;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const filters = if (args.len > 1) args[1..] else args[0..0];

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    const record_count = 10_000;
    // Deepest nesting zbor accepts (`max_nesting_depth` in src/cbor.zig).
    const nesting = 128;

    const doc = try Document.new(arena, record_count);
    const ctx = Ctx{
        .gpa = gpa,
        .doc = doc,
        .doc_cbor = try encode(arena, doc),
        .nested_cbor = try makeNested(arena, nesting),
    };

    try out.print(
        \\zbor {s} benchmarks
        \\  document:    {d} records, {d} bytes of CBOR
        \\  nested-walk: {d} nested arrays
        \\
        \\{s:<14} {s:>14} {s:>12}
        \\
    , .{ zbor.VERSION, record_count, ctx.doc_cbor.len, nesting, "benchmark", "time/op", "throughput" });
    try out.flush();

    for (benchmarks) |b| {
        if (!matches(b.name, filters)) continue;

        const ns = try measure(io, &ctx, b);
        try out.print("{s:<14} ", .{b.name});
        try printDuration(out, ns);

        const bytes = b.bytes(&ctx);
        if (bytes > 0) {
            const mib_s = @as(f64, @floatFromInt(bytes)) / (ns / std.time.ns_per_s) / (1024 * 1024);
            try out.print(" {d:>7.1} MiB/s\n", .{mib_s});
        } else {
            try out.print(" {s:>12}\n", .{"-"});
        }
        try out.flush();
    }
}

fn printDuration(out: *Io.Writer, ns: f64) !void {
    if (ns >= std.time.ns_per_ms) {
        try out.print("{d:>11.3} ms", .{ns / std.time.ns_per_ms});
    } else if (ns >= std.time.ns_per_us) {
        try out.print("{d:>11.3} us", .{ns / std.time.ns_per_us});
    } else {
        try out.print("{d:>11.1} ns", .{ns});
    }
}
