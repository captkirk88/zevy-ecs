const std = @import("std");
const ecs_mod = @import("ecs.zig");
const events = @import("events.zig");
const registry = @import("systems.registry.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");
const state_mod = @import("state.zig");
const reflect = @import("zevy_reflect");

const is_debug = @import("builtin").mode == .Debug;

/// Stage ID type
pub const StageId = struct {
    value: i32,

    pub inline fn init(value: i32) StageId {
        return StageId{ .value = value };
    }

    pub fn eql(self: *const StageId, other: StageId) bool {
        return self.value == other.value;
    }

    pub fn toString(self: StageId) []const u8 {
        return std.fmt.comptimePrint("StageId{{ value: {d} }}", .{self.value});
    }

    pub fn add(self: StageId, offset: u32) StageId {
        return StageId{ .value = self.value + @as(i32, @intCast(offset)) };
    }

    pub fn subtract(self: StageId, offset: u32) StageId {
        return StageId{ .value = self.value - @as(i32, @intCast(offset)) };
    }
};

/// Convert a stage type to its unique stage ID.
/// Each unique type gets a consistent i32 value based on its type name hash.
/// Predefined stages map to specific ranges for ordering, custom stages use hash-based IDs.
pub inline fn Stage(comptime T: type) StageId {
    // Check if T has a priority field for explicit ordering
    switch (comptime reflect.getReflectInfo(T)) {
        .type => |type_info| {
            if (type_info.hasDecl("priority")) {
                return T.priority;
            }
        },
        else => {},
    }

    // Generate hash-based ID in user custom range (2,000,000 to ~2.1B)
    // Reserve space before Last/Exit/Max stages
    const hash = reflect.typeHash(T);
    const max_custom_range = std.math.maxInt(i32) - 2_000_000 - 100_000; // Leave buffer before Last
    return StageId.init(@intCast(2_000_000 + (@as(u32, @truncate(hash)) % @as(u32, max_custom_range))));
}

/// Get a stage ID that falls within a specified range.
pub inline fn StageInRange(comptime T: type, start: StageId, end: StageId) StageId {
    const base_stage = Stage(T);
    if (base_stage.value < start.value or base_stage.value > end.value) {
        const hash = reflect.typeHash(T);
        const range_size_i32 = end.value - start.value;
        const offset_u32 = @as(u32, @truncate(hash)) % @as(u32, range_size_i32);
        const offset: i32 = @intCast(offset_u32);
        return StageId.init(start.value + offset);
    }
    return base_stage;
}

const STAGE_GAP = 100_000;

/// Predefined execution stage types.
/// Use Stage(Stages.Update) to get the i32 value for use in scheduler.
///
/// Example Usage:
/// ```zig
/// // Predefined stages
/// scheduler.addSystem(Stage(Stages.Update), my_system, ParamRegistry);
///
/// // Custom stages
/// const MyStages = struct {
///     pub const EarlyGame = struct { pub const priority: i32 = 150_000; };
///     pub const CustomLogic = struct {}; // Gets hash-based ID
/// };
/// scheduler.addSystem(Stage(MyStages.EarlyGame), my_system, ParamRegistry);
/// ```
pub const Stages = struct {
    /// Minimum stage. PreStartup uses same priority as Min.
    pub const Min = struct {
        pub const priority: StageId = StageId.init(0);
    };
    /// Initialization stage.
    pub const PreStartup = struct {
        pub const priority: StageId = StageId.init(Min.priority.value);
    };
    pub const Startup = struct {
        // 1,000
        pub const priority: StageId = StageId.init(STAGE_GAP / 100);
    };
    /// First stage to be ran in the beginning of a update/draw/logic loop.
    pub const First = struct {
        // 100,000
        pub const priority: StageId = StageId.init(STAGE_GAP);
    };
    pub const PreUpdate = struct {
        // 200,000
        pub const priority: StageId = StageId.init(2 * STAGE_GAP);
    };
    pub const Update = struct {
        // 300,000
        pub const priority: StageId = StageId.init(3 * STAGE_GAP);
    };
    pub const PostUpdate = struct {
        // 400,000
        pub const priority: StageId = StageId.init(4 * STAGE_GAP);
    };
    pub const PreDraw = struct {
        // 500,000
        pub const priority: StageId = StageId.init(5 * STAGE_GAP);
    };
    pub const Draw = struct {
        // 600,000
        pub const priority: StageId = StageId.init(6 * STAGE_GAP);
    };
    pub const PostDraw = struct {
        // 700,000
        pub const priority: StageId = StageId.init(7 * STAGE_GAP);
    };

    /// Last stage to be ran in a update/draw/logic loop.
    pub const Last = struct {
        // 800,000
        pub const priority: StageId = StageId.init(8 * STAGE_GAP);
    };

    /// Internal use for States
    const StateTransition = struct {
        pub const priority: StageId = .init(1_000_000);
    };
    /// Internal use for States
    const StateOnExit = struct {
        pub const priority: StageId = .init(StateTransition.priority.value + STAGE_GAP);
    };
    /// Internal use for States
    const StateOnEnter = struct {
        pub const priority: StageId = .init(StateOnExit.priority.value + STAGE_GAP);
    };
    /// Internal use for States
    const StateUpdate = struct {
        pub const priority: StageId = .init(StateOnEnter.priority.value + STAGE_GAP);
    };

    /// Exit stage, final stage to run.
    /// Range Exit -> Max.
    pub const Exit = struct {
        pub const priority: StageId = StageId.init(std.math.maxInt(i32) - STAGE_GAP);
    };
    pub const Max = struct {
        pub const priority: StageId = StageId.init(std.math.maxInt(i32));
    };
};

