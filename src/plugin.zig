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

    /// Error information for plugin deinit failures
    pub const DeinitError = struct {
        err: anyerror,
        plugin: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PluginManager, ecs: *zevy_ecs.Manager) ?[]const DeinitError {
        // Deinitialize plugins in reverse registration order (LIFO).
        // Continue deinitializing remaining plugins even if some deinit calls fail.
        var any_error: bool = false;
        var errors = std.ArrayList(DeinitError).initCapacity(self.allocator, self.plugins.items.len) catch |err| @panic(@errorName(err));
        defer errors.deinit(self.allocator);
        var i: usize = self.plugins.items.len;
        while (i != 0) : (i -= 1) {
            const entry = self.plugins.items[i - 1];
            // Call deinit, but don't abort on error; log and continue.
            entry.interface.vtable.deinit(entry.interface.ptr, self.allocator, ecs) catch |err| {
                any_error = true;
                _ = errors.append(self.allocator, .{ .err = err, .plugin = entry.name }) catch |inner_err| @panic(@errorName(inner_err));
            };

            // Always attempt to free the concrete plugin instance memory
            if (entry.destroy_fn) |destroy| {
                destroy(entry.interface.ptr, self.allocator);
            }
        }

        self.plugins.deinit(self.allocator);
        self.plugin_hashes.deinit(self.allocator);

        return if (any_error) errors.items else null;
    }

    pub fn addPlugin(self: *PluginManager, plugin: Plugin) error{
        OutOfMemory,
        PluginAlreadyExists,
    }!void {
        const type_info = reflect.getReflectInfo(@TypeOf(plugin.ptr)).type;
        const key_hash = type_info.hash;
        // Check if plugin already exists
        if (self.plugin_hashes.contains(key_hash)) {
            return error.PluginAlreadyExists;
        }

        try self.plugins.append(self.allocator, .{
            .interface = plugin,
            .name = type_info.toStringEx(true),
            .hash = key_hash,
            .destroy_fn = null, // No destroy function for raw plugins
        });

        try self.plugin_hashes.put(self.allocator, key_hash, {});
    }

    /// Add a plugin instance to the manager.
    pub fn add(self: *PluginManager, comptime PluginType: type, plugin: PluginType) error{
        OutOfMemory,
        PluginAlreadyExists,
    }!void {
        const type_info = reflect.getReflectInfo(PluginType).type;
        const key_hash = type_info.hash;
        // Check if plugin already exists
        if (self.plugin_hashes.contains(key_hash)) {
            return error.PluginAlreadyExists;
        }

        PluginTemplate.validate(PluginType);
        var interface: Plugin = undefined;
        const plugin_inst = try self.allocator.create(PluginType);
        plugin_inst.* = plugin;
        PluginTemplate.populate(&interface, plugin_inst);

        const Wrapper = struct {
            fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const p: *PluginType = @ptrCast(@alignCast(ptr));
                allocator.destroy(p);
            }
        };

        try self.plugins.append(self.allocator, .{
            .interface = interface,
            .name = type_info.toStringEx(true),
            .hash = key_hash,
            .destroy_fn = &Wrapper.destroy,
        });

        try self.plugin_hashes.put(self.allocator, key_hash, {});
    }

    pub fn addBundle(self: *PluginManager, comptime BundleType: type, bundle: BundleType) error{
        OutOfMemory,
        PluginAlreadyExists,
    }!void {
        const info = reflect.getReflectInfo(BundleType).type;
        if (info.category != .Struct) {
            @compileError("Plugin bundle must be a struct");
        }

        inline for (info.fields) |field_info| {
            const FieldType = field_info.type.type;
            const field_value = @field(bundle, field_info.name);
            try self.add(FieldType, field_value);
        }
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
    pub fn getNames(self: *const PluginManager, allocator: std.mem.Allocator) []const []const u8 {
        const names = allocator.alloc([]const u8, self.plugins.items.len) catch |err| {
            std.debug.panic(
                "Failed to allocate plugin names list: {s}",
                .{@errorName(err)},
            );
        };

        for (self.plugins.items, 0..) |entry, i| {
            names[i] = entry.name;
        }
        return names;
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
    defer {
        if (plugin_manager.deinit(&manager)) |errors| {
            for (errors) |error_entry| {
                std.debug.print(
                    "Error deinitializing plugin '{s}': {s}\n",
                    .{ error_entry.plugin, @errorName(error_entry.err) },
                );
            }
        }
    }

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
    defer {
        if (plugin_manager.deinit(&manager)) |errors| {
            for (errors) |error_entry| {
                std.debug.print(
                    "Error deinitializing plugin '{s}': {s}\n",
                    .{ error_entry.plugin, @errorName(error_entry.err) },
                );
            }
        }
    }

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
    defer {
        if (plugin_manager.deinit(&manager)) |errors| {
            for (errors) |error_entry| {
                std.debug.print(
                    "Error deinitializing plugin '{s}': {s}\n",
                    .{ error_entry.plugin, @errorName(error_entry.err) },
                );
            }
        }
    }

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
    defer {
        if (plugin_manager.deinit(&manager)) |errors| {
            for (errors) |error_entry| {
                std.debug.print(
                    "Error deinitializing plugin '{s}': {s}\n",
                    .{ error_entry.plugin, @errorName(error_entry.err) },
                );
            }
        }
    }

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
    if (plugin_manager.deinit(&manager)) |errors| {
        for (errors) |error_entry| {
            std.debug.print(
                "Error deinitializing plugin '{s}': {s}\n",
                .{ error_entry.plugin, @errorName(error_entry.err) },
            );
        }
    }

    // Verify deinit was called (tracker is still valid since manager hasn't been deinited)
    try std.testing.expect(tracker.cleanup_called);
}

// Ensure PluginManager continues deinitializing other plugins even if one deinit errors
test "PluginManager continues deinit on plugin error" {
    const FailingPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 1);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, manager: *zevy_ecs.Manager) anyerror!void {
            _ = self;
            _ = allocator;
            _ = manager;
            return error.OutOfMemory;
        }
    };

    const SuccessPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(bool, false);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, manager: *zevy_ecs.Manager) anyerror!void {
            _ = self;
            _ = allocator;
            if (manager.getResource(bool)) |b| {
                b.* = true;
            }
        }
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    var deinit_done: bool = false;
    defer {
        if (!deinit_done) {
            if (plugin_manager.deinit(&manager)) |errors| {
                for (errors) |error_entry| {
                    std.debug.print(
                        "Error deinitializing plugin '{s}': {s}\n",
                        .{ error_entry.plugin, @errorName(error_entry.err) },
                    );
                }
            }
        }
    }

    try plugin_manager.add(FailingPlugin, .{});
    std.debug.print("Added FailingPlugin\n", .{});
    // Add SuccessPlugin as a raw (stack) instance to avoid allocator pressure in tests
    var success_inst = SuccessPlugin{};
    var success_iface: Plugin = undefined;
    PluginTemplate.populate(&success_iface, &success_inst);
    try plugin_manager.addPlugin(success_iface);
    std.debug.print("Added SuccessPlugin (raw)\n", .{});
    std.debug.print("Plugin count after add: {d}\n", .{plugin_manager.len()});
    try plugin_manager.build(&manager);

    _ = plugin_manager.deinit(&manager);
    deinit_done = true;

    const res = manager.getResource(bool).?;
    try std.testing.expect(res.* == true);
}
test "PluginManager getNames returns correct plugin names" {
    const TestPluginA = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i32, 1);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
        }
    };

    const TestPluginB = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(f32, 2.0);
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
    defer {
        if (plugin_manager.deinit(&manager)) |errors| {
            for (errors) |error_entry| {
                std.debug.print(
                    "Error deinitializing plugin '{s}': {s}\n",
                    .{ error_entry.plugin, @errorName(error_entry.err) },
                );
            }
        }
    }

    try plugin_manager.add(TestPluginA, .{});
    try plugin_manager.add(TestPluginB, .{});
    try plugin_manager.build(&manager);

    const names = plugin_manager.getNames(std.testing.allocator);
    defer std.testing.allocator.free(names);
    for (names) |name| {
        std.debug.print("Registered plugin: {s}\n", .{name});
    }
    try std.testing.expect(names.len == 2);
    // try std.testing.expect(std.mem.eql(u8, names[0], "TestPluginA") or std.mem.eql(u8, names[1], "TestPluginA"));
}

