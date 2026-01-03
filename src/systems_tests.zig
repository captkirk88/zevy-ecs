const std = @import("std");
const builtin = @import("builtin");
const is_debug = builtin.mode == .Debug;

const ecs_mod = @import("ecs.zig");
const Manager = ecs_mod.Manager;
const systems = @import("systems.zig");
const ToSystem = systems.ToSystem;
const ToSystemWithArgs = systems.ToSystemWithArgs;
const params = @import("systems.params.zig");
const Res = params.Res;
const Local = params.Local;
const EventReader = params.EventReader;
const EventWriter = params.EventWriter;
const registry = @import("systems.registry.zig");
const DefaultRegistry = registry.DefaultParamRegistry;
const events = @import("events.zig");
const Query = @import("query.zig").Query;
const Commands = @import("commands.zig").Commands;
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

const ChainCounter = struct {
    value: i32,
};

// Basic system functions
fn simpleSystem() void {}

fn resourceSystem(res: Res(DeltaTime)) void {
    std.testing.expect(res.ptr.value == 0.016) catch unreachable;
}

fn querySystem(query: Query(struct { pos: Position }, struct {})) void {
    var count: usize = 0;
    while (query.next()) |_| {
        count += 1;
    }
    std.testing.expect(count == 5) catch unreachable;
}

fn multiParamSystem(res: Res(DeltaTime), query: Query(struct { pos: Position, vel: Velocity }, struct {})) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx * res.ptr.value;
        item.pos.y += item.vel.dy * res.ptr.value;
    }
}

fn localSystem(local: *Local(u32)) void {
    if (!local.isSet()) {
        local.set(0);
    }
    const val = local.get();
    local.set(val + 1);
}

fn eventWriterSystem(writer: EventWriter(u32)) void {
    var mut_writer = writer;
    mut_writer.write(1);
    mut_writer.write(2);
}

fn eventReaderSystem(reader: EventReader(u32)) void {
    var count: usize = 0;
    while (reader.read()) |event| {
        _ = event;
        count += 1;
    }
    std.testing.expect(count == 2) catch unreachable;
}

fn systemWithArgs(multiplier: i32, offset: i32) void {
    const result = multiplier * 2 + offset;
    std.testing.expect(result == 14) catch unreachable; // 5 * 2 + 4 = 14
}

fn chainIncrementCounter(res: Res(ChainCounter)) void {
    res.ptr.value += 1;
}

fn chainMultiplyCounter(res: Res(ChainCounter)) void {
    res.ptr.value *= 3;
}

fn producer() u32 {
    return 42;
}

fn producerError() !u32 {
    return error.TestError;
}

fn consumer(value: u32) void {
    std.testing.expect(value == 42) catch unreachable;
}

fn predicateTrue() bool {
    return true;
}

fn conditionalSystem() void {}

const GameState = enum { menu, playing, paused };

fn actualFuncSystem(
    commands: *Commands,
    res: Res(DeltaTime),
    local: *Local(u32),
    query: Query(struct { pos: Position }, .{Velocity}),
    single: params.Single(struct { vel: Velocity }, .{}),
    event_reader: EventReader(u32),
    event_writer: EventWriter(u32),
    on_added: params.OnAdded(Position),
    on_removed: params.OnRemoved(Position),
    relation_mgr: *params.Relations,
) void {
    _ = commands;
    _ = res;
    _ = local;
    _ = query;
    _ = single;
    _ = event_reader;
    _ = event_writer;
    _ = on_added;
    _ = on_removed;
    _ = relation_mgr;
}

fn mutateRes(res: Res(DeltaTime)) void {
    res.ptr.value = 2.0;
}

fn checkRes(res: Res(DeltaTime)) void {
    std.testing.expect(res.ptr.value == 2.0) catch unreachable;
}

fn errorSys() !void {
    return error.TestError;
}

fn returnSys() i32 {
    return 123; // Would return 123 if systems supported it
}

fn onAddedRemovedSystem(added: params.OnAdded(Position), removed: params.OnRemoved(Position)) anyerror!void {
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

    if (added.items.len != 0)
        try std.testing.expectEqual(1, added_count);
    if (removed.removed.len != 0)
        try std.testing.expectEqual(1, removed_count);
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

test "System - pipe propagates error from first system" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const piped = systems.pipe(producerError, consumer, DefaultRegistry);
    const result = piped.run(&manager, piped.ctx);
    try std.testing.expectError(error.TestError, result);
}

test "System - runIf conditional" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const conditional = systems.runIf(predicateTrue, conditionalSystem, DefaultRegistry);
    _ = try conditional.run(&manager, conditional.ctx);
}

test "System - chain runs systems sequentially" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const counter = ChainCounter{ .value = 2 };
    _ = try manager.addResource(ChainCounter, counter);

    const ChainSystems: [2]fn (res: Res(ChainCounter)) void = .{ chainIncrementCounter, chainMultiplyCounter };
    const chained = systems.chain(ChainSystems, DefaultRegistry);
    _ = try chained.run(&manager, chained.ctx);

    const result = manager.getResource(ChainCounter) orelse unreachable;
    try std.testing.expect(result.value == 9);
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
    const system = ToSystem(onAddedRemovedSystem, DefaultRegistry);
    // Ensure no leftover component events from earlier tests
    manager.component_added.clear();
    manager.component_removed.clear();

    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, .{ .x = 1, .y = 2 });
    _ = try system.run(&manager, system.ctx);

    try manager.removeComponent(entity, Position);

    _ = try system.run(&manager, system.ctx);
}

