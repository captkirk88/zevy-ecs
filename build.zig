const std = @import("std");
const reflect = @import("zevy_reflect");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const reflect_dep = b.lazyDependency("zevy_reflect", .{
        .target = target,
        .optimize = optimize,
        .branch_quota = 40_000,
    }) orelse return error.ZevyReflectDependencyNotFound;
    const reflect_mod = reflect_dep.module("zevy_reflect");

    const mem_dep = b.lazyDependency("zevy_mem", .{
        .target = target,
        .optimize = optimize,
    }) orelse return error.ZevyMemDependencyNotFound;
    const mem_mod = mem_dep.module("zevy_mem");

    const mod = b.addModule("zevy_ecs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_reflect", .module = reflect_mod },
            .{ .name = "zevy_mem", .module = mem_mod },
        },
    });

    _ = b.addModule("benchmark", .{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_reflect", .module = reflect_mod },
        },
    });

    const plugin_mod = b.addModule("plugins", .{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zevy_ecs", .module = mod },
            .{ .name = "zevy_reflect", .module = reflect_mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const plugin_tests = b.addTest(.{ .root_module = plugin_mod });

    const run_tests = b.addRunArtifact(tests);
    const run_plugin_tests = b.addRunArtifact(plugin_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_plugin_tests.step);

    if (isSelf(b)) {
        setupExamples(b, &[_]std.Build.Module.Import{
            .{ .name = "zevy_ecs", .module = mod },
            .{ .name = "zevy_reflect", .module = reflect_mod },
            .{ .name = "zevy_mem", .module = mem_mod },
        }, target, optimize);
    }
}

/// Check if the build is running in this project
pub fn isSelf(b: *std.Build) bool {
    // Check for a file that only exists in the main zevy-ecs project
    if (std.fs.accessAbsolute(b.path("build.zig").getPath(b), .{})) {
        return true;
    } else |_| {
        return true;
    }
}

pub fn setupExamples(b: *std.Build, modules: []const std.Build.Module.Import, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    // Examples
    const examples_step = b.step("examples", "Run all examples");

    var examples_dir = std.fs.openDirAbsolute(b.path("examples").getPath(b), .{ .iterate = true }) catch return;
    defer examples_dir.close();

    var examples_iter = examples_dir.iterate();
    while (examples_iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const example_name = std.fs.path.stem(entry.name);
            const example_path = std.fs.path.join(b.allocator, &.{ "examples", entry.name }) catch continue;
            defer b.allocator.free(example_path);

            const example_mod = b.addModule(example_name, .{
                .root_source_file = b.path(example_path),
                .target = target,
                .optimize = optimize,
            });

            // Add imports from the first module if any
            if (modules.len > 0) {
                for (modules) |module| {
                    example_mod.addImport(module.name, module.module);
                }
            }

            // Add each module
            for (modules) |item| {
                example_mod.addImport(item.name, item.module);
            }

            const example_exe = b.addExecutable(.{
                .name = example_name,
                .root_module = example_mod,
            });

            const run_example = b.addRunArtifact(example_exe);

            if (b.args) |args| {
                run_example.addArgs(args);
            }
            const example_step = b.step(example_name, b.fmt("Run the {s} example", .{example_name}));
            example_step.dependOn(&run_example.step);

            examples_step.dependOn(example_step);
        }
    }
}