/// Wraps a comptime tuple of systems into a chain entry for use with `addSystem`.
/// Systems in the chain run sequentially within a single concurrent task.
///
/// Example:
/// ```zig
/// scheduler.addSystem(ecs, Stage(Stages.Update), chain(.{ physics_step, collision_resolve }), ParamRegistry);
/// ```
pub fn chain(comptime systems_tuple: anytype) ChainEntry(@TypeOf(systems_tuple)) {
    return .{ .tuple = systems_tuple };
}

fn ChainEntry(comptime Tuple: type) type {
    return struct {
        pub const is_chain_entry = true;
        pub const TupleType = Tuple;
        tuple: Tuple,
    };
}

/// A single system or an ordered chain of systems run as one concurrent task.
pub const StageEntry = union(enum) {
    /// Runs as its own independent concurrent task.
    single: systems.UntypedSystemHandle,
    /// Multiple systems run sequentially within a single concurrent task.
    /// Slice is owned by the Scheduler and freed during deinit/removeStage.
    chain: []systems.UntypedSystemHandle,
};

/// Manages system execution order and stages.
///
/// Systems can be added to stages, and stages can be run in order.
/// Systems within a stage run concurrently by default; use `chain()` with
/// `addSystem` to express sequential ordering within a single concurrent task.
///
/// The scheduler can also register event types, which creates EventStore resources.
/// Includes integrated state management for application states.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    /// Thread pool backend for concurrent system dispatch.
    threaded: *std.Io.Threaded,
    systems: std.AutoHashMap(i32, std.ArrayList(StageEntry)),
    stage_order: std.ArrayList(i32),
    // State management - stores state enum type hash and current value
    states: std.AutoHashMap(u64, StateInfo),
    active_state: ?StateValue,

    const StateInfo = struct {
        type_name: []const u8,
        enum_type_hash: u64,
    };

    const StateValue = struct {
        enum_type_hash: u64, // Hash of the enum type
        value_hash: u64, // Hash of the specific enum value
        value_name: []const u8, // Name of the enum value for debugging
    };

    pub const StageInfo = struct {
        stage: StageId,
        system_count: usize,
    };

    /// List of all predefined stages for initialization
    const predefined_stages = [_]i32{
        Stage(Stages.Min).value,
        Stage(Stages.PreStartup).value,
        Stage(Stages.Startup).value,
        Stage(Stages.First).value,
        Stage(Stages.PreUpdate).value,
        Stage(Stages.Update).value,
        Stage(Stages.PostUpdate).value,
        Stage(Stages.PreDraw).value,
        Stage(Stages.Draw).value,
        Stage(Stages.PostDraw).value,
        Stage(Stages.StateTransition).value,
        Stage(Stages.StateOnExit).value,
        Stage(Stages.StateOnEnter).value,
        Stage(Stages.StateUpdate).value,
        Stage(Stages.Last).value,
        Stage(Stages.Max).value, // Exit and Max are the same value now
    };

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!Scheduler {
        const threaded = try allocator.create(std.Io.Threaded);
        errdefer {
            threaded.deinit();
            allocator.destroy(threaded);
        }
        threaded.* = std.Io.Threaded.init(std.heap.page_allocator, .{});
        var _systems = std.AutoHashMap(i32, std.ArrayList(StageEntry)).init(allocator);
        errdefer {
            var cleanup_it = _systems.iterator();
            while (cleanup_it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            _systems.deinit();
        }

        var _stage_order = try std.ArrayList(i32).initCapacity(allocator, predefined_stages.len);
        errdefer _stage_order.deinit(allocator);

        for (predefined_stages) |stage| {
            const gop = try _systems.getOrPut(stage);
            if (gop.found_existing) continue;

            gop.value_ptr.* = .empty;
            gop.value_ptr.* = try std.ArrayList(StageEntry).initCapacity(allocator, 0);
            try insertStageValueSorted(allocator, &_stage_order, stage);
        }
        const self: Scheduler = .{
            .allocator = allocator,
            .threaded = threaded,
            .systems = _systems,
            .stage_order = _stage_order,
            .states = std.AutoHashMap(u64, StateInfo).init(allocator),
            .active_state = null,
        };

        return self;
    }

    pub fn deinit(self: *Scheduler) void {
        var it = self.systems.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |stage_entry| {
                switch (stage_entry) {
                    .chain => |handles| self.allocator.free(handles),
                    .single => {},
                }
            }
            entry.value_ptr.deinit(self.allocator);
        }
        self.systems.deinit();
        self.stage_order.deinit(self.allocator);
        self.states.deinit();
        self.threaded.deinit();
        self.allocator.destroy(self.threaded);
    }

    fn ensureStageList(self: *Scheduler, stage: StageId, initial_capacity: usize) error{OutOfMemory}!*std.ArrayList(StageEntry) {
        const gop = try self.systems.getOrPut(stage.value);
        if (!gop.found_existing) {
            errdefer _ = self.systems.remove(stage.value);

            gop.value_ptr.* = .empty;
            errdefer gop.value_ptr.deinit(self.allocator);

            gop.value_ptr.* = try std.ArrayList(StageEntry).initCapacity(self.allocator, initial_capacity);
            try insertStageValueSorted(self.allocator, &self.stage_order, stage.value);
        }

        return gop.value_ptr;
    }

    inline fn insertStage(self: *Scheduler, stage: StageId, initial_capacity: usize) error{ InvalidStageBounds, StageExists, OutOfMemory }!void {
        if (stage.value < Stage(Stages.Min).value or stage.value > Stage(Stages.Max).value) {
            return error.InvalidStageBounds;
        }

        const gop = try self.systems.getOrPut(stage.value);
        if (gop.found_existing) {
            return error.StageExists;
        }

        errdefer _ = self.systems.remove(stage.value);

        gop.value_ptr.* = .empty;
        errdefer gop.value_ptr.deinit(self.allocator);

        gop.value_ptr.* = try std.ArrayList(StageEntry).initCapacity(self.allocator, initial_capacity);
        try insertStageValueSorted(self.allocator, &self.stage_order, stage.value);
    }

    pub fn addSystem(self: *Scheduler, ecs: *ecs_mod.Manager, stage: StageId, system: anytype, comptime param_registry: type) void {
        const stage_list = self.ensureStageList(stage, 4) catch |err| @panic(@errorName(err));
        const SystemType = @TypeOf(system);
        // Detect chain entries created by chain()
        if (comptime @typeInfo(SystemType) == .@"struct" and @hasDecl(SystemType, "is_chain_entry")) {
            const tuple_info = @typeInfo(SystemType.TupleType);
            const field_count = tuple_info.@"struct".fields.len;
            if (field_count == 0) return;
            var handles_list = std.ArrayList(systems.UntypedSystemHandle).initCapacity(
                self.allocator,
                field_count,
            ) catch |err| @panic(@errorName(err));
            inline for (tuple_info.@"struct".fields) |field| {
                const sys = @field(system.tuple, field.name);
                const SysType = @TypeOf(sys);
                const untyped = switch (comptime systems.getSystemTypeFromType(SysType)) {
                    .func => ecs.createSystemCached(sys, param_registry).eraseType(),
                    .handle => sys.eraseType(),
                    .untyped => sys,
                    .system => ecs.cacheSystem(sys).eraseType(),
                    else => std.debug.panic("chain: invalid system type: {s}", .{@typeName(SysType)}),
                };
                handles_list.appendAssumeCapacity(untyped);
            }
            const owned_handles = handles_list.toOwnedSliceAssert();
            stage_list.append(self.allocator, StageEntry{ .chain = owned_handles }) catch |err| @panic(@errorName(err));
            return;
        }
        const untyped_system_handle = switch (comptime systems.getSystemTypeFromType(SystemType)) {
            .func => ecs.createSystemCached(system, param_registry).eraseType(),
            .handle => system.eraseType(),
            .untyped => system,
            .system => ecs.cacheSystem(system).eraseType(),
            else => std.debug.panic("Invalid system type: {s}. Expected a function, SystemHandle, System(T), or chain().", .{@typeName(SystemType)}),
        };
        stage_list.append(self.allocator, StageEntry{ .single = untyped_system_handle }) catch |err| @panic(@errorName(err));
    }

    pub fn addStage(self: *Scheduler, stage: StageId) error{ InvalidStageBounds, StageExists, OutOfMemory }!void {
        try self.insertStage(stage, 4);
    }

    pub fn removeStage(self: *Scheduler, stage: StageId) error{StageHasNoSystems}!void {
        if (self.systems.fetchRemove(stage.value)) |kv| {
            for (kv.value.items) |stage_entry| {
                switch (stage_entry) {
                    .chain => |handles| self.allocator.free(handles),
                    .single => {},
                }
            }
            var list = kv.value;
            list.deinit(self.allocator);
            removeStageValue(&self.stage_order, stage.value);
        } else {
            return error.StageHasNoSystems;
        }
    }

    /// Run all systems in a stage concurrently.
    /// Each `addSystem` single entry runs as its own async task; each `chain()`
    /// entry runs sequentially within a single async task.
    /// Commands flushing is deferred until all tasks complete.
    pub inline fn runStage(self: *Scheduler, ecs: *ecs_mod.Manager, stage: StageId) anyerror!void {
        const list = self.systems.get(stage.value) orelse return error.StageHasNoSystems;
        if (list.items.len == 0) {
            discardHandledComponentEventsIfLastStage(ecs, stage);
            return;
        }

        // Set up DeferredFlusher so Commands params on worker threads defer
        // flushing instead of executing immediately (not thread-safe for Manager).
        var flusher = ecs_mod.DeferredFlusher.init(ecs.allocator);
        defer flusher.deinit();
        ecs.deferred_flusher = &flusher;
        defer ecs.deferred_flusher = null;

        const io = self.threaded.io();

        // Pre-allocate futures to avoid OOM after tasks are already dispatched.
        var futures = try std.ArrayList(std.Io.Future(anyerror!void)).initCapacity(self.allocator, list.items.len);
        defer futures.deinit(self.allocator);

        // Dispatch each stage entry as an async task.
        for (list.items) |entry| {
            switch (entry) {
                .single => |handle| {
                    futures.appendAssumeCapacity(io.async(runSingleTask, .{ ecs, handle }));
                },
                .chain => |handles| {
                    futures.appendAssumeCapacity(io.async(runChainTask, .{ ecs, handles }));
                },
            }
        }

        // Await all futures. Always wait for everything even on error.
        var first_err: ?anyerror = null;
        for (futures.items) |*future| {
            if (future.await(io)) |_| {} else |err| {
                if (first_err == null) first_err = err;
            }
        }

        // Disable deferred mode before flushing.
        ecs.deferred_flusher = null;

        // Flush all deferred Commands serially on the main thread.
        flusher.flushAll(ecs) catch |err| {
            if (first_err == null) first_err = err;
        };

        discardHandledComponentEventsIfLastStage(ecs, stage);

        if (first_err) |err| return err;
    }

    pub fn runStages(self: *Scheduler, ecs: *ecs_mod.Manager, start: StageId, end: StageId) anyerror!void {
        if (start.value > end.value) return;

        for (self.stage_order.items) |stage_value| {
            if (stage_value < start.value) continue;
            if (stage_value > end.value) break;

            try self.runStage(ecs, StageId.init(stage_value));
        }
    }

    pub fn getStageInfo(self: *Scheduler, allocator: std.mem.Allocator) std.ArrayList(StageInfo) {
        var info_list = std.ArrayList(StageInfo).initCapacity(allocator, self.systems.count()) catch |err| @panic(@errorName(err));

        for (self.stage_order.items) |stage_value| {
            const stage_list = self.systems.get(stage_value) orelse continue;
            info_list.append(allocator, .{
                .stage = StageId.init(stage_value),
                .system_count = stage_list.items.len,
            }) catch |err| @panic(@errorName(err));
        }

        return info_list;
    }

    /// Register an event with the scheduler
    /// This creates an EventStore resource and adds a cleanup system at the Last stage
    pub fn registerEvent(self: *Scheduler, ecs: *ecs_mod.Manager, comptime T: type, comptime ParamRegistry: type) ecs_mod.errors!void {
        return self.registerEventWithCleanupAtStage(ecs, T, Stage(Stages.Last), ParamRegistry);
    }

    /// Register an event with cleanup at a specific stage
    pub fn registerEventWithCleanupAtStage(
        self: *Scheduler,
        ecs: *ecs_mod.Manager,
        comptime T: type,
        cleanup_stage: StageId,
        comptime ParamRegistry: type,
    ) error{OutOfMemory}!void {
        if (!ecs.hasResource(events.EventStore(T))) {
            _ = ecs.addResource(events.EventStore(T), try events.EventStore(T).init(ecs.allocator, 10)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.ResourceAlreadyExists => std.debug.panic("Resource already exists when adding EventStore for newly registered event type: {s}", .{@typeName(T)}),
            };
        }

        // Create cleanup system that discards handled and unhandled events (consumes them)
        const cleanup_system = struct {
            pub fn cleanup(store_res: *params.Res(events.EventStore(T))) void {
                store_res.get().discardHandled();
                store_res.get().discardUnhandled();
            }
        }.cleanup;

        // Add cleanup system
        self.addSystem(ecs, cleanup_stage, cleanup_system, ParamRegistry);
    }

    // ============================================================================
    // State Management Methods
    // ============================================================================

    /// Register a new state enum type with the scheduler.
    /// StateEnum must be an enum type.
    /// Automatically adds the StateManager resource to the ECS
    pub fn registerState(
        self: *Scheduler,
        ecs: *ecs_mod.Manager,
        comptime StateEnum: type,
    ) error{ StateAlreadyRegistered, ExpectedEnumType, ResourceAlreadyExists, OutOfMemory }!void {
        const type_info = @typeInfo(StateEnum);
        if (type_info != .@"enum") {
            return error.ExpectedEnumType;
        }

        const type_hash = reflect.typeHash(StateEnum);

        // Check if state type is already registered
        if (self.states.contains(type_hash)) {
            return error.StateAlreadyRegistered;
        }

        // Store state enum type info
        try self.states.put(type_hash, StateInfo{
            .type_name = @typeName(StateEnum),
            .enum_type_hash = type_hash,
        });

        // Automatically add StateManager resource for this state type
        const state_mgr = self.getStateManager(ecs, StateEnum);
        _ = try ecs.addResource(state_mod.StateManager(StateEnum), state_mgr);
    }

    /// Check if a specific state value is currently active
    pub fn isInState(self: *Scheduler, comptime StateEnum: type, state: StateEnum) bool {
        const type_hash = reflect.typeHash(StateEnum);
        const value_hash = reflect.hash(@tagName(state));

        if (self.active_state) |active| {
            return active.enum_type_hash == type_hash and active.value_hash == value_hash;
        }
        return false;
    }

    /// Get the currently active state of a specific enum type
    pub fn getActiveState(self: *Scheduler, comptime StateEnum: type) ?StateEnum {
        const type_hash = reflect.typeHash(StateEnum);

        if (self.active_state) |active| {
            if (active.enum_type_hash == type_hash) {
                // Parse the value name back to enum value
                inline for (@typeInfo(StateEnum).@"enum".fields) |field| {
                    if (std.mem.eql(u8, field.name, active.value_name)) {
                        return @enumFromInt(field.value);
                    }
                }
            }
        }
        return null;
    }

    /// Get the type name of the currently active state enum
    pub fn getActiveStateName(self: *Scheduler) ?[]const u8 {
        if (self.active_state) |active| {
            return active.value_name;
        }
        return null;
    }

    /// Transition to a new state immediately
    /// This will run OnExit systems for the previous state and OnEnter systems for the new state
    pub fn transitionTo(
        self: *Scheduler,
        ecs: *ecs_mod.Manager,
        comptime StateEnum: type,
        state: StateEnum,
    ) error{StateNotRegistered}!void {
        const type_hash = reflect.typeHash(StateEnum);

        // Verify the state enum type is registered
        if (!self.states.contains(type_hash)) return error.StateNotRegistered;

        const value_hash = reflect.hash(@tagName(state));
        const value_name = @tagName(state);

        // Don't transition if already in this state
        if (self.active_state) |current| {
            if (current.enum_type_hash == type_hash and current.value_hash == value_hash) {
                return;
            }
        }

        // Run OnExit systems for the previous state (if any)
        if (self.active_state) |old_state| {
            if (old_state.enum_type_hash == type_hash) {
                // Calculate OnExit stage for the old state
                const old_combined_hash = reflect.hashWithSeed(std.mem.asBytes(&old_state.value_hash), old_state.enum_type_hash);
                const old_stage_offset: u32 = @intCast(@as(u32, @truncate(old_combined_hash)) % 100_000);
                const exit_stage = Stage(Stages.StateOnExit).add(old_stage_offset);
                // Run the OnExit stage if it exists (don't error if it doesn't)
                self.runStage(ecs, exit_stage) catch {};
            }
        }

        // Apply the state transition immediately
        self.active_state = StateValue{
            .enum_type_hash = type_hash,
            .value_hash = value_hash,
            .value_name = value_name,
        };

        // Run OnEnter systems for the new state
        // Calculate OnEnter stage for the new state
        const new_combined_hash = reflect.hashWithSeed(std.mem.asBytes(&value_hash), type_hash);
        const new_stage_offset: u32 = @intCast(@as(u32, @truncate(new_combined_hash)) % 100_000);
        const enter_stage = Stage(Stages.StateOnEnter).add(new_stage_offset);
        // Run the OnEnter stage if it exists (don't error if it doesn't)
        self.runStage(ecs, enter_stage) catch {};
    }

    /// Run InState systems for a specific state value
    /// This runs systems that were registered with InState(state_value)
    pub fn runInStateSystems(
        self: *Scheduler,
        ecs: *ecs_mod.Manager,
        comptime StateEnum: type,
        state: StateEnum,
    ) !void {
        const type_hash = reflect.typeHash(StateEnum);
        const value_hash = reflect.hash(@tagName(state));
        const combined_hash = reflect.hashWithSeed(std.mem.asBytes(&value_hash), type_hash);
        const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
        const state_stage = Stage(Stages.StateUpdate).add(stage_offset);

        // Run the InState stage if it exists (don't error if it doesn't)
        self.runStage(ecs, state_stage) catch {};
    }

    /// Run InState systems for the currently active state
    /// This is a convenience method that automatically runs the correct InState systems
    pub fn runActiveStateSystems(self: *Scheduler, ecs: *ecs_mod.Manager, comptime StateEnum: type) !void {
        if (self.getActiveState(StateEnum)) |active_state| {
            try self.runInStateSystems(ecs, StateEnum, active_state);
        }
    }

    /// Get a StateManager wrapper for use in systems
    /// This provides a convenient interface for systems to access state management via Res(StateManager(StateEnum))
    pub fn getStateManager(self: *Scheduler, ecs: *ecs_mod.Manager, comptime StateEnum: type) state_mod.StateManager(StateEnum) {
        return state_mod.StateManager(StateEnum){
            .scheduler = self,
            .ecs = ecs,
        };
    }
};
// ============================================================================
// Private helpers for async task dispatch
// ============================================================================

