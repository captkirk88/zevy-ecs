const std = @import("std");
const builtin = @import("builtin");
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
    scheduler: *zevy_ecs.schedule.Scheduler,
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

        pub fn addSystem(self: *Self, stage: zevy_ecs.schedule.StageId, system: anytype) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.scheduler.addSystem(&inner.ecs_man, stage, system, SystemParamRegistry);
            return self;
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
            inner.scheduler.registerEvent(&inner.ecs_man, EventType, SystemParamRegistry) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addEventWithCleanupAtStage(self: *Self, comptime EventType: type, stage: zevy_ecs.schedule.StageId) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.scheduler.registerEventWithCleanupAtStage(inner.ecs_man, EventType, stage, SystemParamRegistry) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn addStage(self: *Self, stage: zevy_ecs.schedule.StageId) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.scheduler.addStage(stage) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn registerState(self: *Self, comptime StateEnum: type) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.scheduler.registerState(&inner.ecs_man, StateEnum) catch |err| handleError(err, @errorReturnTrace());
            return self;
        }

        pub fn unregisterState(self: *Self, comptime StateEnum: type) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            _ = StateEnum;
            // TODO implement
            //inner.scheduler.unregisterState(&inner.ecs_man, StateEnum) catch |err| handleError(err, @errorReturnTrace());
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

        pub fn ecs(self: *Self) *zevy_ecs.Manager {
            const inner = appInner(self);
            return &inner.ecs_man;
        }

        pub fn update(self: *Self) !void {
            const inner = appInner(self);
            if (inner.is_empty) return;

            // Start of loop
            runStage(inner, Stage(Stages.First)) catch |err| handleError(err, @errorReturnTrace());

            // Run inbetween stages
            runStages(inner, Stage(Stages.First).add(1), Stage(Stages.PreUpdate).sub(1)) catch |err| handleError(err, @errorReturnTrace());

            runStages(inner, Stage(Stages.PreUpdate), Stage(Stages.Update)) catch |err| handleError(err, @errorReturnTrace());

            // Run inbetween stages
            runStages(inner, Stage(Stages.Update).add(1), Stage(Stages.PreDraw).sub(1)) catch |err| handleError(err, @errorReturnTrace());

            runStages(inner, Stage(Stages.PreDraw), Stage(Stages.PostDraw)) catch |err| handleError(err, @errorReturnTrace());

            // Run inbetween stages
            runStages(inner, Stage(Stages.PostDraw).add(1), Stage(Stages.Last).sub(1)) catch |err| handleError(err, @errorReturnTrace());

            // End of loop
            runStage(inner, Stage(Stages.Last)) catch |err| handleError(err, @errorReturnTrace());
        }

        /// Runs the app's main loop, which continuously updates the app until an `ExitAppEvent` is emitted. If any error occurs during the update process, it logs the error and exits the process.
        pub fn run(self: *Self) !void {
            const inner = appInner(self);
            if (inner.is_empty) return;
            inner.plugin_man.build(&inner.ecs_man) catch |err| handleError(err, @errorReturnTrace());
            runStages(inner, Stage(Stages.PreStartup), Stage(Stages.Startup)) catch |err| handleError(err, @errorReturnTrace());
            const deinit_errors = inner.plugin_man.deinit(&inner.ecs_man);
            if (deinit_errors) |errors| {
                const log = std.log.scoped(.zevy_app);
                log.err("Errors during plugin deinitialization:", .{});
                for (errors) |err| {
                    log.err("Plugin: {s}, error: {s}", .{ err.plugin, @errorName(err.err) });
                }
            }

            var should_exit = false;
            while (should_exit == false) {
                {
                    const exit_app_event = inner.ecs_man.getResource(zevy_ecs.EventStore(ExitAppEvent));
                    if (exit_app_event) |exit_events| {
                        defer exit_events.deinit();
                        const exit_event_lock = exit_events.lockWrite();
                        defer exit_event_lock.deinit();
                        var exit_event_iter = exit_event_lock.get().iterator();
                        if (exit_event_iter.next()) |_| {
                            should_exit = true;
                        }
                    }
                }

                try self.update();
            }

            // Exit of app
            runStages(inner, Stage(Stages.Exit), Stage(Stages.Max)) catch |err| handleError(err, @errorReturnTrace());
        }

        pub fn deinit(self: *Self) void {
            const inner = appInner(self);
            if (inner.is_empty) return;
            inner.ecs_man.deinit();
        }
    };
}

