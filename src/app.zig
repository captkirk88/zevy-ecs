const std = @import("std");
const builtin = @import("builtin");
const zevy_ecs = @import("zevy_ecs");
const zevy_reflect = @import("zevy_reflect");
const zevy_mem = @import("zevy_mem");
const plugins = zevy_ecs.plugins;
const app = zevy_ecs.app;
const App = app.App;
const AppVTable = zevy_ecs.app.VTable;
const populate = zevy_ecs.app.populate;
const Plugin = plugins.PluginTemplate.Interface;

inline fn appInner(self: anytype) *AppInner {
    return @ptrCast(@alignCast(self));
}

inline fn appFromInner(inner: *AppInner) *AppImpl {
    return @ptrCast(@alignCast(inner));
}

inline fn appInterface(self: anytype) App {
    const inner = appInner(self);
    return app_to_interface(inner);
}

const AppInner = struct {
    is_empty: bool = false,
    is_initialized: bool = false,
    plugins_deinitialized: bool = false,
    last_frame_time_ns: i128 = 0,
    plugin_man: plugins.PluginManager,
    ecs_man: zevy_ecs.Manager,
    io: std.Io,
    arena: *std.heap.ArenaAllocator,
};

const empty = struct {
    pub var app = AppInner{
        .is_empty = true,
        .is_initialized = false,
        .plugins_deinitialized = false,
        .last_frame_time_ns = 0,
        .plugin_man = undefined,
        .ecs_man = undefined,
        .io = undefined,
        .arena = undefined,
    };
};

const app_vtable: AppVTable = .{
    .addSystem = app_addSystem,
    .addPlugin = app_addPlugin,
    .addEvent = app_addEvent,
    .addEventWithCleanupAtStage = app_addEventWithCleanupAtStage,
    .addStage = app_addStage,
    .registerState = app_registerState,
    .unregisterState = app_unregisterState,
    .addResource = app_addResource,
    .addResourceRef = app_addResourceRef,
    .removeResource = app_removeResource,
    .io = app_io,
    .allocator = app_allocator,
    .ecs = app_ecs,
    .scheduler = app_scheduler,
    .pluginManager = app_pluginManager,
    .update = app_update,
    .run = app_run,
    .deinit = app_deinit,
};

fn app_to_interface(inner: *AppInner) App {
    var app_iface: App = undefined;
    populate(&app_iface, inner, &app_vtable);
    return app_iface;
}

fn app_addSystem(self: *anyopaque, stage: zevy_ecs.schedule.StageId, system: anytype) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().addSystem(&inner.ecs_man, stage, system);
    return app_to_interface(inner);
}

fn app_addPlugin(self: *anyopaque, plugin: anytype) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    const PluginType = @TypeOf(plugin);
    inner.plugin_man.add(PluginType, plugin) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_pluginManager(self: *anyopaque) *plugins.PluginManager {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    return &inner.plugin_man;
}

fn app_addEvent(self: *anyopaque, comptime EventType: type) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().registerEvent(&inner.ecs_man, EventType) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_addEventWithCleanupAtStage(self: *anyopaque, comptime EventType: type, stage: zevy_ecs.schedule.StageId) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().registerEventWithCleanupAtStage(&inner.ecs_man, EventType, stage) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_addStage(self: *anyopaque, stage: zevy_ecs.schedule.StageId) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().addStage(stage) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_registerState(self: *anyopaque, comptime StateEnum: type) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().registerState(&inner.ecs_man, StateEnum) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_unregisterState(self: *anyopaque, comptime StateEnum: type) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.scheduler().unregisterState(&inner.ecs_man, StateEnum) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_addResource(self: *anyopaque, comptime ResourceType: type, resource: anytype) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.addResourceRetained(ResourceType, resource) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_addResourceRef(self: *anyopaque, comptime ResourceType: type, resource_ref: anytype) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.addResourceRef(ResourceType, resource_ref) catch |err| handleError(err, @errorReturnTrace());
    return app_to_interface(inner);
}

