const std = @import("std");
const ecs_mod = @import("ecs.zig");
const scheduler_mod = @import("scheduler.zig");
const Scheduler = scheduler_mod.Scheduler;

/// StateManager provides a convenient interface for systems to access state management
/// This is a wrapper around the Scheduler's integrated state management
pub fn StateManager(comptime StateEnum: type) type {
    // Verify StateEnum is actually an enum at compile time
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("StateManager requires an enum type, got: " ++ @typeName(StateEnum));
    }

    return struct {
        const Self = @This();
        pub const StateType = StateEnum;

        scheduler: *Scheduler,
        ecs: *ecs_mod.Manager,

        /// Check if currently in a specific state
        pub fn isInState(self: *const Self, state: StateEnum) bool {
            return self.scheduler.isInState(StateEnum, state);
        }

        /// Get the currently active state
        pub fn getActiveState(self: *const Self) ?StateEnum {
            return self.scheduler.getActiveState(StateEnum);
        }

        /// Transition to a new state (queues the transition)
        pub fn transitionTo(self: *Self, state: StateEnum) !void {
            try self.scheduler.transitionTo(self.ecs, StateEnum, state);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Scheduler register state type" {
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

    try scheduler.registerState(&ecs, GameState);

    // Verify state type is registered
    const type_hash = std.hash.Wyhash.hash(0, @typeName(GameState));
    try std.testing.expect(scheduler.states.contains(type_hash));
}

test "Scheduler duplicate state registration" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
    };

    try scheduler.registerState(&ecs, GameState);
    try std.testing.expectError(error.StateAlreadyRegistered, scheduler.registerState(&ecs, GameState));
}

test "Scheduler state transition" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
    };

    try scheduler.registerState(&ecs, GameState);

    // Transition to Menu state (immediate)
    try scheduler.transitionTo(&ecs, GameState, .Menu);
    try std.testing.expect(scheduler.isInState(GameState, .Menu));

    // Transition to Playing state
    try scheduler.transitionTo(&ecs, GameState, .Playing);
    try std.testing.expect(scheduler.isInState(GameState, .Playing));
    try std.testing.expect(!scheduler.isInState(GameState, .Menu));
}

test "Scheduler get active state name" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
    };

    try scheduler.registerState(&ecs, GameState);

    // No active state initially
    try std.testing.expect(scheduler.getActiveStateName() == null);

    // Set initial state (immediate)
    try scheduler.transitionTo(&ecs, GameState, .Menu);

    // Verify we can get the state name
    const state_name = scheduler.getActiveStateName();
    try std.testing.expect(state_name != null);
    try std.testing.expectEqualStrings("Menu", state_name.?);
}

test "Scheduler state transition processing" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
    };

    try scheduler.registerState(&ecs, GameState);

    // Transition is immediate
    try scheduler.transitionTo(&ecs, GameState, .Menu);
    try std.testing.expect(scheduler.isInState(GameState, .Menu));

    // Transition to another state
    try scheduler.transitionTo(&ecs, GameState, .Playing);
    try std.testing.expect(scheduler.isInState(GameState, .Playing));
}

test "Scheduler unregistered state transition" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    const GameState = enum {
        Menu,
        Playing,
    };

    // Should error when transitioning to unregistered state type
    try std.testing.expectError(error.StateNotRegistered, scheduler.transitionTo(&ecs, GameState, .Menu));
}

