const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zbor_module = try buildZborModule(
        b,
        target,
        optimize,
    );

    // Creates a step for fuzz testing.
    //const fuzz_tests = b.addTest(.{
    //    .root_source_file = b.path("src/fuzz.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});

    //const fuzz_test_step = b.step("fuzz", "Run fuzz tests");
    //fuzz_test_step.dependOn(&b.addRunArtifact(fuzz_tests).step);

    // Examples
    // ---------------------------------------------------
    try buildExamples(
        b,
        target,
        optimize,
        zbor_module,
    );

    // Benchmarks
    // ---------------------------------------------------
    buildBenchmark(b, target);
}

/// Build the main module implementing the CBOR de-/serializer.
fn buildZborModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Module {
    const zbor_module = b.addModule("zbor", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Creates a step for unit testing.
    const mod_tests = b.addTest(.{
        .root_module = zbor_module,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);

    return zbor_module;
}

/// Build the examples found in the `./examples/` directory.
fn buildExamples(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zbor_module: *std.Build.Module,
) !void {
    const examples: [3][2][]const u8 = .{
        .{ "examples/manual_serialization.zig", "manual_serialization" },
        .{ "examples/automatic_serialization.zig", "automatic_serialization" },
        .{ "examples/automatic_serialization2.zig", "automatic_serialization2" },
    };

    for (examples) |entry| {
        const path, const name = entry;

        const exe_mod = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });

        const example = b.addExecutable(.{
            .name = name,
            .root_module = exe_mod,
        });

        example.root_module.addImport("zbor", zbor_module);
        b.installArtifact(example);
    }
}

/// Build the benchmark application found in `./bench/`.
///
/// Benchmarks are always compiled with ReleaseFast, independent of `-Doptimize`,
/// so that `zig build bench` reports meaningful numbers by default.
fn buildBenchmark(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) void {
    const bench_zbor = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("zbor", bench_zbor);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_mod,
    });

    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.addPassthruArgs();

    const bench_step = b.step("bench", "Run the benchmarks; pass filters after --");
    bench_step.dependOn(&run_bench.step);
}