fn app_removeResource(self: *anyopaque, comptime ResourceType: type) App {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return app_to_interface(inner);
    inner.ecs_man.removeResource(ResourceType);
    return app_to_interface(inner);
}

fn app_io(self: *anyopaque) std.Io {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    return inner.io;
}

fn app_allocator(self: *anyopaque) std.mem.Allocator {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    return inner.arena.allocator();
}

fn app_ecs(self: *anyopaque) *zevy_ecs.Manager {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    return &inner.ecs_man;
}

fn app_scheduler(self: *anyopaque) *zevy_ecs.schedule.Scheduler {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    return inner.ecs_man.scheduler();
}

fn app_update(self: *anyopaque) anyerror!void {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return;
    _ = try updateFrame(inner);
}

fn app_run(self: *anyopaque) anyerror!void {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return;
    var should_exit = false;
    while (!should_exit) {
        should_exit = try updateFrame(inner);
    }

    finalizeApp(inner);
}

fn app_deinit(self: *anyopaque) void {
    const inner: *AppInner = @ptrCast(@alignCast(self));
    if (inner.is_empty) return;
    deinitPlugins(inner);
    inner.ecs_man.deinit();
}

pub const AppImpl = opaque {
    const Self = @This();

    pub fn addSystem(self: *Self, stage: zevy_ecs.schedule.StageId, system: anytype) *Self {
        const inner = appInner(self);
        if (inner.is_empty) return self;
        // Let the scheduler/manager handle system type classification and caching.
        inner.ecs_man.scheduler().addSystem(&inner.ecs_man, stage, system);
        return self;
    }

    pub fn addPlugin(self: *Self, plugin: anytype) *Self {
        const inner = appInner(self);
        if (inner.is_empty) return self;
        const PluginType = @TypeOf(plugin);
        inner.plugin_man.add(PluginType, plugin) catch |err| handleError(err, @errorReturnTrace());
        return self;
    }

    pub fn addEvent(self: *Self, comptime EventType: type) *Self {
        const inner = appInner(self);
        if (inner.is_empty) return self;
        inner.ecs_man.scheduler().registerEvent(&inner.ecs_man, EventType) catch |err| handleError(err, @errorReturnTrace());
        return self;
    }

    pub fn addEventWithCleanupAtStage(self: *Self, comptime EventType: type, stage: zevy_ecs.schedule.StageId) *Self {
        const inner = appInner(self);
        if (inner.is_empty) return self;
        inner.ecs_man.scheduler().registerEventWithCleanupAtStage(inner.ecs_man, EventType, stage) catch |err| handleError(err, @errorReturnTrace());
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
        inner.scheduler.unregisterState(&inner.ecs_man, StateEnum) catch |err| handleError(err, @errorReturnTrace());
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

    pub fn removeResource(self: *Self, comptime ResourceType: type) *Self {
        const inner = appInner(self);
        if (inner.is_empty) return self;
        inner.ecs_man.removeResource(ResourceType);
        return self;
    }

    pub fn io(self: *Self) std.Io {
        const inner = appInner(self);
        return inner.ecs_man.io();
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        const inner = appInner(self);
        return inner.arena.allocator();
    }

    pub fn ecs(self: *Self) *zevy_ecs.Manager {
        const inner = appInner(self);
        return &inner.ecs_man;
    }

    pub fn scheduler(self: *Self) *zevy_ecs.schedule.Scheduler {
        const inner = appInner(self);
        return inner.ecs_man.scheduler();
    }

    pub fn update(self: *Self) !bool {
        const inner = appInner(self);
        return try updateFrame(inner);
    }

    /// Runs the app's main loop, which continuously updates the app until an `ExitAppEvent` is emitted. If any error occurs during the update process, it logs the error and exits the process.
    pub fn run(self: *Self) !void {
        const inner = appInner(self);
        if (inner.is_empty) return;

        var should_exit = false;
        while (!should_exit) {
            should_exit = try self.update();
        }

        finalizeApp(inner);
    }

    pub fn deinit(self: *Self) void {
        const inner = appInner(self);
        if (inner.is_empty) return;
        deinitPlugins(inner);
        inner.ecs_man.deinit();
    }
};

/// Event emitted when the application is going to exit
pub const ExitAppEvent = enum(u8) {
    Success = 0,
    Error = 1,
};

pub const FixedTimestepAccumulator = struct {
    const Self = @This();

    pub const Diagnostics = struct {
        frame_time: f32 = 0.0,
        accepted_frame_time: f32 = 0.0,
        dropped_time: f32 = 0.0,
        updates: usize = 0,
        overloaded: bool = false,
        hit_update_cap: bool = false,
        overload_frames: u64 = 0,
        total_dropped_time: f64 = 0.0,
    };

    accumulator: f32 = 0.0,
    delta: f32,
    max_updates: usize = 5,
    max_frame_time: f32 = 0.25,
    updates: usize = 0,
    diagnostics: ?Diagnostics = .{},

    pub fn init(fixed_dt: f32) Self {
        return .{ .delta = fixed_dt };
    }

    pub fn beginFrame(self: *Self) void {
        self.beginFrameWithTime(self.delta);
    }

    pub fn beginFrameWithTime(self: *Self, frame_time: f32) void {
        const max_catchup_time = @min(self.max_frame_time, self.delta * @as(f32, @floatFromInt(self.max_updates)));
        const clamped = @min(frame_time, max_catchup_time);
        const dropped_frame_time = @max(frame_time - clamped, 0.0);

        self.accumulator += clamped;
        self.updates = 0;

        if (self.diagnostics) |*diag| {
            diag.frame_time = frame_time;
            diag.accepted_frame_time = clamped;
            diag.dropped_time = 0.0;
            diag.updates = 0;
            diag.overloaded = false;
            diag.hit_update_cap = false;
        }

        self.recordDroppedTime(dropped_frame_time, false);
    }

    pub fn update(self: *Self) bool {
        if (self.updates >= self.max_updates) return false;
        if (self.accumulator < self.delta) return false;
        self.accumulator -= self.delta;
        self.updates += 1;
        if (self.diagnostics) |*diag|
            diag.updates = self.updates;
        return true;
    }

    pub fn finishFrame(self: *Self) void {
        if (self.updates < self.max_updates) return;
        if (self.diagnostics) |*diag| {
            diag.overloaded = true;
            diag.hit_update_cap = true;
        }

        if (self.accumulator < self.delta) return;

        const remainder = @mod(self.accumulator, self.delta);
        const dropped_backlog = self.accumulator - remainder;
        self.accumulator = remainder;
        self.recordDroppedTime(dropped_backlog, true);
    }

    fn recordDroppedTime(self: *Self, dropped_time: f32, hit_update_cap: bool) void {
        if (dropped_time <= 0 and !hit_update_cap) return;
        if (self.diagnostics) |*diag| {
            if (!diag.overloaded) diag.overload_frames += 1;
            diag.overloaded = true;
            diag.hit_update_cap = diag.hit_update_cap or hit_update_cap;
            if (dropped_time <= 0) return;
            diag.dropped_time += dropped_time;
            diag.total_dropped_time += dropped_time;
        }
    }
};

/// Creates a new app instance with the given juicy main init.
///
/// Initializes the app's internal state, including the ECS manager, plugin manager, and scheduler. If any initialization step fails, it logs the error and exits the process.
pub fn new(init: std.process.Init) App {
    const allocator = init.arena.allocator();
    const new_app = allocator.create(AppInner) catch |err| {
        handleError(err, @errorReturnTrace());
        return appInterface(appFromInner(&empty.app)); // Should never reach here
    };
    var ecs_man = zevy_ecs.Manager.init(allocator, init.io) catch |err| {
        handleError(err, @errorReturnTrace());
        return appInterface(appFromInner(&empty.app)); // Should never reach here
    };

    new_app.* = AppInner{
        .is_empty = false,
        .is_initialized = false,
        .plugins_deinitialized = false,
        .last_frame_time_ns = 0,
        .ecs_man = ecs_man,
        .plugin_man = plugins.PluginManager.init(allocator),
        .io = init.io,
        .arena = init.arena,
    };

    const scheduler = ecs_man.scheduler();
    scheduler.registerEvent(
        &new_app.ecs_man,
        ExitAppEvent,
    ) catch |err| {
        handleError(err, @errorReturnTrace());
        return appInterface(appFromInner(new_app));
    };
    return appInterface(appFromInner(new_app));
}

const Stage = zevy_ecs.schedule.Stage;
const Stages = zevy_ecs.schedule.Stages;

fn runStages(app_: *AppInner, start: zevy_ecs.schedule.StageId, end: zevy_ecs.schedule.StageId) !void {
    const log = std.log.scoped(.zevy_app);
    var eg = app_.ecs_man.scheduler().runStages(&app_.ecs_man, start, end);
    if (eg.hasErrors()) {
        var iter = eg.iterator();
        while (iter.next()) |er| {
            log.err("Error in stages {d} -> {d}: {s}", .{ start.value, end.value, @errorName(er) });
            handleError(er, @errorReturnTrace());
        }
        std.process.exit(1);
    }
}

fn runStage(app_: *AppInner, stage: zevy_ecs.schedule.StageId) !void {
    const log = std.log.scoped(.zevy_app);
    var eg = app_.ecs_man.scheduler().runStage(&app_.ecs_man, stage);
    if (eg.hasErrors()) {
        var iter = eg.iterator();
        while (iter.next()) |er| {
            log.err("Error in stage {d}: {s}", .{ stage.value, @errorName(er) });
            handleError(er, @errorReturnTrace());
        }
        std.process.exit(1);
    }
}

fn initializeApp(inner: *AppInner) !void {
    if (inner.is_empty or inner.is_initialized) return;

    inner.is_initialized = true;
    var app_iface = app_to_interface(inner);
    inner.plugin_man.build(&app_iface) catch |err| handleError(err, @errorReturnTrace());
    runStages(inner, Stage(Stages.PreStartup), Stage(Stages.Startup)) catch |err| handleError(err, @errorReturnTrace());
}

fn shouldExitApp(inner: *AppInner) bool {
    const exit_app_event = inner.ecs_man.getResource(zevy_ecs.EventStore(ExitAppEvent));
    if (exit_app_event) |exit_events| {
        defer exit_events.deinit();
        const exit_event_lock = exit_events.lockWrite();
        defer exit_event_lock.deinit();
        return !exit_event_lock.get().isEmpty();
    }
    return false;
}

fn sampleFrameTimeSeconds(inner: *AppInner, default_dt: f32) f32 {
    const now = std.Io.Clock.Timestamp.now(inner.io, .awake).raw.nanoseconds;
    defer inner.last_frame_time_ns = now;

    if (inner.last_frame_time_ns == 0) return default_dt;

    const elapsed_ns = now - inner.last_frame_time_ns;
    if (elapsed_ns <= 0) return 0;

    return @as(f32, @floatFromInt(elapsed_ns)) / @as(f32, @floatFromInt(std.time.ns_per_s));
}

fn runFixedUpdateStages(inner: *AppInner) !void {
    const accum_ref = inner.ecs_man.getResource(FixedTimestepAccumulator) orelse {
        inner.last_frame_time_ns = std.Io.Clock.Timestamp.now(inner.io, .awake).raw.nanoseconds;
        return;
    };
    defer accum_ref.deinit();

    var accum_guard = accum_ref.lockWrite();
    defer accum_guard.deinit();

    const accum = accum_guard.get();
    const frame_time = sampleFrameTimeSeconds(inner, accum.delta);
    accum.beginFrameWithTime(frame_time);

    while (accum.update()) {
        runStages(inner, Stage(Stages.PreFixedUpdate), Stage(Stages.PostFixedUpdate)) catch |err| handleError(err, @errorReturnTrace());
        if (shouldExitApp(inner)) break;
    }

    accum.finishFrame();
}

fn updateFrame(inner: *AppInner) !bool {
    if (inner.is_empty) return false;

    try initializeApp(inner);
    deinitPlugins(inner); // Plugins should not be kept alive for the app lifetime.

    runStage(inner, Stage(Stages.First)) catch |err| handleError(err, @errorReturnTrace());
    runStages(inner, Stage(Stages.First).add(1), Stage(Stages.PreUpdate).sub(1)) catch |err| handleError(err, @errorReturnTrace());
    runStages(inner, Stage(Stages.PreUpdate), Stage(Stages.PreFixedUpdate).sub(1)) catch |err| handleError(err, @errorReturnTrace());
    runFixedUpdateStages(inner) catch |err| handleError(err, @errorReturnTrace());
    runStages(inner, Stage(Stages.PostFixedUpdate).add(1), Stage(Stages.PreDraw).sub(1)) catch |err| handleError(err, @errorReturnTrace());

    const should_exit = shouldExitApp(inner);

    runStages(inner, Stage(Stages.PreDraw), Stage(Stages.PostDraw)) catch |err| handleError(err, @errorReturnTrace());
    runStages(inner, Stage(Stages.PostDraw).add(1), Stage(Stages.Last).sub(1)) catch |err| handleError(err, @errorReturnTrace());
    runStage(inner, Stage(Stages.Last)) catch |err| handleError(err, @errorReturnTrace());

    return should_exit;
}

fn finalizeApp(inner: *AppInner) void {
    if (inner.is_empty) return;
    runStages(inner, Stage(Stages.Exit), Stage(Stages.Max)) catch |err| handleError(err, @errorReturnTrace());
}

fn deinitPlugins(inner: *AppInner) void {
    if (inner.is_empty or inner.plugins_deinitialized) return;

    inner.plugins_deinitialized = true;
    const deinit_errors = inner.plugin_man.deinit(&inner.ecs_man);
    if (deinit_errors) |errors| {
        const log = std.log.scoped(.zevy_app);
        log.err("Errors during plugin deinitialization:", .{});
        for (errors) |err| {
            log.err("Plugin: {s}, error: {s}", .{ err.plugin, @errorName(err.err) });
        }
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
    var app_ = new(testInit());
    defer app_.deinit();
    try app_.update();
}

test "app empty state" {
    var app_ = appFromInner(&empty.app);
    _ = try app_.update();
}

test "app event registration" {
    var app_ = new(testInit());
    defer app_.deinit();

    const TestEvent = struct {
        value: i32,
    };

    try app_.addEvent(TestEvent)
        .addEvent(TestEvent).update();
}

test "fixed timestep accumulator records overload diagnostics" {
    var accum = FixedTimestepAccumulator.init(0.1);
    accum.max_updates = 2;
    accum.max_frame_time = 1.0;
    const diagnostics = &accum.diagnostics.?;

    accum.beginFrameWithTime(0.35);

    try std.testing.expect(diagnostics.overloaded);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), diagnostics.frame_time, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), diagnostics.accepted_frame_time, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.15), diagnostics.dropped_time, 0.0001);
    try std.testing.expectEqual(@as(u64, 1), diagnostics.overload_frames);

    try std.testing.expect(accum.update());
    try std.testing.expect(accum.update());
    try std.testing.expect(!accum.update());

    accum.finishFrame();

    try std.testing.expectEqual(@as(usize, 2), diagnostics.updates);
    try std.testing.expect(diagnostics.hit_update_cap);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), accum.accumulator, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), diagnostics.total_dropped_time, 0.0001);
}