fn runSingleTask(ecs: *ecs_mod.Manager, handle: systems.UntypedSystemHandle) anyerror!void {
    return ecs.runSystemUntyped(void, handle);
}

fn runChainTask(ecs: *ecs_mod.Manager, handles: []systems.UntypedSystemHandle) anyerror!void {
    for (handles) |handle| {
        try ecs.runSystemUntyped(void, handle);
    }
}

inline fn insertStageValueSorted(allocator: std.mem.Allocator, stage_values: *std.ArrayList(i32), stage_value: i32) error{OutOfMemory}!void {
    var insert_index: usize = 0;
    while (insert_index < stage_values.items.len and stage_values.items[insert_index] < stage_value) : (insert_index += 1) {}

    if (insert_index < stage_values.items.len and stage_values.items[insert_index] == stage_value) {
        return;
    }

    try stage_values.insert(allocator, insert_index, stage_value);
}

fn removeStageValue(stage_values: *std.ArrayList(i32), stage_value: i32) void {
    for (stage_values.items, 0..) |current_stage, index| {
        if (current_stage == stage_value) {
            _ = stage_values.orderedRemove(index);
            return;
        }
    }
}

fn discardHandledComponentEventsIfLastStage(ecs: *ecs_mod.Manager, stage: StageId) void {
    if (!stage.eql(Stage(Stages.Last))) return;

    ecs.component_added.discardHandled();
    ecs.component_removed.discardHandled();
}

