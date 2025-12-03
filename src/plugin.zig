//! Plugin management system for Zevy ECS.
//! A plugin is a modular piece of functionality that can be
//! added to the ECS manager to extend functionality.
//!
//! Example:
//! const MyPlugin = struct {
//!    pub fn build(self: *@This(), manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) !void {
//!       // Setup code here
//!   }
//!
//!   // Optional deinit
//!   pub fn deinit(self: *@This(), manager: *zevy_ecs.Manager) void {
//!       // Cleanup code here
//!   }
//! };

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
        build_fn: *const fn (*anyopaque, *zevy_ecs.Manager, *PluginManager) anyerror!void,
        deinit_fn: *const fn (*anyopaque, std.mem.Allocator, *zevy_ecs.Manager) void,
        name: []const u8,
        hash: u64,
    };

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginManager, ecs: *zevy_ecs.Manager) void {
        // Free all allocated plugin instances using their typed deinit functions
        for (self.plugins.items) |entry| {
            entry.deinit_fn(entry.ptr, self.allocator, ecs);
        }
        self.plugins.deinit(self.allocator);
        self.plugin_hashes.deinit(self.allocator);
    }

    /// Add a plugin instance to the manager.
    pub fn add(self: *PluginManager, comptime T: type, instance: T) error{ OutOfMemory, PluginAlreadyExists }!void {
        // Compile-time verification
        if (!comptime zevy_ecs.reflect.hasFuncWithArgs(T, "build", &[_]type{ *zevy_ecs.Manager, *PluginManager })) {
            @compileError(std.fmt.comptimePrint("Plugin '{s}' does not implement plugin interface (must have: pub fn build(self: *T, manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) !void)", .{@typeName(T)}));
        }

        // Use the name field if available (for FnPlugin), otherwise use type name
        const name = if (@hasDecl(T, "name") and
            @TypeOf(@field(T, "name")) == []const u8)
            instance.name
        else
            @typeName(T);
        const hash = comptime std.hash.Wyhash.hash(0, @typeName(T));

        // Check if plugin already exists
        if (self.plugin_hashes.contains(hash)) {
            return error.PluginAlreadyExists;
        }

        // Allocate and store the plugin instance
        const plugin_ptr = try self.allocator.create(T);
        plugin_ptr.* = instance;

        // Generate wrapper functions at compile time for this specific type
        const Wrapper = struct {
            fn buildImpl(ptr: *anyopaque, manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) !void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                return self_ptr.build(manager, plugin_manager);
            }

            fn deinitImpl(ptr: *anyopaque, allocator: std.mem.Allocator, manager: *zevy_ecs.Manager) void {
                const self_ptr: *T = @ptrCast(@alignCast(ptr));
                if (@hasDecl(T, "deinit")) {
                    self_ptr.deinit(manager);
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

    pub fn get(self: *const PluginManager, comptime T: type) ?*T {
        const hash = comptime std.hash.Wyhash.hash(0, @typeName(T));
        for (self.plugins.items) |entry| {
            if (entry.hash == hash) {
                return @ptrCast(@alignCast(entry.ptr));
            }
        }
        return null;
    }

    /// Build all registered plugins
    pub fn build(self: *PluginManager, manager: *zevy_ecs.Manager) !void {
        // Build all plugins
        for (self.plugins.items) |entry| {
            entry.build_fn(entry.ptr, manager, self) catch |err| {
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
};

/// Helper to create a simple function-based plugin.
/// Useful for quick plugins that don't need state.
///
/// Example:
/// ```zig
/// const myPlugin = FnPlugin("MyPlugin", struct {
///     fn build(manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) !void {
///         // Setup code here
///     }
/// }.build);
/// ```
pub fn FnPlugin(
    comptime plugin_name: []const u8,
    comptime buildFn: fn (manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) anyerror!void,
) type {
    return struct {
        const Self = @This();
        name: []const u8 = plugin_name,

        pub fn build(_: *Self, manager: *zevy_ecs.Manager, plugin_manager: *PluginManager) !void {
            return buildFn(manager, plugin_manager);
        }
    };
}

test "Plugin basic functionality" {
    const TestPlugin = struct {
        const Self = @This();

        pub fn build(_: *Self, manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(bool, true);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expect(manager.getResource(bool).?.* == true);
}

test "PluginManager add single plugin" {
    const TestPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 42);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

    try plugin_manager.add(TestPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expectEqual(@as(i32, 42), manager.getResource(i32).?.*);
}

test "PluginManager add multiple plugins" {
    const TestPlugin1 = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 10);
        }
    };

    const TestPlugin2 = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            const res = manager.getResource(i32).?;
            res.* = 20;
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

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
        fn build(manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(MyRes, .{ .value = "TestFn" });
        }
    }.build);

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

    try plugin_manager.add(MyFnPlugin, .{});
    try plugin_manager.build(&manager);

    try std.testing.expectEqualStrings("TestFn", manager.getResource(MyRes).?.value);
}

test "PluginManager prevents duplicate plugins" {
    const TestPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 42);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

    // First add should succeed
    try plugin_manager.add(TestPlugin, .{});

    // Subsequent adds of the same plugin type should return PluginAlreadyExists
    try std.testing.expectError(error.PluginAlreadyExists, plugin_manager.add(TestPlugin, .{}));
    try std.testing.expectError(error.PluginAlreadyExists, plugin_manager.add(TestPlugin, .{}));

    try plugin_manager.build(&manager);

    // Should only have been added and built once
    try std.testing.expectEqual(@as(i32, 42), manager.getResource(i32).?.*);
    try std.testing.expectEqual(@as(usize, 1), plugin_manager.plugins.items.len);
}

test "PluginManager multiple FnPlugin instances" {
    const FnPlugin1 = FnPlugin("Plugin1", struct {
        fn build(manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 1);
        }
    }.build);

    const FnPlugin2 = FnPlugin("Plugin2", struct {
        fn build(manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            const res = manager.getResource(i32).?;
            res.* += 10;
        }
    }.build);

    const FnPlugin3 = FnPlugin("Plugin3", struct {
        fn build(manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            const res = manager.getResource(i32).?;
            res.* += 100;
        }
    }.build);

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer plugin_manager.deinit(&manager);

    // Add multiple FnPlugin instances
    try plugin_manager.add(FnPlugin1, .{});
    try plugin_manager.add(FnPlugin2, .{});
    try plugin_manager.add(FnPlugin3, .{});
    try plugin_manager.build(&manager);

    // All three should have been built
    try std.testing.expectEqual(@as(i32, 111), manager.getResource(i32).?.*);
    try std.testing.expectEqual(@as(usize, 3), plugin_manager.plugins.items.len);
}