test "System signature populated in Debug mode" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const system = ToSystem(TestSystem, DefaultRegistry);

    if (is_debug) {
        // In debug mode, debug_info should be populated with function signature
        try std.testing.expect(system.debug_info.signature.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.signature, "fn") != null);
    } else {
        // In release mode, debug_info is void (no field access needed)
        const debug_info_type = @TypeOf(system.debug_info);
        try std.testing.expect(debug_info_type == void);
    }
}

test "SystemHandle signature in Debug mode" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const handle = manager.createSystemCached(TestSystem, DefaultRegistry);

    if (is_debug) {
        // In debug mode, debug_info should be populated with function signature
        std.debug.print("System debug sig: {s}\n", .{handle.debug_info.signature});
        try std.testing.expect(handle.debug_info.signature.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, handle.debug_info.signature, "fn") != null);
    } else {
        // In release mode, debug_info is void
        const debug_info_type = @TypeOf(handle.debug_info);
        try std.testing.expect(debug_info_type == void);
    }
}

test "UntypedSystemHandle signature in Debug mode" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const handle = manager.createSystemCached(TestSystem, DefaultRegistry);
    const untyped = handle.eraseType();

    if (is_debug) {
        // In debug mode, debug_info should be populated with function signature
        std.debug.print("Untyped debug sig: {s}\n", .{untyped.debug_info.signature});
        try std.testing.expect(untyped.debug_info.signature.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, untyped.debug_info.signature, "fn") != null);
    } else {
        // In release mode, debug_info is void
        const debug_info_type = @TypeOf(untyped.debug_info);
        try std.testing.expect(debug_info_type == void);
    }
}

test "UntypedSystemHandle format includes sig in Debug mode" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const handle = manager.createSystemCached(TestSystem, DefaultRegistry);
    const untyped = handle.eraseType();

    // Format the handle as a string using {f} to call format method
    var buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buffer.deinit(std.testing.allocator);
    try buffer.writer(std.testing.allocator).print("{f}", .{untyped});

    const formatted = buffer.items;

    if (is_debug) {
        // In debug mode, the formatted output should include both handle and sig
        std.debug.print("Formatted untyped handle: {s}\n", .{formatted});
        try std.testing.expect(std.mem.indexOf(u8, formatted, "SystemHandle") != null);
        try std.testing.expect(std.mem.indexOf(u8, formatted, ".sig = ") != null);
    } else {
        // In release mode, should only show handle number
        std.debug.print("Formatted untyped handle (release): {s}\n", .{formatted});
        try std.testing.expect(std.mem.indexOf(u8, formatted, "SystemHandle") != null);
    }
}

test "SystemHandle format with {d} shows only number" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const handle = manager.createSystemCached(TestSystem, DefaultRegistry);
    const untyped = handle.eraseType();

    // Format with {d} specifier
    var buffer = try std.ArrayList(u8).initCapacity(std.testing.allocator, 0);
    defer buffer.deinit(std.testing.allocator);
    try buffer.writer(std.testing.allocator).print("{d}", .{untyped});

    const formatted = buffer.items;

    // Should only contain digits (the handle number)
    try std.testing.expect(formatted.len > 0);
    for (formatted) |c| {
        try std.testing.expect(std.ascii.isDigit(c));
    }
}

test "Multiple systems have different debug sigs" {
    if (!is_debug) return error.SkipZigTest;

    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Use systems with different signatures to get different output
    const System1 = struct {
        pub fn run(_: *Manager) void {}
    }.run;

    const System2 = struct {
        pub fn run(_: *Manager) i32 {
            return 42;
        }
    }.run;

    const handle1 = manager.createSystemCached(System1, DefaultRegistry);
    const handle2 = manager.createSystemCached(System2, DefaultRegistry);

    // Different systems should have different debug sigs (different return types)
    try std.testing.expect(!std.mem.eql(u8, handle1.debug_info.signature, handle2.debug_info.signature));
}

test "System with injected args has correct debug name" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const TestSystem = struct {
        pub fn run(_: i32, _: []const u8) void {}
    }.run;

    const system = ToSystemWithArgs(TestSystem, .{ 42, "test" }, DefaultRegistry);

    if (is_debug) {
        try std.testing.expect(system.debug_info.signature.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.signature, "fn") != null);
    }
}

test "SystemDebugInfo contains parameter information" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Setup resources and entities for the system
    const dt = DeltaTime{ .value = 0.016 };
    _ = try manager.addResource(DeltaTime, dt);

    // Create entities for Query and Single to work
    const pos_entity = manager.create(.{Position{ .x = 1.0, .y = 2.0 }});
    _ = manager.create(.{Velocity{ .dx = 3.0, .dy = 4.0 }});

    // Trigger component events for OnAdded/OnRemoved
    try manager.addComponent(pos_entity, Position, Position{ .x = 5.0, .y = 6.0 });
    try manager.removeComponent(pos_entity, Position);

    const system = ToSystem(actualFuncSystem, DefaultRegistry);

    if (is_debug) {
        std.debug.print("\nSystem signature: {s}\n", .{system.debug_info.signature});
        std.debug.print("Number of params: {}\n", .{system.debug_info.params.len});

        for (system.debug_info.params, 0..) |param, i| {
            std.debug.print("  Param {}: type={s}\n", .{ i, param.name });
        }

        // Should have 10 params (including Commands)
        try std.testing.expect(system.debug_info.params.len == 10);

        // Verify param types
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[0].name, "Commands") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[1].name, "Res") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[2].name, "Local") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[3].name, "Query") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[4].name, "Single") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[5].name, "EventReader") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[6].name, "EventWriter") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[7].name, "OnAdded") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[8].name, "OnRemoved") != null);
        try std.testing.expect(std.mem.indexOf(u8, system.debug_info.params[9].name, "RelationManager") != null);
    }
}