/// Returns a temporary stage ID for systems that should run when entering a specific state
/// Usage: scheduler.addSystem(OnEnter(GameState.Playing), my_system_handle)
pub inline fn OnEnter(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("OnEnter requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateOnEnter base stage + hash of type name and value name
    const type_hash = reflect.typeHash(StateEnum);
    const value_hash = reflect.hash(@tagName(state));
    const combined_hash = reflect.hashWithSeed(std.mem.asBytes(&value_hash), type_hash);

    // Map hash to a range within StateOnEnter stage area (1,200,000 - 1,299,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateOnEnter).add(stage_offset);
}

/// Returns a temporary stage ID for systems that should run when exiting a specific state
/// Usage: scheduler.addSystem(OnExit(GameState.Playing), my_cleanup_system_handle)
pub inline fn OnExit(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("OnExit requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateOnExit base stage + hash of type name and value name
    const type_hash = reflect.typeHash(StateEnum);
    const value_hash = reflect.hash(@tagName(state));
    const combined_hash = reflect.hashWithSeed(std.mem.asBytes(&value_hash), type_hash);

    // Map hash to a range within StateOnExit stage area (1,100,000 - 1,199,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateOnExit).add(stage_offset);
}

/// Returns a temporary stage ID for systems that should run only while in a specific state
/// Usage: scheduler.addSystem(InState(GameState.Playing), gameplay_system_handle)
pub inline fn InState(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("InState requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateUpdate base stage + hash of type name and value name
    const type_hash = reflect.typeHash(StateEnum);
    const value_hash = reflect.hash(@tagName(state));
    const combined_hash = reflect.hashWithSeed(std.mem.asBytes(&value_hash), type_hash);

    // Map hash to a range within StateUpdate stage area (1,300,000 - 1,399,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateUpdate).add(stage_offset);
}

// Test the registerEventType functionality
test "Scheduler registerEventType" {
    const allocator = std.testing.allocator;

    // Define a test event type
    const TestEvent = struct {
        id: u32,
        message: []const u8,
    };

    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Register the event type
    scheduler.registerEvent(&ecs, TestEvent, registry.DefaultParamRegistry) catch |err| {
        return err;
    };

    std.testing.expect(ecs.hasResource(events.EventStore(TestEvent))) catch {
        std.debug.print("Failed to find EventStore resource for TestEvent\n", .{});
        return error.FailedToFindEventStore;
    };

    // Verify a cleanup system was added to the Last stage
    var stage_info = scheduler.getStageInfo(std.testing.allocator);
    defer stage_info.deinit(std.testing.allocator);

    // Find the Last stage
    var found_last_stage = false;
    for (stage_info.items) |info| {
        if (info.stage.eql(Stage(Stages.Last))) {
            std.testing.expect(info.system_count >= 1) catch {
                std.debug.print("Expected at least one system in Last stage, found {d}\n", .{info.system_count});
                return error.UnexpectedSystemCount;
            };
            found_last_stage = true;
            break;
        }
    }
    std.testing.expect(found_last_stage) catch {
        std.debug.print("Failed to find Last stage in stage info\n", .{});
        return error.LastStageNotFound;
    };
}

test "Scheduler addStage" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const first_custom_stage = StageId.init(350_000);
    const second_custom_stage = StageId.init(150_000);
    const third_custom_stage = StageId.init(250_000);
    const invalid_stage = StageId.init(-1);

    try scheduler.addStage(first_custom_stage);
    try scheduler.addStage(second_custom_stage);
    try scheduler.addStage(third_custom_stage);

    try std.testing.expect(scheduler.systems.contains(first_custom_stage.value));
    try std.testing.expect(scheduler.systems.contains(second_custom_stage.value));
    try std.testing.expect(scheduler.systems.contains(third_custom_stage.value));
    try std.testing.expectError(error.StageExists, scheduler.addStage(first_custom_stage));
    try std.testing.expectError(error.InvalidStageBounds, scheduler.addStage(invalid_stage));
    try std.testing.expect(!scheduler.systems.contains(invalid_stage.value));

    var found_first = false;
    var found_second = false;
    var found_third = false;
    for (scheduler.stage_order.items, 0..) |stage_value, index| {
        if (index > 0) {
            try std.testing.expect(scheduler.stage_order.items[index - 1] < stage_value);
        }

        if (stage_value == first_custom_stage.value) found_first = true;
        if (stage_value == second_custom_stage.value) found_second = true;
        if (stage_value == third_custom_stage.value) found_third = true;
    }

    try std.testing.expect(found_first);
    try std.testing.expect(found_second);
    try std.testing.expect(found_third);
}

test "Scheduler getStageInfo" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    var info = scheduler.getStageInfo(allocator);
    defer info.deinit(allocator);

    // Note: Exit and Max have the same value, so we expect one less unique stage
    // predefined_stages has 16 entries but only 15 unique stage IDs
    const expected_unique_stages = 15;
    try std.testing.expect(info.items.len >= expected_unique_stages);

    // Check that all unique predefined stages are present
    // Build a set of unique stage IDs from predefined_stages
    var unique_stages = std.AutoHashMap(i32, void).init(allocator);
    defer unique_stages.deinit();
    for (Scheduler.predefined_stages) |stage| {
        try unique_stages.put(stage, {});
    }

    // Verify each unique stage is in the info list
    var it = unique_stages.keyIterator();
    while (it.next()) |stage_ptr| {
        var found = false;
        for (info.items) |i| {
            if (i.stage.eql(StageId.init(stage_ptr.*))) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "Scheduler runStage on non-existing stage" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    try std.testing.expectError(error.StageHasNoSystems, scheduler.runStage(&ecs, .init(9999)));
}

test "Scheduler assign outside scope" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add a custom stage and a system to it
    const custom_stage = StageId.init(150_000); // Between First (100,000) and PreUpdate (200,000)
    _ = try ecs.addResource(bool, false);
    try scheduler.addStage(custom_stage);
    const test_system = struct {
        pub fn run(out: *params.Res(bool)) void {
            out.get().* = true;
        }
    }.run;

    scheduler.addSystem(&ecs, custom_stage, test_system, registry.DefaultParamRegistry);

    // Run stages from First to PostUpdate, which includes the custom stage
    try scheduler.runStages(&ecs, Stage(Stages.First), Stage(Stages.PostUpdate));

    var out_ref = ecs.getResource(bool).?;
    defer out_ref.deinit();
    var out_guard = out_ref.lock();
    defer out_guard.deinit();
    try std.testing.expect(out_guard.get().* == true);
}

test "Scheduler runStages executes custom stages in sorted order" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const ExecutionTrace = struct {
        values: [3]i32 = .{ 0, 0, 0 },
        len: usize = 0,
    };
    const EarlyMarker = struct {};
    const MiddleMarker = struct {};
    const LateMarker = struct {};

    _ = try ecs.addResource(ExecutionTrace, .{});
    _ = try ecs.addResource(EarlyMarker, .{});
    _ = try ecs.addResource(MiddleMarker, .{});
    _ = try ecs.addResource(LateMarker, .{});

    const early_stage = StageId.init(150_000);
    const middle_stage = StageId.init(250_000);
    const late_stage = StageId.init(350_000);

    const record_early = struct {
        fn run(trace: *params.Res(ExecutionTrace), _: *params.Res(EarlyMarker)) void {
            const trace_data = trace.get();
            trace_data.values[trace_data.len] = 150_000;
            trace_data.len += 1;
        }
    }.run;
    const record_middle = struct {
        fn run(trace: *params.Res(ExecutionTrace), _: *params.Res(MiddleMarker)) void {
            const trace_data = trace.get();
            trace_data.values[trace_data.len] = 250_000;
            trace_data.len += 1;
        }
    }.run;
    const record_late = struct {
        fn run(trace: *params.Res(ExecutionTrace), _: *params.Res(LateMarker)) void {
            const trace_data = trace.get();
            trace_data.values[trace_data.len] = 350_000;
            trace_data.len += 1;
        }
    }.run;

    scheduler.addSystem(&ecs, late_stage, record_late, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, early_stage, record_early, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, middle_stage, record_middle, registry.DefaultParamRegistry);

    try scheduler.runStages(&ecs, Stage(Stages.First), Stage(Stages.PostUpdate));

    const trace_res = ecs.getResource(ExecutionTrace).?;
    defer trace_res.deinit();
    var trace_guard = trace_res.lock();
    defer trace_guard.deinit();

    try std.testing.expectEqual(@as(usize, 3), trace_guard.get().len);
    try std.testing.expectEqual(@as(i32, 150_000), trace_guard.get().values[0]);
    try std.testing.expectEqual(@as(i32, 250_000), trace_guard.get().values[1]);
    try std.testing.expectEqual(@as(i32, 350_000), trace_guard.get().values[2]);
}

test "Scheduler discards handled component events in Last stage" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const commands_mod = @import("commands.zig");

    const Tag = struct { value: u32 };
    const AddedCount = struct { value: usize };

    const entity = ecs.createEmpty();
    _ = try ecs.addResource(AddedCount, .{ .value = 0 });

    const add_tag = struct {
        fn run(ent: ecs_mod.Entity, cmds: *commands_mod.Commands) void {
            cmds.addComponent(ent, Tag, .{ .value = 42 }) catch {};
        }
    }.run;
    const count_added = struct {
        fn run(count: *params.Res(AddedCount), added: params.OnAdded(Tag)) void {
            count.get().value = added.items.len;
        }
    }.run;

    const add_tag_system = systems.ToSystemWithArgs(add_tag, .{entity}, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(Stages.Update), add_tag_system, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(Stages.PostUpdate), count_added, registry.DefaultParamRegistry);

    try scheduler.runStage(&ecs, Stage(Stages.Update));
    try std.testing.expectEqual(@as(usize, 1), ecs.component_added.count());
    try std.testing.expect(!ecs.component_added.peek().?.handled);

    try scheduler.runStage(&ecs, Stage(Stages.PostUpdate));
    try std.testing.expectEqual(@as(usize, 1), ecs.component_added.count());
    try std.testing.expect(ecs.component_added.peek().?.handled);

    try scheduler.runStage(&ecs, Stage(Stages.Last));
    try std.testing.expectEqual(@as(usize, 0), ecs.component_added.count());
}

