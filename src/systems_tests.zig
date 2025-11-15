const std = @import("std");
const ecs_mod = @import("ecs.zig");
const Manager = ecs_mod.Manager;
const systems = @import("systems.zig");
const ToSystem = systems.ToSystem;
const ToSystemWithArgs = systems.ToSystemWithArgs;
const Res = systems.Res;
const Local = systems.Local;
const EventReader = systems.EventReader;
const EventWriter = systems.EventWriter;
const registry = @import("systems.registry.zig");
const DefaultRegistry = registry.DefaultParamRegistry;
const events = @import("events.zig");
const Query = @import("query.zig").Query;
const relations = @import("relations.zig");

// Test components
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

// Test resource
const DeltaTime = struct {
    value: f32,
};

// Basic system functions
fn simpleSystem(_: *Manager) void {}

fn resourceSystem(_: *Manager, res: Res(DeltaTime)) void {
    std.testing.expect(res.ptr.value == 0.016) catch unreachable;
}

fn querySystem(_: *Manager, query: Query(struct { pos: Position }, struct {})) void {
    var count: usize = 0;
    while (query.next()) |_| {
        count += 1;
    }
    std.testing.expect(count == 5) catch unreachable;
}

fn multiParamSystem(_: *Manager, res: Res(DeltaTime), query: Query(struct { pos: Position, vel: Velocity }, struct {})) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx * res.ptr.value;
        item.pos.y += item.vel.dy * res.ptr.value;
    }
}

fn localSystem(_: *Manager, local: *Local(u32)) void {
    if (!local.isSet()) {
        local.set(0);
    }
    const val = local.get();
    local.set(val + 1);
}

fn eventWriterSystem(_: *Manager, writer: EventWriter(u32)) void {
    var mut_writer = writer;
    mut_writer.write(1);
    mut_writer.write(2);
}

fn eventReaderSystem(_: *Manager, reader: EventReader(u32)) void {
    var count: usize = 0;
    while (reader.read()) |event| {
        _ = event;
        count += 1;
    }
    std.testing.expect(count == 2) catch unreachable;
}

fn systemWithArgs(_: *Manager, multiplier: i32, offset: i32) void {
    const result = multiplier * 2 + offset;
    std.testing.expect(result == 14) catch unreachable; // 5 * 2 + 4 = 14
}

fn producer(_: *Manager) u32 {
    return 42;
}

fn consumer(_: *Manager, value: u32) void {
    std.testing.expect(value == 42) catch unreachable;
}

fn predicateTrue(_: *Manager) bool {
    return true;
}

fn conditionalSystem(_: *Manager) void {}

fn mutateRes(_: *Manager, res: Res(DeltaTime)) void {
    res.ptr.value = 2.0;
}

fn checkRes(_: *Manager, res: Res(DeltaTime)) void {
    std.testing.expect(res.ptr.value == 2.0) catch unreachable;
}

fn errorSys(_: *Manager) !void {
    return error.TestError;
}

fn returnSys(_: *Manager) i32 {
    return 123; // Would return 123 if systems supported it
}

fn onAddedRemovedSystem(_: *Manager, added: systems.OnAdded(Position), removed: systems.OnRemoved(Position)) void {
    var added_count: usize = 0;
    for (added.iter()) |item| {
        _ = item;
        added_count += 1;
    }

    var removed_count: usize = 0;
    for (removed.iter()) |entity| {
        _ = entity;
        removed_count += 1;
    }

    std.testing.expect(added_count >= 1) catch unreachable;
    std.testing.expect(removed_count >= 1) catch unreachable;
}

test "System - basic execution" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const system = ToSystem(simpleSystem, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - with resource parameter" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const dt = DeltaTime{ .value = 0.016 };
    _ = try manager.addResource(DeltaTime, dt);

    const system = ToSystem(resourceSystem, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - with query parameter" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    const system = ToSystem(querySystem, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - with multiple parameters" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const dt = DeltaTime{ .value = 0.016 };
    _ = try manager.addResource(DeltaTime, dt);

    for (0..3) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    const system = ToSystem(multiParamSystem, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - Local parameter" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const system = ToSystem(localSystem, DefaultRegistry);

    // Run multiple times to test persistence
    _ = try system.run(&manager, system.ctx);
    _ = try system.run(&manager, system.ctx);
    _ = try system.run(&manager, system.ctx);
}

test "System - EventWriter and EventReader" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const write_sys = ToSystem(eventWriterSystem, DefaultRegistry);
    const read_sys = ToSystem(eventReaderSystem, DefaultRegistry);

    _ = try write_sys.run(&manager, write_sys.ctx);
    _ = try read_sys.run(&manager, read_sys.ctx);
}

test "System - createSystemCached" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const handle = manager.createSystemCached(simpleSystem, DefaultRegistry);
    _ = try manager.runSystem(handle);
}

test "System - cacheSystem" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create a system manually
    const system = manager.createSystem(simpleSystem, DefaultRegistry);

    // Cache it (should infer return type automatically)
    const handle = manager.cacheSystem(system);

    // Run the cached system
    _ = try manager.runSystem(handle);
}

test "System - ToSystemWithArgs" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const system = ToSystemWithArgs(systemWithArgs, .{ @as(i32, 5), @as(i32, 4) }, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - pipe functionality" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const piped = systems.pipe(producer, consumer, DefaultRegistry);
    _ = try piped.run(&manager, piped.ctx);
}

test "System - runIf conditional" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const conditional = systems.runIf(predicateTrue, conditionalSystem, DefaultRegistry);
    _ = try conditional.run(&manager, conditional.ctx);
}

test "System - resource mutation" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const dt = DeltaTime{ .value = 1.0 };
    _ = try manager.addResource(DeltaTime, dt);

    const sys1 = ToSystem(mutateRes, DefaultRegistry);
    const sys2 = ToSystem(checkRes, DefaultRegistry);

    _ = try sys1.run(&manager, sys1.ctx);
    _ = try sys2.run(&manager, sys2.ctx);
}

test "System - error handling" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const system = ToSystem(errorSys, DefaultRegistry);
    const result = system.run(&manager, system.ctx);

    try std.testing.expectError(error.TestError, result);
}

test "System - return value" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const system = ToSystem(returnSys, DefaultRegistry);
    const ret = try system.run(&manager, system.ctx);

    try std.testing.expect(ret == 123);
}

test "System - OnAdded and OnRemoved system params" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Ensure no leftover component events from earlier tests
    manager.component_added.clear();
    manager.component_removed.clear();

    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, .{ .x = 1, .y = 2 });
    try manager.removeComponent(entity, Position);

    const system = ToSystem(onAddedRemovedSystem, DefaultRegistry);
    _ = try system.run(&manager, system.ctx);
}

test "System - multiple cached systems" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const h1 = manager.createSystemCached(simpleSystem, DefaultRegistry);
    const h2 = manager.createSystemCached(resourceSystem, DefaultRegistry);

    try std.testing.expect(h1.handle != h2.handle);
}
