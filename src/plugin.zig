const std = @import("std");
const zevy_ecs = @import("zevy_ecs");

/// Check if a type implements the plugin interface at compile time.
/// A plugin must have a `build` method with signature:
/// `pub fn build(self: *T, manager: *zevy_ecs.Manager) !void`
/// Manager for ECS plugins
///
/// Example:
/// ```zig
/// var manager = zevy_ecs.Manager.init(allocator);
/// defer manager.deinit();
///
/// var plugin_manager = PluginManager.init(allocator);
/// defer plugin_manager.deinit();
///
/// try plugin_manager.add(InputPlugin, .{});
/// try plugin_manager.add(TimePlugin, .{});
///
/// try plugin_manager.build(&manager);
/// ```
pub const PluginManager = struct {
    plugins: std.ArrayListUnmanaged(PluginEntry) = .{},
    plugin_hashes: std.AutoHashMapUnmanaged(u64, void) = .{},
    allocator: std.mem.Allocator,

    /// Internal storage for type-erased plugins
    const PluginEntry = struct {
        ptr: *anyopaque,
        build_fn: *const fn (*anyopaque, *zevy_ecs.Manager) anyerror!void,
        deinit_fn: *const fn (*anyopaque, allocator: std.mem.Allocator) void,
        name: []const u8,
        hash: u64,
    };

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginManager) void {
        // Free all allocated plugin instances using their typed deinit functions
        for (self.plugins.items) |entry| {
            entry.deinit_fn(entry.ptr, self.allocator);
        }
        self.plugins.deinit(self.allocator);
        self.plugin_hashes.deinit(self.allocator);
    }

    /// Add a plugin instance to the manager.
    pub fn add(self: *PluginManager, comptime T: type, instance: T) !void {
        // Compile-time verification
        if (!comptime isPlugin(T)) {
            @compileError(@typeName(T) ++ " does not implement plugin interface (must have: pub fn build(self: *T, manager: *zevy_ecs.Manager) !void)");
        }

        // Use the name field if available (for FnPlugin), otherwise use type name
        const name = if (@hasDecl(T, "name") and @TypeOf(@field(T, "name")) == []const u8)
            instance.name
        else
            @typeName(T);
        const hash = comptime std.hash.Wyhash.hash(0, @typeName(T));

        // Check if plugin already exists
        if (self.plugin_hashes.contains(hash)) {
            return; // Plugin already added, skip
        }

        // Allocate and store the plugin instance
        const plugin_ptr = try self.allocator.create(T);
        plugin_ptr.* = instance;

        // Generate wrapper functions at compile time for this specific type
        const Wrapper = struct {
            fn buildImpl(ptr: *anyopaque, manager: *zevy_ecs.Manager) !void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                return self_ptr.build(manager);
            }

            fn deinitImpl(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                if (@hasDecl(T, "deinit")) {
                    self_ptr.deinit(allocator);
                }
                allocator.destroy(self_ptr);
            }
        };

        try self.plugins.append(self.allocator, .{
            .ptr = plugin_ptr,
            .build_fn = Wrapper.buildImpl,
            .deinit_fn = Wrapper.deinitImpl,
            .name = name,
            .hash = hash,
        });

        try self.plugin_hashes.put(self.allocator, hash, {});
    }

    /// Build all registered plugins
    pub fn build(self: *const PluginManager, manager: *zevy_ecs.Manager) !void {
        // Build all plugins
        for (self.plugins.items) |entry| {
            entry.build_fn(entry.ptr, manager) catch |err| {
                std.debug.panic(
                    "Failed to build plugin '{s}': {s}",
                    .{ entry.name, @errorName(err) },
                );
            };
        }
    }

    /// Get the names of all registered plugins
    pub fn getNames(self: *const PluginManager) []const []const u8 {
        var names = std.ArrayListUnmanaged([]const u8).initCapacity(self.allocator, self.plugins.items.len) catch |err| {
            std.debug.panic(
                "Failed to allocate plugin names list: {s}",
                .{@errorName(err)},
            );
        };
        defer names.deinit(self.allocator);

        for (self.plugins.items) |entry| {
            names.append(self.allocator, entry.name) catch |err| {
                std.debug.panic(
                    "Failed to append plugin name '{s}': {s}",
                    .{ entry.name, @errorName(err) },
                );
            };
        }
        return names.items;
    }

    pub fn len(self: *const PluginManager) usize {
        return self.plugins.items.len;
    }

    pub fn has(self: *const PluginManager, comptime T: type) bool {
        const hash = comptime std.hash.Wyhash.hash(0, @typeName(T));
        return self.plugin_hashes.contains(hash);
    }

    inline fn isPlugin(comptime T: type) bool {
        if (!@hasDecl(T, "build")) return false;

        const build_fn = @TypeOf(T.build);
        const build_info = @typeInfo(build_fn);

        if (build_info != .@"fn") return false;

        // Verify it's a function that can be called
        return true;
    }
};

