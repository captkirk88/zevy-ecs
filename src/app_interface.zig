const std = @import("std");

const ecs_mod = @import("ecs.zig");
const schedule = @import("scheduler.zig");
const plugins = @import("plugin.zig");
const zreflect = @import("zevy_reflect");

pub const AppVTable = zreflect.DynamicVTable;
pub const VTableEntry = zreflect.VTableEntry;

/// Base App interface entries that zevy-ecs guarantees.
///
/// Downstream libraries can evolve this interface additively with:
/// `const Extended = BaseVTableType.Extend(&.{ ... });`
pub const BaseEntries: []const VTableEntry = &.{
    .{ .name = "io", .Fn = fn (*anyopaque) std.Io },
    .{ .name = "allocator", .Fn = fn (*anyopaque) std.mem.Allocator },
    .{ .name = "ecs", .Fn = fn (*anyopaque) *ecs_mod.Manager },
    .{ .name = "scheduler", .Fn = fn (*anyopaque) *schedule.Scheduler },
    .{ .name = "pluginManager", .Fn = fn (*anyopaque) *plugins.PluginManager },
    .{ .name = "update", .Fn = fn (*anyopaque) anyerror!void },
    .{ .name = "run", .Fn = fn (*anyopaque) anyerror!void },
    .{ .name = "deinit", .Fn = fn (*anyopaque) void },
};

pub const BaseVTableType = AppVTable(BaseEntries);

/// AppExt is a view of the App with an extended DynamicVTable.  This allows downstream libraries to expose additional methods on App without sacrificing interoperability with other libraries or the base App interface.
///
/// Example:
/// ```zig
/// const Extended = BaseVTableType.Extend(&.{
///     .{ .name = "customFn", .Fn = fn (*anyopaque) void },
/// });
/// const ext_vt = Extended.create(struct {
///     pub const customFn = myCustomFnImpl;
/// });
/// const extended_app = app.extend(Extended, &ext_vt.vtable);
/// extended_app.call("customFn", .{}) // calls myCustomFnImpl
/// ```
pub fn AppExt(comptime VTableType: type) type {
    comptime if (!VTableType.containsAll(BaseVTableType)) {
        @compileError("AppExt requires a DynamicVTable type that contains all base App entries");
    };

    return struct {
        ptr: *anyopaque,
        vtable: *const VTableType.VTable,

        pub fn call(self: @This(), comptime name: [:0]const u8, args: anytype) blk: {
            const FnType = @TypeOf((@as(VTableType, undefined)).get(name));
            break :blk @typeInfo(@typeInfo(FnType).pointer.child).@"fn".return_type orelse void;
        } {
            const fn_ptr = @field(self.vtable, name);
            const fn_type = @TypeOf(fn_ptr.*);
            const fn_info = @typeInfo(fn_type).@"fn";
            const args_type = @TypeOf(args);
            const args_info = @typeInfo(args_type);

            if (fn_info.params.len == 0) {
                if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
                    return @call(.auto, fn_ptr, args);
                }
                return @call(.auto, fn_ptr, .{args});
            }

            const self_param = fn_info.params[0].type orelse {
                @compileError("AppExt.call: first parameter for '" ++ name ++ "' must be concrete");
            };

            const erased_self = @as(self_param, @ptrCast(self.ptr));

            if (args_info == .@"struct" and args_info.@"struct".is_tuple) {
                return @call(.auto, fn_ptr, .{erased_self} ++ args);
            }

            return @call(.auto, fn_ptr, .{ erased_self, args });
        }
    };
}

pub const App = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn addSystem(self: App, stage: schedule.StageId, system: anytype) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.addSystem(mgr, stage, system);
        return self;
    }

    pub fn addPlugin(self: App, plugin: anytype) App {
        const PluginType = @TypeOf(plugin);
        const pluginManager = self.vtable.pluginManager(self.ptr);
        _ = pluginManager.add(PluginType, plugin) catch |err| std.debug.panic("addPlugin failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn addEvent(self: App, comptime EventType: type) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.registerEvent(mgr, EventType) catch |err| std.debug.panic("registerEvent failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn addEventWithCleanupAtStage(self: App, comptime EventType: type, stage: schedule.StageId) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.registerEventWithCleanupAtStage(mgr, EventType, stage) catch |err| std.debug.panic("registerEventWithCleanupAtStage failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn addStage(self: App, stage: schedule.StageId) App {
        const sched = self.vtable.scheduler(self.ptr);
        sched.addStage(stage) catch |err| std.debug.panic("addStage failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn registerState(self: App, comptime StateEnum: type) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.registerState(mgr, StateEnum) catch |err| std.debug.panic("registerState failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn unregisterState(self: App, comptime StateEnum: type) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.unregisterState(mgr, StateEnum) catch |err| std.debug.panic("unregisterState failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn addResource(self: App, comptime ResourceType: type, resource: ResourceType) App {
        const mgr = self.vtable.ecs(self.ptr);
        _ = mgr.addResourceRetained(ResourceType, resource) catch |err| std.debug.panic("addResource failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn addResourceRef(self: App, comptime ResourceType: type, resource_ref: ecs_mod.Ref(ResourceType)) App {
        const mgr = self.vtable.ecs(self.ptr);
        _ = mgr.addResourceRef(ResourceType, resource_ref) catch |err| std.debug.panic("addResourceRef failed: {s}", .{@errorName(err)});
        return self;
    }

    pub fn removeResource(self: App, comptime ResourceType: type) App {
        const mgr = self.vtable.ecs(self.ptr);
        mgr.removeResource(ResourceType);
        return self;
    }

    pub fn io(self: App) std.Io {
        return self.vtable.io(self.ptr);
    }

    pub fn allocator(self: App) std.mem.Allocator {
        return self.vtable.allocator(self.ptr);
    }

    pub fn ecs(self: App) *ecs_mod.Manager {
        return self.vtable.ecs(self.ptr);
    }

    pub fn scheduler(self: App) *schedule.Scheduler {
        return self.vtable.scheduler(self.ptr);
    }

    pub fn update(self: App) anyerror!void {
        return self.vtable.update(self.ptr);
    }

    pub fn run(self: App) anyerror!void {
        return self.vtable.run(self.ptr);
    }

    /// Convenience method for chaining a final `.done()` at the end of app construction to indicate completion and improve readability.
    pub fn done(self: App) void {
        _ = self;
        return;
    }

    pub fn deinit(self: App) void {
        self.vtable.deinit(self.ptr);
    }

    /// View this App with an extended DynamicVTable.
    ///
    /// Example:
    /// ```zig
    /// const Extended = BaseVTableType.Extend(&.{
    ///     .{ .name = "customFn", .Fn = fn (*anyopaque) void },
    /// });
    /// const ext_vt = Extended.create(struct {
    ///     pub const customFn = myCustomFnImpl;
    /// });
    /// const extended_app = app.extend(Extended, &ext_vt.vtable);
    /// ```
    pub fn extend(self: App, comptime VTableType: type, vtable: *const VTableType.VTable) AppExt(VTableType) {
        return .{
            .ptr = self.ptr,
            .vtable = vtable,
        };
    }
};

pub const VTable = BaseVTableType.VTable;

pub fn populate(app: *App, ptr: *anyopaque, vtable: *const VTable) void {
    app.ptr = ptr;
    app.vtable = vtable;
}