test "Custom stage types with explicit priorities" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Define custom stages with explicit priorities
    const CustomStages = struct {
        pub const EarlyGame = struct {
            pub const priority: StageId = .init(50_000); // Between Startup and First
        };
        pub const LateUpdate = struct {
            pub const priority: StageId = .init(350_000); // Between Update and PostUpdate
        };
        pub const PreCleanup = struct {
            pub const priority: StageId = .init(750_000); // Between PostDraw and Last
        };
    };

    // Add systems to custom stages
    const test_sys = struct {
        pub fn run(_: *ecs_mod.Manager) void {}
    }.run;

    scheduler.addSystem(&ecs, Stage(CustomStages.EarlyGame), test_sys, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(CustomStages.LateUpdate), test_sys, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(CustomStages.PreCleanup), test_sys, registry.DefaultParamRegistry);

    // Verify stages have correct priority values
    try std.testing.expect(Stage(CustomStages.EarlyGame).value == 50_000);
    try std.testing.expect(Stage(CustomStages.LateUpdate).value == 350_000);
    try std.testing.expect(Stage(CustomStages.PreCleanup).value == 750_000);

    // Verify stages were added to scheduler
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.EarlyGame).value));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.LateUpdate).value));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.PreCleanup).value));
}

test "Custom stage types with hash-based IDs" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Define custom stages without priorities (will get hash-based IDs)
    const CustomStages = struct {
        pub const Physics = struct {};
        pub const Audio = struct {};
        pub const Networking = struct {};
    };

    // Add systems to custom stages
    const test_sys = struct {
        pub fn run() void {}
    }.run;

    scheduler.addSystem(&ecs, Stage(CustomStages.Physics), test_sys, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(CustomStages.Audio), test_sys, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(CustomStages.Networking), test_sys, registry.DefaultParamRegistry);

    // Verify hash-based IDs are in the correct range (2M+)
    try std.testing.expect(Stage(CustomStages.Physics).value >= 2_000_000);
    try std.testing.expect(Stage(CustomStages.Audio).value >= 2_000_000);
    try std.testing.expect(Stage(CustomStages.Networking).value >= 2_000_000);

    // Verify different types get different IDs
    try std.testing.expect(Stage(CustomStages.Physics).value != Stage(CustomStages.Audio).value);
    try std.testing.expect(Stage(CustomStages.Audio).value != Stage(CustomStages.Networking).value);
    try std.testing.expect(Stage(CustomStages.Physics).value != Stage(CustomStages.Networking).value);

    // Verify stages were added to scheduler
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Physics).value));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Audio).value));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Networking).value));
}

