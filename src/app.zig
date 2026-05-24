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
    scheduler: zevy_ecs.schedule.Scheduler,
};

pub const empty = struct {
    pub var app = AppInner{
        .is_empty = true,
        .plugin_man = undefined,
        .ecs_man = undefined,
        .scheduler = undefined,
    };
};

pub fn App(comptime SystemParamRegistry: type) type {
    return opaque {
        /// The registry for system parameters.
        pub const ParamRegistry = SystemParamRegistry;
        const Self = @This();

        pub fn addPlugin(self: *Self, comptime PluginType: type, plugin: PluginType) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.plugin_man.add(PluginType, plugin) catch |err| handleError(err);
            return self;
        }

        pub fn addEvent(self: *Self, comptime EventType: type) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.scheduler.registerEvent(inner.ecs_man, EventType, inner.param_registry) catch |err| handleError(err);
            return self;
        }

        pub fn addResource(self: *Self, comptime ResourceType: type, resource: ResourceType) *Self {
            const inner = appInner(self);
            if (inner.is_empty) return self;
            inner.ecs_man.addResource(ResourceType, resource) catch |err| handleError(err);
            return self;
        }

        pub fn run(self: *Self) !void {
            const inner = appInner(self);
            if (inner.is_empty) return;
            inner.plugin_man.build(&inner.ecs_man) catch |err| handleError(err);
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

pub fn new(init: std.process.Init, comptime ParamRegistry: type) *App(ParamRegistry) {
    const allocator = init.arena.allocator();
    const new_app = allocator.create(AppInner) catch |err| {
        handleError(err);
        return appFromInner(ParamRegistry, &empty.app);
    };
    new_app.* = AppInner{
        .is_empty = false,
        .ecs_man = zevy_ecs.Manager.init(allocator) catch |err| {
            handleError(err);
            return appFromInner(ParamRegistry, &empty.app);
        },
        .plugin_man = plugins.PluginManager.init(allocator),
        .scheduler = zevy_ecs.schedule.Scheduler.init(allocator) catch |err| {
            handleError(err);
            return appFromInner(ParamRegistry, &empty.app);
        },
    };
    return appFromInner(ParamRegistry, new_app);
}

fn handleError(err: anyerror) void {
    const log = std.log.scoped(.zevy_app);
    const stack = @errorReturnTrace();
    log.err("{s}", .{@errorName(err)});
    if (stack) |trace| {
        log.err("Stack trace:\n{any}", .{trace});
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