test "PluginManager addPlugin" {
    const RawPlugin = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(u8, 255);
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
    defer _ = plugin_manager.deinit(&manager);

    var rawPlugin = RawPlugin{};
    var interface: Plugin = undefined;
    PluginTemplate.populate(&interface, &rawPlugin);

    try plugin_manager.addPlugin(interface);
    try plugin_manager.build(&manager);

    try std.testing.expectEqual(@as(u8, 255), manager.getResource(u8).?.*);
}

test "PluginManager addBundle" {
    const PluginOne = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(i16, 16);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
        }
    };

    const PluginTwo = struct {
        pub fn build(_: *@This(), manager: *zevy_ecs.Manager, _: *PluginManager) !void {
            _ = try manager.addResource(f64, 3.14);
        }
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator, e: *zevy_ecs.Manager) !void {
            _ = self;
            _ = allocator;
            _ = e;
        }
    };

    const PluginBundle = struct {
        plugin_one: PluginOne = .{},
        plugin_two: PluginTwo = .{},
    };

    var manager = try zevy_ecs.Manager.init(std.testing.allocator);
    defer manager.deinit();

    var plugin_manager = PluginManager.init(std.testing.allocator);
    defer _ = plugin_manager.deinit(&manager);

    try plugin_manager.addBundle(PluginBundle, .{});

    try plugin_manager.build(&manager);

    try std.testing.expectEqual(@as(i16, 16), manager.getResource(i16).?.*);
    try std.testing.expectEqual(3.14, manager.getResource(f64).?.*);
}
