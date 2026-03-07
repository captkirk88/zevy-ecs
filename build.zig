const std = @import("std");
const buildtools = @import("zevy_buildtools");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const reflect_dep = b.dependency("zevy_reflect", .{
        .target = target,
        .optimize = optimize,
    });
    const reflect_mod = reflect_dep.module("zevy_reflect");

    const mem_dep = b.dependency("zevy_mem", .{
        .target = target,
        .optimize = optimize,
    });
    const mem_mod = mem_dep.module("zevy_mem");

    const self_mod = b.addModule("zevy_ecs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_reflect", .module = reflect_mod },
            .{ .name = "zevy_mem", .module = mem_mod },
        },
    });

    const benchmark_mod = b.addModule("benchmark", .{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_reflect", .module = reflect_mod },
            .{ .name = "zevy_mem", .module = mem_mod },
        },
    });

    const plugin_mod = b.addModule("plugins", .{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_ecs", .module = self_mod },
            .{ .name = "zevy_reflect", .module = reflect_mod },
        },
    });

    // Setup tests
    const tests = b.addTest(.{
        .root_module = self_mod,
    });
    const plugin_tests = b.addTest(.{
        .root_module = plugin_mod,
        .name = "plugin_tests",
    });
    const benchmark_tests = b.addTest(.{
        .root_module = benchmark_mod,
        .name = "benchmark_tests",
    });

    const run_tests = b.addRunArtifact(tests);
    const run_plugin_tests = b.addRunArtifact(plugin_tests);
    const run_benchmark_tests = b.addRunArtifact(benchmark_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_plugin_tests.step);
    if (b.release_mode == .any) {
        test_step.dependOn(&run_benchmark_tests.step);
    }

    const examples = buildtools.examples.setupExamples(b, &.{
        .{ .name = "zevy_ecs", .module = self_mod },
        .{ .name = "zevy_reflect", .module = reflect_mod },
        .{ .name = "zevy_mem", .module = mem_mod },
        .{ .name = "benchmark", .module = benchmark_mod },
    }, target, optimize);
    _ = examples;

    try buildtools.fmt.addFmtStep(b, false);

    try buildtools.fetch.addFetchStep(b, b.path("build.zig.zon"));

    try buildtools.deps.addDepsStep(b);
}
