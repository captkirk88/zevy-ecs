const std = @import("std");

const ecs_mod = @import("ecs.zig");
const schedule = @import("scheduler.zig");
const plugins = @import("plugin.zig");

pub const App = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn addSystem(self: App, stage: schedule.StageId, system: anytype) App {
        const sched = self.vtable.scheduler(self.ptr);
        const mgr = self.vtable.ecs(self.ptr);
        sched.addSystem(mgr, stage, system);
        return self;
    }

    pub fn addPlugin(self: App, comptime PluginType: type, plugin: PluginType) App {
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
        return self.vtable.addEventWithCleanupAtStage(self.ptr, EventType, stage);
    }

    pub fn addStage(self: App, stage: schedule.StageId) App {
        return self.vtable.addStage(self.ptr, stage);
    }

    pub fn registerState(self: App, comptime StateEnum: type) App {
        return self.vtable.registerState(self.ptr, StateEnum);
    }

    pub fn unregisterState(self: App, comptime StateEnum: type) App {
        return self.vtable.unregisterState(self.ptr, StateEnum);
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
};

pub const VTable = struct {
    addSystem: *const fn (*anyopaque, schedule.StageId, anytype) App,
    addEvent: *const fn (*anyopaque, comptime anytype) App,
    addEventWithCleanupAtStage: *const fn (*anyopaque, comptime anytype, schedule.StageId) App,
    addStage: *const fn (*anyopaque, schedule.StageId) App,
    registerState: *const fn (*anyopaque, comptime anytype) App,
    unregisterState: *const fn (*anyopaque, comptime anytype) App,
    addResource: *const fn (*anyopaque, comptime anytype, anytype) App,
    addResourceRef: *const fn (*anyopaque, comptime anytype, anytype) App,
    removeResource: *const fn (*anyopaque, comptime anytype) App,
    io: *const fn (*anyopaque) std.Io,
    allocator: *const fn (*anyopaque) std.mem.Allocator,
    ecs: *const fn (*anyopaque) *ecs_mod.Manager,
    scheduler: *const fn (*anyopaque) *schedule.Scheduler,
    pluginManager: *const fn (*anyopaque) *plugins.PluginManager,
    update: *const fn (*anyopaque) anyerror!void,
    run: *const fn (*anyopaque) anyerror!void,
    deinit: *const fn (*anyopaque) void,
};

pub fn populate(app: *App, ptr: *anyopaque, vtable: *const VTable) void {
    app.ptr = ptr;
    app.vtable = vtable;
}
