const std = @import("std");
const ecs_mod = @import("ecs.zig");
const events = @import("events.zig");
const registry = @import("systems.registry.zig");
const systems = @import("systems.zig");
const state_mod = @import("state.zig");

/// Stage ID type (internal representation)
pub const StageId = u32;

/// Convert a stage type to its unique stage ID.
/// Each unique type gets a consistent i32 value based on its type name hash.
/// Predefined stages map to specific ranges for ordering, custom stages use hash-based IDs.
pub fn Stage(comptime T: type) StageId {
    // Check if T has a priority field for explicit ordering
    if (@hasDecl(T, "priority")) {
        return T.priority;
    }

    // Generate hash-based ID in user custom range (2,000,000 to ~2.1B)
    // Reserve space before Last/Exit/Max stages
    const hash = std.hash.Wyhash.hash(0, @typeName(T));
    const max_custom_range = std.math.maxInt(i32) - 2_000_000 - 100_000; // Leave buffer before Last
    return @intCast(2_000_000 + (@as(u32, @truncate(hash)) % max_custom_range));
}

const STAGE_GAP: StageId = 100_000;

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
    pub const Min = struct {
        pub const priority: StageId = 0;
    };
    pub const PreStartup = struct {
        pub const priority: StageId = Min.priority;
    };
    pub const Startup = struct {
        pub const priority: StageId = STAGE_GAP / 100; // 1,000
    };
    pub const First = struct {
        pub const priority: StageId = STAGE_GAP; // 100,000
    };
    pub const PreUpdate = struct {
        pub const priority: StageId = 2 * STAGE_GAP; // 200,000
    };
    pub const Update = struct {
        pub const priority: StageId = 3 * STAGE_GAP; // 300,000
    };
    pub const PostUpdate = struct {
        pub const priority: StageId = 4 * STAGE_GAP; // 400,000
    };
    pub const PreDraw = struct {
        pub const priority: StageId = 5 * STAGE_GAP; // 500,000
    };
    pub const Draw = struct {
        pub const priority: StageId = 6 * STAGE_GAP; // 600,000
    };
    pub const PostDraw = struct {
        pub const priority: StageId = 7 * STAGE_GAP; // 700,000
    };

    // State management stages (1,000,000 - 1,999,999)
    pub const StateTransition = struct {
        pub const priority: StageId = 1_000_000;
    };
    pub const StateOnExit = struct {
        pub const priority: StageId = StateTransition.priority + STAGE_GAP;
    };
    pub const StateOnEnter = struct {
        pub const priority: StageId = StateOnExit.priority + STAGE_GAP;
    };
    pub const StateUpdate = struct {
        pub const priority: StageId = StateOnEnter.priority + STAGE_GAP;
    };

    pub const Last = struct {
        pub const priority: StageId = std.math.maxInt(i32) - 1;
    };
    pub const Exit = struct {
        pub const priority: StageId = std.math.maxInt(i32);
    };
    pub const Max = struct {
        pub const priority: StageId = Exit.priority;
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
    systems: std.AutoHashMap(StageId, std.ArrayList(ecs_mod.SystemHandle)),
    ecs: *ecs_mod.Manager,
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
    const predefined_stages = [_]StageId{
        Stage(Stages.Min),
        Stage(Stages.PreStartup),
        Stage(Stages.Startup),
        Stage(Stages.First),
        Stage(Stages.PreUpdate),
        Stage(Stages.Update),
        Stage(Stages.PostUpdate),
        Stage(Stages.PreDraw),
        Stage(Stages.Draw),
        Stage(Stages.PostDraw),
        Stage(Stages.StateTransition),
        Stage(Stages.StateOnExit),
        Stage(Stages.StateOnEnter),
        Stage(Stages.StateUpdate),
        Stage(Stages.Last),
        Stage(Stages.Max), // Exit and Max are the same value now
    };

    pub fn init(allocator: std.mem.Allocator, ecs: *ecs_mod.Manager) !Scheduler {
        var _systems = std.AutoHashMap(StageId, std.ArrayList(ecs_mod.SystemHandle)).init(allocator);
        for (predefined_stages) |stage| {
            const new_list = std.ArrayList(ecs_mod.SystemHandle).initCapacity(allocator, 0) catch |err| {
                _systems.deinit();
                return err;
            };
            _systems.put(stage, new_list) catch @panic(try std.fmt.allocPrint(allocator, "Failed to init stage: {d}", .{stage}));
        }
        const self: Scheduler = .{
            .allocator = allocator,
            .systems = _systems,
            .ecs = ecs,
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

    pub fn addSystem(self: *Scheduler, stage: StageId, system_handle: ecs_mod.SystemHandle) void {
        const gop = self.systems.getOrPut(stage) catch |err| @panic(@errorName(err));
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(ecs_mod.SystemHandle).initCapacity(self.allocator, 4) catch |err| @panic(@errorName(err));
        }
        gop.value_ptr.append(self.allocator, system_handle) catch |err| @panic(@errorName(err));
    }

    pub fn addStage(self: *Scheduler, stage: StageId) error{ InvalidStageBounds, StageExists, OutOfMemory }!void {
        const gop = try self.systems.getOrPut(stage);
        if (!gop.found_existing) {
            if (stage < Stage(Stages.Min) or stage > Stage(Stages.Max)) {
                return error.InvalidStageBounds;
            }
            gop.value_ptr.* = try std.ArrayList(ecs_mod.SystemHandle).initCapacity(self.allocator, 4);
        } else {
            return error.StageExists;
        }
    }

    pub fn runStage(self: *Scheduler, ecs: *ecs_mod.Manager, stage: StageId) anyerror!void {
        if (self.systems.get(stage)) |list| {
            for (list.items) |handle| {
                try ecs.runSystem(void, handle);
            }
        } else {
            return error.StageNotFound;
        }
    }

    pub fn runStages(self: *Scheduler, ecs: *ecs_mod.Manager, start: StageId, end: StageId) anyerror!void {
        // Collect stages in the range and sort them
        var stages_in_range = std.ArrayList(StageId).initCapacity(self.allocator, 0) catch |err| @panic(@errorName(err));
        defer stages_in_range.deinit(self.allocator);

        var it = self.systems.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* >= start and entry.key_ptr.* <= end) {
                stages_in_range.append(self.allocator, entry.key_ptr.*) catch |err| @panic(@errorName(err));
            }
        }

        // Sort stages by their ID (ascending order)
        std.mem.sort(StageId, stages_in_range.items, {}, std.sort.asc(StageId));

        // Run stages in sorted order
        for (stages_in_range.items) |stage| {
            try self.runStage(ecs, stage);
        }
    }

    pub fn getStageInfo(self: *Scheduler, allocator: std.mem.Allocator) std.ArrayList(StageInfo) {
        var info_list = std.ArrayList(StageInfo).initCapacity(allocator, self.systems.count()) catch |err| @panic(@errorName(err));
        var it = self.systems.iterator();
        while (it.next()) |entry| {
            info_list.append(allocator, .{
                .stage = entry.key_ptr.*,
                .system_count = entry.value_ptr.items.len,
            }) catch |err| @panic(@errorName(err));
        }
        return info_list;
    }

    /// Register an event with the scheduler
    /// This creates an EventStore resource and adds a cleanup system at the Last stage
    pub fn registerEvent(self: *Scheduler, ecs: *ecs_mod.Manager, comptime T: type) ecs_mod.errors!void {
        // Create EventStore for this event type
        const event_store = events.EventStore(T).init(self.allocator, 10);

        // Add EventStore as a resource
        _ = ecs.addResource(events.EventStore(T), event_store) catch |err| {
            return err;
        };

        // Create cleanup system that discards handled events (consumes them)
        const cleanup_system = struct {
            pub fn cleanup(_: *ecs_mod.Manager, store_res: systems.Res(events.EventStore(T))) void {
                store_res.ptr.discardHandled();
            }
        }.cleanup;

        // Create and cache the cleanup system
        const system_handle = ecs.createSystemCached(cleanup_system, registry.DefaultParamRegistry);

        // Add cleanup system to Last stage
        self.addSystem(Stage(Stages.Last), system_handle);
    }

    // ============================================================================
    // State Management Methods
    // ============================================================================

    /// Register a new state enum type with the scheduler.
    /// StateEnum must be an enum type.
    /// Automatically adds the StateManager resource to the ECS
    pub fn registerState(
        self: *Scheduler,
        comptime StateEnum: type,
    ) !void {
        const type_info = @typeInfo(StateEnum);
        if (type_info != .@"enum") {
            @compileError("registerStateType requires an enum type, got: " ++ @typeName(StateEnum));
        }

        const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));

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
        const state_mgr = self.getStateManager(StateEnum);
        _ = try self.ecs.addResource(state_mod.StateManager(StateEnum), state_mgr);
    }

    /// Check if a specific state value is currently active
    pub fn isInState(self: *Scheduler, comptime StateEnum: type, state: StateEnum) bool {
        const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));
        const value_hash = std.hash.Wyhash.hash(0, @tagName(state));

        if (self.active_state) |active| {
            return active.enum_type_hash == type_hash and active.value_hash == value_hash;
        }
        return false;
    }

    /// Get the currently active state of a specific enum type
    pub fn getActiveState(self: *Scheduler, comptime StateEnum: type) ?StateEnum {
        const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));

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
        comptime StateEnum: type,
        state: StateEnum,
    ) !void {
        const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));

        // Verify the state enum type is registered
        _ = self.states.get(type_hash) orelse return error.StateNotRegistered;

        const value_hash = std.hash.Wyhash.hash(0, @tagName(state));
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
                const old_combined_hash = std.hash.Wyhash.hash(old_state.enum_type_hash, std.mem.asBytes(&old_state.value_hash));
                const old_stage_offset: u32 = @intCast(@as(u32, @truncate(old_combined_hash)) % 100_000);
                const exit_stage = Stage(Stages.StateOnExit) + old_stage_offset;
                // Run the OnExit stage if it exists (don't error if it doesn't)
                self.runStage(self.ecs, exit_stage) catch {};
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
        const new_combined_hash = std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&value_hash));
        const new_stage_offset: u32 = @intCast(@as(u32, @truncate(new_combined_hash)) % 100_000);
        const enter_stage = Stage(Stages.StateOnEnter) + new_stage_offset;
        // Run the OnEnter stage if it exists (don't error if it doesn't)
        self.runStage(self.ecs, enter_stage) catch {};
    }

    /// Run InState systems for a specific state value
    /// This runs systems that were registered with InState(state_value)
    pub fn runInStateSystems(
        self: *Scheduler,
        comptime StateEnum: type,
        state: StateEnum,
    ) !void {
        const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));
        const value_hash = std.hash.Wyhash.hash(0, @tagName(state));
        const combined_hash = std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&value_hash));
        const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
        const state_stage = Stage(Stages.StateUpdate) + stage_offset;

        // Run the InState stage if it exists (don't error if it doesn't)
        self.runStage(self.ecs, state_stage) catch {};
    }

    /// Run InState systems for the currently active state
    /// This is a convenience method that automatically runs the correct InState systems
    pub fn runActiveStateSystems(self: *Scheduler, comptime StateEnum: type) !void {
        if (self.getActiveState(StateEnum)) |active_state| {
            try self.runInStateSystems(StateEnum, active_state);
        }
    }

    /// Get a StateManager wrapper for use in systems
    /// This provides a convenient interface for systems to access state management via Res(StateManager(StateEnum))
    pub fn getStateManager(self: *Scheduler, comptime StateEnum: type) state_mod.StateManager(StateEnum) {
        return state_mod.StateManager(StateEnum){
            .scheduler = self,
        };
    }
};

