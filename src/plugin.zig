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
const reflect = @import("zevy_reflect");

/// Template defining the Plugin interface
///
/// Call `PluginTemplate.validate(YourPluginType)` to ensure your plugin
/// conforms to the required interface.
pub const PluginTemplate = reflect.Template(struct {
    pub const Name: []const u8 = "Plugin";

    pub fn build(_: *@This(), _: *zevy_ecs.Manager, _: *PluginManager) anyerror!void {
        unreachable;
    }
    pub fn deinit(_: *@This(), _: std.mem.Allocator, _: *zevy_ecs.Manager) anyerror!void {
        unreachable;
    }
});

const Plugin = PluginTemplate.Interface;

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
/// try plugin_manager.add(InputPlugin{});
/// try plugin_manager.add(TimePlugin{});
///
/// try plugin_manager.build(&manager);
/// ```
pub const PluginManager = struct {
    plugins: std.ArrayListUnmanaged(PluginEntry) = .{},
    plugin_hashes: std.AutoHashMapUnmanaged(u64, void) = .{},
    allocator: std.mem.Allocator,

    /// Internal storage for type-erased plugins
    const PluginEntry = struct {
        interface: Plugin,
        name: []const u8,
        hash: u64,
        // Type-specific destroy function to free the allocated instance
        destroy_fn: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
    };

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginManager, ecs: *zevy_ecs.Manager) void {
        // Free all allocated plugin instances using their typed deinit functions
        for (self.plugins.items) |entry| {
            // First call the plugin's deinit if present
            entry.interface.vtable.deinit(entry.interface.ptr, self.allocator, ecs) catch |err| {
                std.debug.panic(
                    "Failed to deinit plugin '{s}': {s}",
                    .{ entry.name, @errorName(err) },
                );
            };
            // Then free the concrete plugin instance memory
            if (entry.destroy_fn) |destroy| {
                destroy(entry.interface.ptr, self.allocator);
            }
        }

        self.plugins.deinit(self.allocator);
        self.plugin_hashes.deinit(self.allocator);
    }

    /// Add a plugin instance to the manager.
    pub fn add(self: *PluginManager, comptime PluginType: type, plugin: PluginType) error{
        OutOfMemory,
        PluginAlreadyExists,
    }!void {
        const type_info = reflect.getTypeInfo(PluginType);
        const key_hash = type_info.hash;
        // Check if plugin already exists
        if (self.plugin_hashes.contains(key_hash)) {
            return error.PluginAlreadyExists;
        }

        PluginTemplate.validate(PluginType);
        var interface: Plugin = undefined;
        _ = try PluginTemplate.populateFromValue(&interface, self.allocator, plugin);

        const Wrapper = struct {
            fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const p: *PluginType = @ptrCast(@alignCast(ptr));
                allocator.destroy(p);
            }
        };

        try self.plugins.append(self.allocator, .{
            .interface = interface,
            .name = type_info.name,
            .hash = key_hash,
            .destroy_fn = &Wrapper.destroy,
        });

        try self.plugin_hashes.put(self.allocator, key_hash, {});
    }

    pub fn get(self: *const PluginManager, comptime T: type) ?*T {
        const hash = comptime reflect.typeHash(T);
        for (self.plugins.items) |entry| {
            if (entry.hash == hash) {
                return @ptrCast(@alignCast(entry.interface.ptr));
            }
        }
        return null;
    }

    /// Build all registered plugins
    pub fn build(self: *PluginManager, manager: *zevy_ecs.Manager) !void {
        // Build all plugins
        for (self.plugins.items) |entry| {
            entry.interface.vtable.build(entry.interface.ptr, manager, self) catch |err| {
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
        const hash = comptime reflect.typeHash(T);
        return self.plugin_hashes.contains(hash);
    }
};

test "Plugin basic functionality" {
    const TestPlugin = struct {
        const Self = @This();

        pub fn build(_: *Self, manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(bool, true);
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
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
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
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
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
        }
    };

    const TestPlugin2 = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            const res = manager.getResource(i32).?;
            res.* = 20;
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
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

test "PluginManager prevents duplicate plugins" {
    const TestPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 42);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
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

        pub fn deinit(self: *@This(), _: std.mem.Allocator, manager: *zevy_ecs.Manager) !void {
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