test "Plugin with deinit for proper memory cleanup" {
    // Resource to track cleanup state
    const CleanupTracker = struct {
        cleanup_called: bool = false,
    };

    const TestPluginWithDeinit = struct {
        const Self = @This();

        // Plugin owns allocated memory that must be freed
        allocated_data: []u8,

        pub fn build(self: *Self, manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            // Allocate some data during build
            self.allocated_data = try manager.allocator.alloc(u8, 64);
            @memset(self.allocated_data, 0xAB);

            // Add a resource to verify build ran
            _ = try manager.addResource(CleanupTracker, .{});
        }

        pub fn deinit(self: *Self, manager: *zevy_ecs.Manager) void {
            // Mark that cleanup was called
            if (manager.getResource(CleanupTracker)) |tracker| {
                tracker.cleanup_called = true;
            }

            // Free the allocated data
            manager.allocator.free(self.allocated_data);
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);

    // Add and build the plugin
    try plugin_manager.add(TestPluginWithDeinit, .{ .allocated_data = &.{} });
    try plugin_manager.build(&manager);

    // Verify build ran
    const tracker = manager.getResource(CleanupTracker).?;
    try std.testing.expect(!tracker.cleanup_called);

    // Deinit the plugin manager - this should call the plugin's deinit
    plugin_manager.deinit(&manager);

    // Verify deinit was called (tracker is still valid since manager hasn't been deinited)
    try std.testing.expect(tracker.cleanup_called);
}