/// Returns a temporary stage ID for systems that should run when entering a specific state
/// Usage: scheduler.addSystem(OnEnter(GameState.Playing), my_system_handle)
pub fn OnEnter(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("OnEnter requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateOnEnter base stage + hash of type name and value name
    const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));
    const value_hash = std.hash.Wyhash.hash(0, @tagName(state));
    const combined_hash = std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&value_hash));

    // Map hash to a range within StateOnEnter stage area (1,200,000 - 1,299,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateOnEnter) + stage_offset;
}

/// Returns a temporary stage ID for systems that should run when exiting a specific state
/// Usage: scheduler.addSystem(OnExit(GameState.Playing), my_cleanup_system_handle)
pub fn OnExit(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("OnExit requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateOnExit base stage + hash of type name and value name
    const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));
    const value_hash = std.hash.Wyhash.hash(0, @tagName(state));
    const combined_hash = std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&value_hash));

    // Map hash to a range within StateOnExit stage area (1,100,000 - 1,199,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateOnExit) + stage_offset;
}

/// Returns a temporary stage ID for systems that should run only while in a specific state
/// Usage: scheduler.addSystem(InState(GameState.Playing), gameplay_system_handle)
pub fn InState(comptime state: anytype) StageId {
    const StateEnum = @TypeOf(state);
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("InState requires an enum value, got: " ++ @typeName(StateEnum));
    }

    // Generate a unique stage ID based on the enum type and value
    // Use StateUpdate base stage + hash of type name and value name
    const type_hash = std.hash.Wyhash.hash(0, @typeName(StateEnum));
    const value_hash = std.hash.Wyhash.hash(0, @tagName(state));
    const combined_hash = std.hash.Wyhash.hash(type_hash, std.mem.asBytes(&value_hash));

    // Map hash to a range within StateUpdate stage area (1,300,000 - 1,399,999)
    const stage_offset: u32 = @intCast(@as(u32, @truncate(combined_hash)) % 100_000);
    return Stage(Stages.StateUpdate) + stage_offset;
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

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    // Register the event type
    scheduler.registerEvent(&ecs, TestEvent) catch |err| {
        return err;
    };

    std.testing.expect(ecs.hasResource(events.EventStore(TestEvent))) catch {
        std.debug.print("Failed to find EventStore resource for TestEvent\n", .{});
        return error.FailedToFindEventStore;
    };

    // Verify a cleanup system was added to the Last stage
    const stage_info = scheduler.getStageInfo(std.testing.allocator);
    defer (@constCast(&stage_info)).deinit(std.testing.allocator);

    // Find the Last stage
    var found_last_stage = false;
    for (stage_info.items) |info| {
        if (info.stage == Stage(Stages.Last)) {
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

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    const custom_stage = 999;
    try scheduler.addStage(custom_stage);
    try std.testing.expect(scheduler.systems.contains(custom_stage));
    try std.testing.expectError(error.StageExists, scheduler.addStage(custom_stage));
}

test "Scheduler getStageInfo" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    var info = scheduler.getStageInfo(allocator);
    defer info.deinit(allocator);

    // Note: Exit and Max have the same value, so we expect one less unique stage
    // predefined_stages has 16 entries but only 15 unique stage IDs
    const expected_unique_stages = 15;
    try std.testing.expect(info.items.len >= expected_unique_stages);

    // Check that all unique predefined stages are present
    // Build a set of unique stage IDs from predefined_stages
    var unique_stages = std.AutoHashMap(StageId, void).init(allocator);
    defer unique_stages.deinit();
    for (Scheduler.predefined_stages) |stage| {
        try unique_stages.put(stage, {});
    }

    // Verify each unique stage is in the info list
    var it = unique_stages.keyIterator();
    while (it.next()) |stage_ptr| {
        var found = false;
        for (info.items) |i| {
            if (i.stage == stage_ptr.*) {
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

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    try std.testing.expectError(error.StageNotFound, scheduler.runStage(&ecs, 9999));
}

test "Scheduler assign outside scope" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    // Add a custom stage and a system to it
    const custom_stage = 150_000; // Between First (100,000) and PreUpdate (200,000)
    const out_value = try ecs.addResource(bool, false);
    try scheduler.addStage(custom_stage);
    const test_system = struct {
        pub fn run(_: *ecs_mod.Manager, out: systems.Res(bool)) void {
            std.debug.print("Test system executed\n", .{});
            out.ptr.* = true;
        }
    }.run;
    const system_handle = ecs.createSystemCached(test_system, registry.DefaultParamRegistry);
    scheduler.addSystem(custom_stage, system_handle);

    // Run stages from First to PostUpdate, which includes the custom stage
    try scheduler.runStages(&ecs, Stage(Stages.First), Stage(Stages.PostUpdate));

    try std.testing.expect(out_value.* == true);
}

test "Custom stage types with explicit priorities" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    // Define custom stages with explicit priorities
    const CustomStages = struct {
        pub const EarlyGame = struct {
            pub const priority: StageId = 50_000; // Between Startup and First
        };
        pub const LateUpdate = struct {
            pub const priority: StageId = 350_000; // Between Update and PostUpdate
        };
        pub const PreCleanup = struct {
            pub const priority: StageId = 750_000; // Between PostDraw and Last
        };
    };

    // Add systems to custom stages
    const test_sys = struct {
        pub fn run(_: *ecs_mod.Manager) void {}
    }.run;

    const handle = ecs.createSystemCached(test_sys, registry.DefaultParamRegistry);

    scheduler.addSystem(Stage(CustomStages.EarlyGame), handle);
    scheduler.addSystem(Stage(CustomStages.LateUpdate), handle);
    scheduler.addSystem(Stage(CustomStages.PreCleanup), handle);

    // Verify stages have correct priority values
    try std.testing.expect(Stage(CustomStages.EarlyGame) == 50_000);
    try std.testing.expect(Stage(CustomStages.LateUpdate) == 350_000);
    try std.testing.expect(Stage(CustomStages.PreCleanup) == 750_000);

    // Verify stages were added to scheduler
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.EarlyGame)));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.LateUpdate)));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.PreCleanup)));
}

