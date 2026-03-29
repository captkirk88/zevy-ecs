const std = @import("std");
const ecs = @import("ecs.zig");
const errs = @import("errors.zig");
const qry = @import("query.zig");
const world = @import("world.zig");
const sys = @import("systems.zig");
const params_mod = @import("systems.params.zig");
pub const commands = @import("commands.zig");
const registry = @import("systems.registry.zig");
const scheduler = @import("scheduler.zig");
const sparse = @import("sparse_set.zig");

/// Error enum
pub const errors = errs.ECSError;
pub const Manager = ecs.Manager;
pub const Entity = ecs.Entity;
pub const Ref = ecs.Ref;
pub const World = world.World;
pub const System = sys.System;
pub const SystemHandle = sys.SystemHandle;
pub const UntypedSystemHandle = sys.UntypedSystemHandle;
pub const ToSystem = sys.ToSystem;
pub const ToSystemWithArgs = sys.ToSystemWithArgs;
pub const ToSystemReturnType = sys.ToSystemReturnType;
pub const pipe = sys.pipe;
pub const runIf = sys.runIf;
pub const chain = scheduler.chain;
pub const With = qry.With;
pub const Without = qry.Without;
pub const Res = params_mod.Res;
pub const ResMut = params_mod.ResMut;

// System parameter types
/// Default system parameter registry including Query, Res, Local, EventReader, and EventWriter
pub const DefaultParamRegistry = registry.DefaultParamRegistry;
/// Merge two or more SystemParamRegistry, deduplicating types at comptime
pub const MergedSystemParamRegistry = registry.MergedSystemParamRegistry;

/// Common system parameter types
pub const params = struct {
    /// Query parameter type for accessing entities with specific components
    pub const Query = qry.Query;
    /// Commands parameter type for issuing commands to modify the ECS world
    pub const Commands = commands.Commands;
    /// Resource parameter type for accessing resources
    pub const Res = params_mod.Res;
    /// Mutable resource parameter type for exclusive resource access
    pub const ResMut = params_mod.ResMut;
    /// Local parameter type for per-system-instance local state
    pub const Local = params_mod.Local;
    /// EventReader parameter type for reading events
    pub const EventReader = params_mod.EventReader;
    /// EventWriter parameter type for writing events
    pub const EventWriter = params_mod.EventWriter;
    /// State parameter type for checking if a specific state enum value is active
    pub const State = params_mod.State;
    /// NextState parameter type for immediate state transitions
    pub const NextState = params_mod.NextState;
    /// Relations parameter type for managing entity relationships
    pub const Relations = params_mod.Relations;
    /// OnAdded parameter type for reading components that were added this frame
    pub const OnAdded = params_mod.OnAdded;
    /// OnRemoved parameter type for reading components that were removed this frame
    pub const OnRemoved = params_mod.OnRemoved;
    /// Single parameter type — returns exactly one matching query result
    pub const Single = params_mod.Single;

    /// System parameter type aliases for usage in custom system params.
    pub const systems = struct {
        pub const CommandsSystemParam = params_mod.CommandsSystemParam;
        pub const QuerySystemParam = params_mod.QuerySystemParam;
        pub const ResourceSystemParam = params_mod.ResourceSystemParam;
        pub const ResourceMutSystemParam = params_mod.ResourceMutSystemParam;
        pub const LocalSystemParam = params_mod.LocalSystemParam;
        pub const EventReaderSystemParam = params_mod.EventReaderSystemParam;
        pub const EventWriterSystemParam = params_mod.EventWriterSystemParam;
        pub const StateSystemParam = params_mod.StateSystemParam;
        pub const NextStateSystemParam = params_mod.NextStateSystemParam;
        pub const RelationsSystemParam = params_mod.RelationsSystemParam;
        pub const OnAddedSystemParam = params_mod.OnAddedSystemParam;
        pub const OnRemovedSystemParam = params_mod.OnRemovedSystemParam;
        pub const SingleSystemParam = params_mod.SingleSystemParam;
    };
};

// Data structures
/// SparseSet - O(1) lookup/insert/remove with cache-friendly iteration
pub const SparseSet = sparse.SparseSet;

// Event types and functions
const events = @import("events.zig");
pub const EventStore = events.EventStore;

/// Scheduling types and functions
pub const schedule = struct {
    /// Scheduler is the system execution scheduler and state manager
    pub const Scheduler = scheduler.Scheduler;
    /// A stage entry: either a single system or an ordered chain of systems
    /// run as one concurrent task. Created implicitly by addSystem / chain().
    pub const StageEntry = scheduler.StageEntry;
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
};

const relations_mod = @import("relations.zig");

/// Relations module for managing entity relationships
pub const relations = struct {
    /// RelationManager provides entity relationship management with optional indexing
    pub const RelationManager = relations_mod.RelationManager;
    /// Relation component type for representing relationships between entities
    pub const Relation = relations_mod.Relation;
    /// Relation configuration type for defining relation behavior for `kinds`
    pub const RelationConfig = relations_mod.RelationConfig;

    /// Predefined relation kinds
    pub const kinds = struct {
        /// Indexed exclusive parent-child relationship (each child has one parent, parents can have multiple children)
        pub const Child = relations_mod.Child;
        /// Non-indexed attachment relationship (source entity is attached to target entity, no reverse lookup index)
        pub const AttachedTo = relations_mod.AttachedTo;
        /// Indexed non-exclusive ownership relationship (one entity can own multiple others, entities can have multiple owners)
        pub const Owns = relations_mod.Owns;
    };
};

pub const serialize = @import("serialize.zig");
pub const reflect = @import("reflect.zig");

/// Panic handler that logs the panic message and exits gracefully
const panic = std.debug.FullPanic(gracefulPanic);

fn gracefulPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    const log = std.log.scoped(.zevy_ecs);
    log.err("PANIC: {s}", .{msg});
    std.process.exit(1);
}

// Tests
test {
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
    std.testing.refAllDecls(schedule.state);
    std.testing.refAllDecls(events);
}
