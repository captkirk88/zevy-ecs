const std = @import("std");
const ecs = @import("ecs.zig");
const errs = @import("errors.zig");
const qry = @import("query.zig");
const world = @import("world.zig");
const sys = @import("systems.zig");

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
pub const Query = qry.Query;
pub const Res = sys.Res;
pub const Local = sys.Local;
pub const EventReader = sys.EventReader;
pub const EventWriter = sys.EventWriter;

const events = @import("events.zig");
pub const EventStore = events.EventStore;

pub const reflect = @import("reflect.zig");

// Tests
test {
    const benchmarks = @import("benchmark_tests.zig");
    std.testing.refAllDeclsRecursive(ecs);
    std.testing.refAllDeclsRecursive(benchmarks);
}