test "Custom stage types with hash-based IDs" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    // Define custom stages without priorities (will get hash-based IDs)
    const CustomStages = struct {
        pub const Physics = struct {};
        pub const Audio = struct {};
        pub const Networking = struct {};
    };

    // Add systems to custom stages
    const test_sys = struct {
        pub fn run(_: *ecs_mod.Manager) void {}
    }.run;

    const handle = ecs.createSystemCached(test_sys, registry.DefaultParamRegistry);

    scheduler.addSystem(Stage(CustomStages.Physics), handle);
    scheduler.addSystem(Stage(CustomStages.Audio), handle);
    scheduler.addSystem(Stage(CustomStages.Networking), handle);

    // Verify hash-based IDs are in the correct range (2M+)
    try std.testing.expect(Stage(CustomStages.Physics) >= 2_000_000);
    try std.testing.expect(Stage(CustomStages.Audio) >= 2_000_000);
    try std.testing.expect(Stage(CustomStages.Networking) >= 2_000_000);

    // Verify different types get different IDs
    try std.testing.expect(Stage(CustomStages.Physics) != Stage(CustomStages.Audio));
    try std.testing.expect(Stage(CustomStages.Audio) != Stage(CustomStages.Networking));
    try std.testing.expect(Stage(CustomStages.Physics) != Stage(CustomStages.Networking));

    // Verify stages were added to scheduler
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Physics)));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Audio)));
    try std.testing.expect(scheduler.systems.contains(Stage(CustomStages.Networking)));
}

test "State management without registration throws errors" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator, &ecs);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
        Paused,
    };

    // Test 1: transitionTo without registration should return error.StateNotRegistered
    const transition_result = scheduler.transitionTo(GameState, .Menu);
    try std.testing.expectError(error.StateNotRegistered, transition_result);

    // Test 2: Verify isInState returns false when state not registered
    const is_in_state = scheduler.isInState(GameState, .Menu);
    try std.testing.expect(is_in_state == false);

    // Test 3: Verify getActiveState returns null when state not registered
    const active_state = scheduler.getActiveState(GameState);
    try std.testing.expect(active_state == null);

    // Note: Testing State(StateEnum) parameter panic would require a separate test
    // that expects a panic, which is not easily done in Zig's test framework.
    // The panic occurs in systems.params.zig StateSystemParam.apply() when
    // a system with State parameter tries to access an unregistered state.
}
