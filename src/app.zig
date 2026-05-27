const std = @import("std");

const zevy_ecs = @import("zevy_ecs");
const zevy_reflect = @import("zevy_reflect");
const zevy_mem = @import("zevy_mem");
const plugins = @import("plugins");
const Plugin = plugins.PluginTemplate.Interface;

inline fn appInner(self: anytype) *AppInner {
    return @ptrCast(@alignCast(self));
}

inline fn appFromInner(comptime ParamRegistry: type, inner: *AppInner) *App(ParamRegistry) {
    return @ptrCast(@alignCast(inner));
}

const AppInner = struct {
    is_empty: bool = false,
    plugin_man: plugins.PluginManager,
    ecs_man: zevy_ecs.Manager,
    scheduler: zevy_ecs.Ref(zevy_ecs.schedule.Scheduler),
    io: std.Io,
    arena: *std.heap.ArenaAllocator,
};

const empty = struct {
    pub var app = AppInner{
        .is_empty = true,
        .plugin_man = undefined,
        .ecs_man = undefined,
        .scheduler = undefined,
        .io = undefined,
        .arena = undefined,
    };
};

pub fn App(comptime SystemParamRegistry: type) type {
    return opaque {
        const Self = @This();

        pub fn SystemParamRegistryType(self: *Self) type {
            _ = self;
            return SystemParamRegistry;
        }

        pub fn addPlugin(self: *Self, comptime PluginType: type, plugin: PluginType) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.plugin_man.add(PluginType, plugin) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addEvent(self: *Self, comptime EventType: type) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            const scheduler = inner.scheduler.lockWrite();
            defer scheduler.deinit();
            scheduler.get().registerEvent(&inner.ecs_man, EventType, SystemParamRegistry) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addEventWithCleanupStage(self: *Self, comptime EventType: type, stage: zevy_ecs.schedule.Stage) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            const scheduler = inner.scheduler.lockWrite();
            scheduler.get().registerEventWithCleanupAtStage(inner.ecs_man, EventType, stage, SystemParamRegistry) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addResource(self: *Self, comptime ResourceType: type, resource: ResourceType) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.ecs_man.addResourceRetained(ResourceType, resource) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addResourceRef(self: *Self, comptime ResourceType: type, resource_ref: zevy_ecs.Ref(ResourceType)) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.ecs_man.addResourceRef(ResourceType, resource_ref) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn io(self: *Self) std.Io {
            const inner = appInner(self);
            return inner.io;
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            const inner = appInner(self);
            return inner.arena.allocator();
        }

        pub fn run(self: *Self) !void {
            const inner = appInner(self);
            if (inner.is_empty) return;
            inner.plugin_man.build(&inner.ecs_man) catch |err| handleError(err, @errorReturnTrace());
            const deinit_errors = inner.plugin_man.deinit(&inner.ecs_man);
            if (deinit_errors) |errors| {
                const log = std.log.scoped(.zevy_app);
                log.err("Errors during plugin deinitialization:", .{});
                for (errors) |err| {
                    log.err("Plugin: {s}, error: {s}", .{ err.plugin, @errorName(err.err) });
                }
            }
        }

        pub fn deinit(self: *Self) void {
            const inner = appInner(self);
            if (inner.is_empty) return;
            inner.ecs_man.deinit();
        }
    };
}

/// Creates a new app instance with the given initialization parameters and system parameter registry.
///
/// Initializes the app's internal state, including the ECS manager, plugin manager, and scheduler. If any initialization step fails, it logs the error and exits the process.
pub fn new(init: std.process.Init, comptime ParamRegistry: type) *App(ParamRegistry) {
    const allocator = init.arena.allocator();
    const new_app = allocator.create(AppInner) catch |err| {
        handleError(err, @errorReturnTrace());
        return appFromInner(ParamRegistry, &empty.app);
    };
    new_app.* = AppInner{
        .is_empty = false,
        .ecs_man = zevy_ecs.Manager.init(allocator) catch |err| {
            handleError(err, @errorReturnTrace());
            return appFromInner(ParamRegistry, &empty.app);
        },
        .plugin_man = plugins.PluginManager.init(allocator),
        .scheduler = zevy_mem.pointers.ArcRwLock(zevy_ecs.schedule.Scheduler).init(allocator, zevy_ecs.schedule.Scheduler.init(allocator) catch |err| {
            handleError(err, @errorReturnTrace());
            return appFromInner(ParamRegistry, &empty.app);
        }) catch |err| {
            handleError(err, @errorReturnTrace());
            return appFromInner(ParamRegistry, &empty.app);
        },
        .io = init.io,
        .arena = init.arena,
    };
    new_app.ecs_man.addResourceRef(zevy_ecs.schedule.Scheduler, new_app.scheduler) catch |err| {
        handleError(err, @errorReturnTrace());
        return appFromInner(ParamRegistry, &empty.app);
    };
    return appFromInner(ParamRegistry, new_app);
}

fn handleError(err: anyerror, stack_trace: ?*std.builtin.StackTrace) void {
    const log = std.log.scoped(.zevy_app);
    log.err("{s}", .{@errorName(err)});
    if (stack_trace) |trace| {
        log.err("Stack trace:\n", .{});
        std.debug.dumpErrorReturnTrace(trace);
        std.debug.dumpCurrentStackTrace(.{});
    } else {
        std.debug.dumpCurrentStackTrace(.{});
    }
    const builtin = @import("builtin");
    if (builtin.mode != .Debug and !builtin.is_test) {
        // This is not useful for diagnosing the exit code but gives a hint to the user that something went wrong and they should check the logs.  This is not useful because the error code (u8) may not match a actual error (u16) using `@errorFromInt`.
        std.process.exit(@as(u8, @intCast(@intFromError(err))));
    }
}

fn testInit() std.process.Init {
    const State = struct {
        var initialized = false;
        var threaded: std.Io.Threaded = undefined;
        var arena: std.heap.ArenaAllocator = undefined;
        var environ_map: std.process.Environ.Map = undefined;
    };

    if (!State.initialized) {
        State.threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        State.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        State.environ_map = std.process.Environ.Map.init(State.arena.allocator());
        State.initialized = true;
    }

    return .{
        .arena = &State.arena,
        .gpa = std.heap.page_allocator,
        .io = State.threaded.io(),
        .minimal = .{ .args = .{ .vector = undefined }, .environ = .empty },
        .preopens = .empty,
        .environ_map = &State.environ_map,
    };
}

test "app compiles and runs" {
    var app = new(testInit(), zevy_ecs.DefaultParamRegistry);
    defer app.deinit();
    try app.run();
}

test "app empty state" {
    var app = appFromInner(zevy_ecs.DefaultParamRegistry, &empty.app);
    try app.run();
}

test "app error exit" {
    var app = new(testInit(), zevy_ecs.DefaultParamRegistry);
    defer app.deinit();

    const TestResource = struct {
        value: i32,
    };

    try app.addResource(TestResource, .{ .value = 69 })
        .addResource(TestResource, .{ .value = 69 }).run();
}

test "app event registration" {
    var app = new(testInit(), zevy_ecs.DefaultParamRegistry);
    defer app.deinit();

    const TestEvent = struct {
        value: i32,
    };

    try app.addEvent(TestEvent)
        .addEvent(TestEvent).run();
}