test "StageInRange returns base if in range and maps out-of-range to within range" {

    // Priority-based type that sits in the range
    const InRange = struct {
        pub const priority: StageId = .init(150);
    };
    try std.testing.expect(StageInRange(InRange, .init(100), .init(200)).value == 150);

    // Priority-based type outside the range should be mapped into it
    const OutRangePriority = struct {
        pub const priority: StageId = .init(800);
    };
    const mapped_priority = StageInRange(OutRangePriority, .init(100), .init(200));
    try std.testing.expect(mapped_priority.value >= 100);
    try std.testing.expect(mapped_priority.value < 200);

    // Non-priority (hash-based) type should also be mapped into the given range
    const HashBased = struct {};
    const start = StageId.init(2_000_000);
    const end = StageId.init(2_000_100);
    const mapped_hash = StageInRange(HashBased, start, end);
    try std.testing.expect(mapped_hash.value >= start.value);
    try std.testing.expect(mapped_hash.value < end.value);

    // Sanity: start must be less than end
    try std.testing.expect(start.value < end.value);
}

test "State management without registration throws errors" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
        Paused,
    };

    // Test 1: transitionTo without registration should return error.StateNotRegistered
    const transition_result = scheduler.transitionTo(&ecs, GameState, .Menu);
    try std.testing.expectError(error.StateNotRegistered, transition_result);

    // Test 2: Verify isInState returns false when state not registered
    const is_in_state = scheduler.isInState(GameState, .Menu);
    try std.testing.expect(is_in_state == false);

    // Test 3: Verify getActiveState returns null when state not registered
    const active_state = scheduler.getActiveState(GameState);
    try std.testing.expect(active_state == null);
}

