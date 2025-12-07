const std = @import("std");
const ecs = @import("ecs.zig");
const errs = @import("errors.zig");
const qry = @import("query.zig");
const world = @import("world.zig");
const sys = @import("systems.zig");
const params = @import("systems.params.zig");
pub const commands = @import("commands.zig");
const registry = @import("systems.registry.zig");
const scheduler = @import("scheduler.zig");
const sparse = @import("sparse_set.zig");

/// Error enum
pub const errors = errs.ECSError;
/// ECS Manager type
pub const Manager = ecs.Manager;
/// Entity type
pub const Entity = ecs.Entity;
/// World type
pub const World = world.World;
/// System type
pub const System = sys.System;
/// Identifier for a cached system (generic, preserves return type)
pub const SystemHandle = sys.SystemHandle;
/// Type-erased system handle for storage
pub const UntypedSystemHandle = sys.UntypedSystemHandle;
/// Function to create a system from a function
pub const ToSystem = sys.ToSystem;
/// Function to create a system from a function with arguments
pub const ToSystemWithArgs = sys.ToSystemWithArgs;
/// Function to infer the return type of a system function
pub const ToSystemReturnType = sys.ToSystemReturnType;
/// Function to create a pipe system from two systems
pub const pipe = sys.pipe;
/// Function to run a system only if a condition is met
pub const runIf = sys.runIf;

// System parameter types
/// Default system parameter registry including Query, Res, Local, EventReader, and EventWriter
pub const DefaultParamRegistry = registry.DefaultParamRegistry;
/// Merge two or more SystemParamRegistry, deduplicating types at comptime
pub const MergedSystemParamRegistry = registry.MergedSystemParamRegistry;
/// Query parameter type for accessing entities with specific components
pub const Query = qry.Query;
/// Commands parameter type for issuing commands to modify the ECS world
pub const Commands = commands.Commands;
/// Resource parameter type for accessing resources
pub const Res = params.Res;
/// Local parameter type for per-system-instance local state
pub const Local = params.Local;
/// EventReader parameter type for reading events
pub const EventReader = params.EventReader;
/// EventWriter parameter type for writing events
pub const EventWriter = params.EventWriter;
/// State parameter type for checking if a specific state enum value is active
pub const State = params.State;
/// NextState parameter type for immediate state transitions
pub const NextState = params.NextState;
/// Relations parameter type for managing entity relationships
pub const Relations = params.Relations;
/// OnAdded parameter type for reading components that were added this frame
pub const OnAdded = params.OnAdded;
/// OnRemoved parameter type for reading components that were removed this frame
pub const OnRemoved = params.OnRemoved;
/// Single parameter type — returns exactly one matching query result
pub const Single = params.Single;

/// System parameter type aliases for usage in custom system params.
pub const system_params = struct {
    pub const CommandsSystemParam = params.CommandsSystemParam;
    pub const QuerySystemParam = params.QuerySystemParam;
    pub const ResourceSystemParam = params.ResourceSystemParam;
    pub const LocalSystemParam = params.LocalSystemParam;
    pub const EventReaderSystemParam = params.EventReaderSystemParam;
    pub const EventWriterSystemParam = params.EventWriterSystemParam;
    pub const StateSystemParam = params.StateSystemParam;
    pub const NextStateSystemParam = params.NextStateSystemParam;
    pub const RelationsSystemParam = params.RelationsSystemParam;
    pub const OnAddedSystemParam = params.OnAddedSystemParam;
    pub const OnRemovedSystemParam = params.OnRemovedSystemParam;
    pub const SingleSystemParam = params.SingleSystemParam;
};

// Data structures
/// SparseSet - O(1) lookup/insert/remove with cache-friendly iteration
pub const SparseSet = sparse.SparseSet;

// Event types and functions
const events = @import("events.zig");
pub const EventStore = events.EventStore;

/// Scheduler is the system execution scheduler and state manager
pub const Scheduler = scheduler.Scheduler;
/// StageId type for identifying execution stages
pub const StageId = scheduler.StageId;
pub const Stage = scheduler.Stage;
pub const StageInRange = scheduler.StageInRange;
pub const Stages = scheduler.Stages;
/// Returns a stage ID for systems that should run when entering a specific state
pub const OnEnter = scheduler.OnEnter;
/// Returns a stage ID for systems that should run when exiting a specific state
pub const OnExit = scheduler.OnExit;
/// Returns a stage ID for systems that should run only while in a specific state
pub const InState = scheduler.InState;

// State management types and functions
const state = @import("state.zig");
/// StateManager provides state management functionality for a specific enum type
pub const StateManager = state.StateManager;

// Relations
pub const relations = @import("relations.zig");
/// RelationManager provides entity relationship management with optional indexing
pub const RelationManager = relations.RelationManager;
/// Relation component type for representing relationships between entities
pub const Relation = relations.Relation;

pub const serialize = @import("serialize.zig");
pub const reflect = @import("reflect.zig");

/// Panic handler that logs the panic message and exits gracefully
pub const panic = std.debug.FullPanic(gracefulPanic);

fn gracefulPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    const log = std.log.scoped(.zevy_ecs);
    log.err("PANIC: {s}", .{msg});
    std.process.exit(1);
}

// Tests
test {
    const builtin = @import("builtin");
    if (builtin.mode != .Debug) {
        const benchmarks = @import("benchmark_tests.zig");
        std.testing.refAllDecls(benchmarks);
    }
    std.testing.refAllDecls(ecs);
    std.testing.refAllDecls(@import("ecs_tests.zig"));
    std.testing.refAllDecls(@import("query_tests.zig"));
    std.testing.refAllDecls(@import("archetype_tests.zig"));
    std.testing.refAllDecls(@import("archetype_storage_tests.zig"));
    std.testing.refAllDecls(@import("systems_tests.zig"));
    std.testing.refAllDecls(@import("serialize_tests.zig"));
    std.testing.refAllDecls(@import("relations_tests.zig"));
    std.testing.refAllDecls(@import("world_tests.zig"));
    std.testing.refAllDecls(scheduler);
    std.testing.refAllDecls(state);
    std.testing.refAllDecls(events);
}