/// Event emitted when the application is going to exit
pub const ExitAppEvent = enum(u8) {
    Success = 0,
    Error = 1,
};

/// Creates a new app instance with the given initialization parameters and system parameter registry.
///
/// Initializes the app's internal state, including the ECS manager, plugin manager, and scheduler. If any initialization step fails, it logs the error and exits the process.
pub fn new(init: std.process.Init, comptime ParamRegistry: type) *App(ParamRegistry) {
    const allocator = init.arena.allocator();
    const new_app = allocator.create(AppInner) catch |err| {
        handleError(err, @errorReturnTrace());
        return appFromInner(ParamRegistry, &empty.app);
    };
    const ecs_man = zevy_ecs.Manager.init(allocator, init.io) catch |err| {
        handleError(err, @errorReturnTrace());
        return appFromInner(ParamRegistry, &empty.app);
    };
    const scheduler_ptr = ecs_man.scheduler;
    new_app.* = AppInner{
        .is_empty = false,
        .ecs_man = ecs_man,
        .plugin_man = plugins.PluginManager.init(allocator),
        .scheduler = scheduler_ptr,
        .io = init.io,
        .arena = init.arena,
    };

    new_app.scheduler.registerEvent(
        &new_app.ecs_man,
        ExitAppEvent,
        ParamRegistry,
    ) catch |err| {
        handleError(err, @errorReturnTrace());
        return appFromInner(ParamRegistry, &empty.app);
    };
    return appFromInner(ParamRegistry, new_app);
}

const Stage = zevy_ecs.schedule.Stage;
const Stages = zevy_ecs.schedule.Stages;

fn runStages(app: *AppInner, start: zevy_ecs.schedule.StageId, end: zevy_ecs.schedule.StageId) !void {
    const log = std.log.scoped(.zevy_app);
    var eg = app.scheduler.runStages(&app.ecs_man, start, end);
    if (eg.hasErrors()) {
        var iter = eg.iterator();
        while (iter.next()) |er| {
            log.err("Error in stages {d} -> {d}: {s}", .{ start.value, end.value, @errorName(er) });
            handleError(er, @errorReturnTrace());
        }
        std.process.exit(1);
    }
}

fn runStage(app: *AppInner, stage: zevy_ecs.schedule.StageId) !void {
    const log = std.log.scoped(.zevy_app);
    var eg = app.scheduler.runStage(&app.ecs_man, stage);
    if (eg.hasErrors()) {
        var iter = eg.iterator();
        while (iter.next()) |er| {
            log.err("Error in stage {d}: {s}", .{ stage.value, @errorName(er) });
            handleError(er, @errorReturnTrace());
        }
        std.process.exit(1);
    }
}

fn handleError(err: anyerror, stack_trace: ?*std.builtin.StackTrace) void {
    const log = std.log.scoped(.zevy_app);
    log.err("{s}", .{@errorName(err)});
    if (builtin.mode == .Debug) {
        if (stack_trace) |trace| {
            log.err("Stack trace:\n", .{});
            std.debug.dumpErrorReturnTrace(trace);
            std.debug.dumpCurrentStackTrace(.{});
        } else {
            std.debug.dumpCurrentStackTrace(.{});
        }
    }
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
    try app.update();
}

test "app empty state" {
    var app = appFromInner(zevy_ecs.DefaultParamRegistry, &empty.app);
    try app.update();
}

test "app event registration" {
    var app = new(testInit(), zevy_ecs.DefaultParamRegistry);
    defer app.deinit();

    const TestEvent = struct {
        value: i32,
    };

    try app.addEvent(TestEvent)
        .addEvent(TestEvent).update();
}