// ============================================================================
// Async / concurrent execution tests
// ============================================================================

test "Concurrent stage: two independent systems both run" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    // Two distinct resource types written by separate systems.
    const AValue = struct { v: u32 };
    const BValue = struct { v: u32 };

    _ = try ecs.addResource(AValue, .{ .v = 0 });
    _ = try ecs.addResource(BValue, .{ .v = 0 });

    const sysA = struct {
        fn run(res: *params.Res(AValue)) void {
            res.get().v = 111;
        }
    }.run;

    const sysB = struct {
        fn run(res: *params.Res(BValue)) void {
            res.get().v = 222;
        }
    }.run;

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    scheduler.addSystem(&ecs, Stage(Stages.Update), sysA, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, Stage(Stages.Update), sysB, registry.DefaultParamRegistry);

    try scheduler.runStage(&ecs, Stage(Stages.Update));

    {
        const ra = ecs.getResource(AValue).?;
        defer ra.deinit();
        var ga = ra.lock();
        defer ga.deinit();
        try std.testing.expectEqual(@as(u32, 111), ga.get().v);
    }
    {
        const rb = ecs.getResource(BValue).?;
        defer rb.deinit();
        var gb = rb.lock();
        defer gb.deinit();
        try std.testing.expectEqual(@as(u32, 222), gb.get().v);
    }
}

