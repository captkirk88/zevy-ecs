const std = @import("std");
const ecs_mod = @import("ecs.zig");
const events = @import("events.zig");
const registry = @import("systems.registry.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");
const state_mod = @import("state.zig");
const reflect = @import("zevy_reflect");

const is_debug = @import("builtin").mode == .Debug;

/// Stage ID type (internal representation)
pub const StageId = struct {
    value: i32,

    pub inline fn init(value: i32) StageId {
        return StageId{ .value = value };
    }

    pub inline fn initDebug(value: i32, comptime _T: type) StageId {
        // Keep API compatible but do not store slices in the struct
        comptime {
            // reference _T at comptime so the parameter is considered used
            _ = reflect.getSimpleTypeName(_T);
        }
        return init(value);
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
    if (comptime reflect.getTypeInfo(T).hasDecl("priority")) {
        return T.priority;
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
/// scheduler.addSystem(Stage(Stages.Update), my_system);
///
/// // Custom stages
/// const MyStages = struct {
///     pub const EarlyGame = struct { pub const priority: i32 = 150_000; };
///     pub const CustomLogic = struct {}; // Gets hash-based ID
/// };
/// scheduler.addSystem(Stage(MyStages.EarlyGame), my_system);
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

/// Manages system execution order and stages.
///
/// Systems can be added to stages, and stages can be run in order.
///
/// The scheduler can also register event types, which creates EventStore resources.
/// Includes integrated state management for application states.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    systems: std.AutoHashMap(i32, std.ArrayList(systems.UntypedSystemHandle)),
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
        var _systems = std.AutoHashMap(i32, std.ArrayList(systems.UntypedSystemHandle)).init(allocator);
        for (predefined_stages) |stage| {
            const new_list = std.ArrayList(systems.UntypedSystemHandle).initCapacity(allocator, 0) catch |err| {
                _systems.deinit();
                return err;
            };
            _systems.put(stage, new_list) catch @panic(try std.fmt.allocPrint(allocator, "Failed to init stage: {d}", .{stage}));
        }
        const self: Scheduler = .{
            .allocator = allocator,
            .systems = _systems,
            .states = std.AutoHashMap(u64, StateInfo).init(allocator),
            .active_state = null,
        };

        return self;
    }

    pub fn deinit(self: *Scheduler) void {
        var it = self.systems.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.systems.deinit();
        self.states.deinit();
    }

    pub fn addSystem(self: *Scheduler, ecs: *ecs_mod.Manager, stage: StageId, system: anytype, comptime param_registry: type) void {
        const gop = self.systems.getOrPut(stage.value) catch |err| @panic(@errorName(err));
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(systems.UntypedSystemHandle).initCapacity(self.allocator, 4) catch |err| @panic(@errorName(err));
        }
        const SystemType = @TypeOf(system);
        const untyped_system_handle = switch (comptime systems.getSystemTypeFromType(SystemType)) {
            .func => ecs.createSystemCached(system, param_registry).eraseType(),
            .handle => system.eraseType(),
            .untyped => system,
            else => std.debug.panic("Invalid system type: {s}. Expected a function or SystemHandle.", .{@typeName(SystemType)}),
        };
        gop.value_ptr.append(self.allocator, untyped_system_handle) catch |err| @panic(@errorName(err));
    }

    pub fn addStage(self: *Scheduler, stage: StageId) error{ InvalidStageBounds, StageExists, OutOfMemory }!void {
        const gop = try self.systems.getOrPut(stage.value);
        if (!gop.found_existing) {
            if (stage.value < Stage(Stages.Min).value or stage.value > Stage(Stages.Max).value) {
                return error.InvalidStageBounds;
            }
            gop.value_ptr.* = try std.ArrayList(systems.UntypedSystemHandle).initCapacity(self.allocator, 4);
        } else {
            return error.StageExists;
        }
    }

    pub fn removeStage(self: *Scheduler, stage: StageId) error{StageHasNoSystems}!void {
        if (self.systems.fetchRemove(stage.value)) |entry| {
            entry.value.deinit(self.allocator);
        } else {
            return error.StageHasNoSystems;
        }
    }

    pub fn runStage(self: *Scheduler, ecs: *ecs_mod.Manager, stage: StageId) anyerror!void {
        if (self.systems.get(stage.value)) |list| {
            for (list.items) |handle| {
                try ecs.runSystemUntyped(void, handle);
            }
        } else return error.StageHasNoSystems;
    }

    pub fn runStages(self: *Scheduler, ecs: *ecs_mod.Manager, start: StageId, end: StageId) anyerror!void {
        // Collect stages in the range and sort them
        var stage_values = std.ArrayList(i32).initCapacity(self.allocator, 0) catch |err| @panic(@errorName(err));
        defer stage_values.deinit(self.allocator);

        var it = self.systems.iterator();
        while (it.next()) |entry| {
            const k = entry.key_ptr.*;
            if (k >= start.value and k <= end.value) {
                stage_values.append(self.allocator, k) catch |err| @panic(@errorName(err));
            }
        }

        // Sort stage integer IDs (ascending)
        std.mem.sort(i32, stage_values.items, {}, std.sort.asc(i32));

        // Run stages in sorted order
        for (stage_values.items) |val| {
            try self.runStage(ecs, StageId.init(val));
        }
    }

    pub fn getStageInfo(self: *Scheduler, allocator: std.mem.Allocator) std.ArrayList(StageInfo) {
        var info_list = std.ArrayList(StageInfo).initCapacity(allocator, self.systems.count()) catch |err| @panic(@errorName(err));
        var it = self.systems.iterator();
        while (it.next()) |entry| {
            info_list.append(allocator, .{
                .stage = StageId.init(entry.key_ptr.*),
                .system_count = entry.value_ptr.items.len,
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
    ) error{ ResourceAlreadyExists, OutOfMemory }!void {
        // Create EventStore for this event type
        const event_store = try events.EventStore(T).init(self.allocator, 10);

        // Add EventStore as a resource
        _ = try ecs.addResource(events.EventStore(T), event_store);

        // Create cleanup system that discards handled and unhandled events (consumes them)
        const cleanup_system = struct {
            pub fn cleanup(store_res: params.Res(events.EventStore(T))) void {
                store_res.ptr.discardHandled();
                store_res.ptr.discardUnhandled();
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

    const custom_stage = StageId.init(999);
    try scheduler.addStage(custom_stage);
    try std.testing.expect(scheduler.systems.contains(custom_stage.value));
    try std.testing.expectError(error.StageExists, scheduler.addStage(custom_stage));
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
    const out_value = try ecs.addResource(bool, false);
    try scheduler.addStage(custom_stage);
    const test_system = struct {
        pub fn run(out: params.Res(bool)) void {
            std.debug.print("Test system executed\n", .{});
            out.ptr.* = true;
        }
    }.run;

    scheduler.addSystem(&ecs, custom_stage, test_system, registry.DefaultParamRegistry);

    // Run stages from First to PostUpdate, which includes the custom stage
    try scheduler.runStages(&ecs, Stage(Stages.First), Stage(Stages.PostUpdate));

    try std.testing.expect(out_value.* == true);
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
            pub const priority: StageId = .initDebug(50_000, EarlyGame); // Between Startup and First
        };
        pub const LateUpdate = struct {
            pub const priority: StageId = .initDebug(350_000, LateUpdate); // Between Update and PostUpdate
        };
        pub const PreCleanup = struct {
            pub const priority: StageId = .initDebug(750_000, PreCleanup); // Between PostDraw and Last
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
        pub const priority: StageId = .initDebug(150, @This());
    };
    try std.testing.expect(StageInRange(InRange, .init(100), .init(200)).value == 150);

    // Priority-based type outside the range should be mapped into it
    const OutRangePriority = struct {
        pub const priority: StageId = .initDebug(800, @This());
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