test "States parameter in system" {
    const allocator = std.testing.allocator;
    var ecs = try ecs_mod.Manager.init(allocator);
    defer ecs.deinit();

    var scheduler = try Scheduler.init(allocator);
    defer scheduler.deinit();

    // Define game state enum
    const GameState = enum {
        Menu,
        Playing,
        Paused,
    };

    // Register state type (automatically adds StateManager resource)
    try scheduler.registerState(&ecs, GameState);

    // Set initial state (immediate)
    try scheduler.transitionTo(&ecs, GameState, .Menu);

    // System that uses State and NextState parameters
    const params = @import("systems.params.zig");
    const test_system = struct {
        pub fn run(
            _: *ecs_mod.Manager,
            game_state: params.State(GameState),
            next_state: *params.NextState(GameState),
        ) anyerror!void {
            // Check current state using State parameter
            std.debug.assert(game_state.isActive(.Menu));
            std.debug.assert(!game_state.isActive(.Playing));

            // Get active state
            const active = game_state.get();
            std.debug.assert(active != null);
            std.debug.assert(active.? == .Menu);

            // Transition to playing state using NextState (immediate)
            try next_state.set(.Playing);
        }
    }.run;

    // Create and run the system
    const registry = @import("systems.registry.zig");
    const system = ecs.createSystem(test_system, registry.DefaultParamRegistry);
    try system.run(&ecs, system.ctx);

    // Verify transition happened immediately
    try std.testing.expect(scheduler.isInState(GameState, .Playing));
    try std.testing.expect(!scheduler.isInState(GameState, .Menu));
}

test "OnEnter and OnExit systems" {
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

    // Register state type
    try scheduler.registerState(&ecs, GameState);

    // Create unique resource types to track which systems ran
    const MenuEntered = struct { value: bool };
    const MenuExited = struct { value: bool };
    const PlayingEntered = struct { value: bool };
    const PlayingExited = struct { value: bool };

    const menu_entered = try ecs.addResource(MenuEntered, .{ .value = false });
    const menu_exited = try ecs.addResource(MenuExited, .{ .value = false });
    const playing_entered = try ecs.addResource(PlayingEntered, .{ .value = false });
    const playing_exited = try ecs.addResource(PlayingExited, .{ .value = false });

    // Create OnEnter system for Menu state
    const params = @import("systems.params.zig");
    const menu_enter_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(MenuEntered)) void {
            flag.ptr.value = true;
        }
    }.run;

    // Create OnExit system for Menu state
    const menu_exit_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(MenuExited)) void {
            flag.ptr.value = true;
        }
    }.run;

    // Create OnEnter system for Playing state
    const playing_enter_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(PlayingEntered)) void {
            flag.ptr.value = true;
        }
    }.run;

    // Create OnExit system for Playing state
    const playing_exit_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(PlayingExited)) void {
            flag.ptr.value = true;
        }
    }.run;

    // Register systems for state transitions
    const registry = @import("systems.registry.zig");
    const OnEnter = @import("scheduler.zig").OnEnter;
    const OnExit = @import("scheduler.zig").OnExit;

    const menu_enter_handle = ecs.createSystemCached(menu_enter_system, registry.DefaultParamRegistry);
    const menu_exit_handle = ecs.createSystemCached(menu_exit_system, registry.DefaultParamRegistry);
    const playing_enter_handle = ecs.createSystemCached(playing_enter_system, registry.DefaultParamRegistry);
    const playing_exit_handle = ecs.createSystemCached(playing_exit_system, registry.DefaultParamRegistry);

    scheduler.addSystem(&ecs, OnEnter(GameState.Menu), menu_enter_handle, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, OnExit(GameState.Menu), menu_exit_handle, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, OnEnter(GameState.Playing), playing_enter_handle, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, OnExit(GameState.Playing), playing_exit_handle, registry.DefaultParamRegistry);

    // Transition to Menu state - should trigger OnEnter(Menu)
    try scheduler.transitionTo(&ecs, GameState, .Menu);
    try std.testing.expect(menu_entered.value);
    try std.testing.expect(!menu_exited.value);
    try std.testing.expect(!playing_entered.value);
    try std.testing.expect(!playing_exited.value);

    // Reset flags
    menu_entered.value = false;
    menu_exited.value = false;
    playing_entered.value = false;
    playing_exited.value = false;

    // Transition to Playing state - should trigger OnExit(Menu) and OnEnter(Playing)
    try scheduler.transitionTo(&ecs, GameState, .Playing);
    try std.testing.expect(!menu_entered.value);
    try std.testing.expect(menu_exited.value);
    try std.testing.expect(playing_entered.value);
    try std.testing.expect(!playing_exited.value);

    // Reset flags
    menu_entered.value = false;
    menu_exited.value = false;
    playing_entered.value = false;
    playing_exited.value = false;

    // Transition to Menu state again - should trigger OnExit(Playing) and OnEnter(Menu)
    try scheduler.transitionTo(&ecs, GameState, .Menu);
    try std.testing.expect(menu_entered.value);
    try std.testing.expect(!menu_exited.value);
    try std.testing.expect(!playing_entered.value);
    try std.testing.expect(playing_exited.value);
}