/// Helper to create a simple function-based plugin.
/// Useful for quick plugins that don't need state.
///
/// Example:
/// ```zig
/// const myPlugin = FnPlugin("MyPlugin", struct {
///     fn build(manager: *zevy_ecs.Manager) !void {
///         // Setup code here
///     }
/// }.build);
/// ```
pub fn FnPlugin(
    comptime plugin_name: []const u8,
    comptime buildFn: fn (manager: *zevy_ecs.Manager) anyerror!void,
) type {
    return struct {
        const Self = @This();
        name: []const u8 = plugin_name,

        pub fn build(_: *Self, manager: *zevy_ecs.Manager) !void {
            return buildFn(manager);
        }
    };
}

test "Plugin basic functionality" {
    const TestPlugin = struct {
        const Self = @This();

        pub fn build(_: *Self, manager: *zevy_ecs.Manager) !void {
            _ = try manager.addResource(bool, true);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expect(manager.getResource(bool).?.* == true);
}

test "PluginManager add single plugin" {
    const TestPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager) !void {
            _ = try manager.addResource(i32, 42);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expectEqual(@as(i32, 42), manager.getResource(i32).?.*);
}

test "PluginManager add multiple plugins" {
    const TestPlugin1 = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager) !void {
            _ = try manager.addResource(i32, 10);
        }
    };

    const TestPlugin2 = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager) !void {
            const res = manager.getResource(i32).?;
            res.* = 20;
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    try plugin_manager.add(TestPlugin1, .{});
    try plugin_manager.add(TestPlugin2, .{});
    try plugin_manager.build(&manager);

    try std.testing.expectEqual(@as(i32, 20), manager.getResource(i32).?.*);
}

test "Function plugin creation" {
    const MyRes = struct {
        value: []const u8,
    };
    const MyFnPlugin = FnPlugin("TestFn", struct {
        fn build(manager: *zevy_ecs.Manager) !void {
            _ = try manager.addResource(MyRes, .{ .value = "TestFn" });
        }
    }.build);

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    try plugin_manager.add(MyFnPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expectEqualStrings("TestFn", manager.getResource(MyRes).?.value);
}

test "PluginManager prevents duplicate plugins" {
    const TestPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager) !void {
            const res = manager.getResource(i32) orelse {
                _ = try manager.addResource(i32, 0);
                return;
            };
            res.* += 1;
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    // Add the same plugin type multiple times
    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.build(&manager);

    // Should only have been built once
    try std.testing.expectEqual(@as(i32, 0), manager.getResource(i32).?.*);
    try std.testing.expectEqual(@as(usize, 1), plugin_manager.plugins.items.len);
}

test "PluginManager multiple FnPlugin instances" {
    const FnPlugin1 = FnPlugin("Plugin1", struct {
        fn build(manager: *zevy_ecs.Manager) !void {
            _ = try manager.addResource(i32, 1);
        }
    }.build);

    const FnPlugin2 = FnPlugin("Plugin2", struct {
        fn build(manager: *zevy_ecs.Manager) !void {
            const res = manager.getResource(i32).?;
            res.* += 10;
        }
    }.build);

    const FnPlugin3 = FnPlugin("Plugin3", struct {
        fn build(manager: *zevy_ecs.Manager) !void {
            const res = manager.getResource(i32).?;
            res.* += 100;
        }
    }.build);

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit();

    // Add multiple FnPlugin instances
    try plugin_manager.add(FnPlugin1, .{});
    try plugin_manager.add(FnPlugin2, .{});
    try plugin_manager.add(FnPlugin3, .{});
    try plugin_manager.build(&manager);

    // All three should have been built
    try std.testing.expectEqual(@as(i32, 111), manager.getResource(i32).?.*);
    try std.testing.expectEqual(@as(usize, 3), plugin_manager.plugins.items.len);
}
