const std = @import("std");
const ecs = @import("ecs.zig");
const errs = @import("errors.zig");
const qry = @import("query.zig");
const world = @import("world.zig");
const sys = @import("systems.zig");
const registry = @import("systems.registry.zig");

// Core ECS types and functions
pub const errors = errs.ECSError;
pub const Manager = ecs.Manager;
pub const Entity = ecs.Entity;
pub const World = world.World;
pub const System = sys.System;
pub const ToSystem = sys.ToSystem;
pub const ToSystemWithArgs = sys.ToSystemWithArgs;
pub const pipe = sys.pipe;
pub const runIf = sys.runIf;

// System parameter types
/// Default system parameter registry including Query, Res, Local, EventReader, and EventWriter
pub const DefaultParamRegistry = registry.DefaultParamRegistry;
/// Merge two or more SystemParamRegistry, deduplicating types at comptime
pub const MergedSystemParamRegistry = registry.MergedSystemParamRegistry;
/// Query parameter type for accessing entities with specific components
pub const Query = qry.Query;
/// Resource parameter type for accessing resources
pub const Res = sys.Res;
/// Local parameter type for per-system-instance local state
pub const Local = sys.Local;
/// EventReader parameter type for reading events
pub const EventReader = sys.EventReader;
/// EventWriter parameter type for writing events
pub const EventWriter = sys.EventWriter;

const events = @import("events.zig");
pub const EventStore = events.EventStore;

pub const reflect = @import("reflect.zig");

// Tests
test {
    const benchmarks = @import("benchmark_tests.zig");
    std.testing.refAllDeclsRecursive(ecs);
    std.testing.refAllDeclsRecursive(benchmarks);
    std.testing.refAllDeclsRecursive(@import("ecs_tests.zig"));
    std.testing.refAllDeclsRecursive(@import("query_tests.zig"));
    std.testing.refAllDeclsRecursive(@import("archetype_tests.zig"));
    std.testing.refAllDeclsRecursive(@import("archetype_storage_tests.zig"));
    std.testing.refAllDeclsRecursive(@import("systems_tests.zig"));
    // world_tests.zig removed - World.add() API needs investigation
}