test "InState systems" {
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

    // Register state type
    try scheduler.registerState(&ecs, GameState);

    // Create unique resource types to track which systems ran
    const MenuSystemRan = struct { value: bool };
    const PlayingSystemRan = struct { value: bool };
    const PausedSystemRan = struct { value: bool };

    const menu_ran = try ecs.addResource(MenuSystemRan, .{ .value = false });
    const playing_ran = try ecs.addResource(PlayingSystemRan, .{ .value = false });
    const paused_ran = try ecs.addResource(PausedSystemRan, .{ .value = false });

    // Create InState systems for each state
    const params = @import("systems.params.zig");
    const menu_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(MenuSystemRan)) void {
            flag.ptr.value = true;
        }
    }.run;

    const playing_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(PlayingSystemRan)) void {
            flag.ptr.value = true;
        }
    }.run;

    const paused_system = struct {
        pub fn run(_: *ecs_mod.Manager, flag: params.Res(PausedSystemRan)) void {
            flag.ptr.value = true;
        }
    }.run;

    // Register systems for specific states
    const registry = @import("systems.registry.zig");
    const InState = @import("scheduler.zig").InState;

    const menu_handle = ecs.createSystemCached(menu_system, registry.DefaultParamRegistry);
    const playing_handle = ecs.createSystemCached(playing_system, registry.DefaultParamRegistry);
    const paused_handle = ecs.createSystemCached(paused_system, registry.DefaultParamRegistry);

    scheduler.addSystem(&ecs, InState(GameState.Menu), menu_handle, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, InState(GameState.Playing), playing_handle, registry.DefaultParamRegistry);
    scheduler.addSystem(&ecs, InState(GameState.Paused), paused_handle, registry.DefaultParamRegistry);

    // Transition to Menu state
    try scheduler.transitionTo(&ecs, GameState, .Menu);

    // Run InState systems for Menu
    try scheduler.runInStateSystems(&ecs, GameState, .Menu);
    try std.testing.expect(menu_ran.value);
    try std.testing.expect(!playing_ran.value);
    try std.testing.expect(!paused_ran.value);

    // Reset flags
    menu_ran.value = false;
    playing_ran.value = false;
    paused_ran.value = false;

    // Transition to Playing state
    try scheduler.transitionTo(&ecs, GameState, .Playing);

    // Run InState systems for Playing
    try scheduler.runInStateSystems(&ecs, GameState, .Playing);
    try std.testing.expect(!menu_ran.value);
    try std.testing.expect(playing_ran.value);
    try std.testing.expect(!paused_ran.value);

    // Reset flags
    menu_ran.value = false;
    playing_ran.value = false;
    paused_ran.value = false;

    // Test runActiveStateSystems convenience method
    try scheduler.runActiveStateSystems(&ecs, GameState);
    try std.testing.expect(!menu_ran.value);
    try std.testing.expect(playing_ran.value);
    try std.testing.expect(!paused_ran.value);

    // Reset flags
    menu_ran.value = false;
    playing_ran.value = false;
    paused_ran.value = false;

    // Transition to Paused state
    try scheduler.transitionTo(&ecs, GameState, .Paused);

    // Run InState systems using convenience method
    try scheduler.runActiveStateSystems(&ecs, GameState);
    try std.testing.expect(!menu_ran.value);
    try std.testing.expect(!playing_ran.value);
    try std.testing.expect(paused_ran.value);
}