test "chain(): systems within a chain run in order" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    // Use distinct resource types so each system has a unique signature and
    // can be cached independently by createSystemCached.
    const A = struct { v: u32 };
    const B = struct { v: u32 };
    const C = struct { v: u32 };
    _ = try ecs.addResource(A, .{ .v = 0 });
    _ = try ecs.addResource(B, .{ .v = 0 });
    _ = try ecs.addResource(C, .{ .v = 0 });

    // sys1 → A.v = 1
    // sys2 reads A.v, writes B.v = A.v + 10  (proves sys2 runs after sys1)
    // sys3 reads B.v, writes C.v = B.v + 100  (proves sys3 runs after sys2)
    const sys1 = struct {
        fn run(a: *params.Res(A)) void {
            a.get().v = 1;
        }
    }.run;
    const sys2 = struct {
        fn run(a: *params.Res(A), b: *params.Res(B)) void {
            b.get().v = a.get().v + 10;
        }
    }.run;
    const sys3 = struct {
        fn run(b: *params.Res(B), c: *params.Res(C)) void {
            c.get().v = b.get().v + 100;
        }
    }.run;

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    scheduler.addSystem(&ecs, Stage(Stages.Update), chain(.{ sys1, sys2, sys3 }), registry.DefaultParamRegistry);

    try scheduler.runStage(&ecs, Stage(Stages.Update));

    const ra = ecs.getResource(A).?;
    defer ra.deinit();
    var ga = ra.lock();
    defer ga.deinit();
    try std.testing.expectEqual(@as(u32, 1), ga.get().v);

    const rb = ecs.getResource(B).?;
    defer rb.deinit();
    var gb = rb.lock();
    defer gb.deinit();
    try std.testing.expectEqual(@as(u32, 11), gb.get().v); // 1 + 10

    const rc = ecs.getResource(C).?;
    defer rc.deinit();
    var gc = rc.lock();
    defer gc.deinit();
    try std.testing.expectEqual(@as(u32, 111), gc.get().v); // 11 + 100
}

test "Concurrent stage: Commands deferred flush adds components" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    const commands_mod = @import("commands.zig");
    const Tag = struct { value: u32 };

    // Create the target entity on the main thread before the stage runs.
    const entity = ecs.createEmpty();

    // System takes the entity as its first (injected) arg and queues addComponent.
    // Commands flushing is deferred by CommandsSystemParam.deinit until all stage
    // futures settle, so the mutation reaches the Manager safely on the main thread.
    const tagSys = struct {
        fn run(ent: ecs_mod.Entity, cmds: *commands_mod.Commands) void {
            cmds.addComponent(ent, Tag, .{ .value = 99 }) catch {};
        }
    }.run;

    // Bind the runtime entity via ToSystemWithArgs, then hand the pre-built
    // System(void) to addSystem via the .system / cacheSystem path.
    const prebuilt = systems.ToSystemWithArgs(tagSys, .{entity}, registry.DefaultParamRegistry);

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    scheduler.addSystem(&ecs, Stage(Stages.Update), prebuilt, registry.DefaultParamRegistry);

    try scheduler.runStage(&ecs, Stage(Stages.Update));

    // Component must exist after runStage — proving deferred flush ran.
    const tag = try ecs.getComponent(entity, Tag);
    try std.testing.expect(tag != null);
    if (tag) |t| try std.testing.expectEqual(@as(u32, 99), t.value);
}
