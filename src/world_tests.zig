const std = @import("std");
const ecs = @import("ecs.zig");
const World = @import("world.zig").World;
const ComponentInstance = @import("world.zig").ComponentInstance;

const Entity = ecs.Entity;

const A = struct { value: i32 };
const B = struct { value: i32 };

fn makeEntityWithAB(world: *World, entity: Entity) !void {
    try world.add(entity, .{ A{ .value = 1 }, B{ .value = 2 } });
}

test "World.removeComponent migrates archetype and keeps other components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    try makeEntityWithAB(&world, entity);

    try std.testing.expect(world.has(entity, A));
    try std.testing.expect(world.has(entity, B));

    _ = try world.removeComponent(entity, B);

    try std.testing.expect(world.has(entity, A));
    try std.testing.expect(!world.has(entity, B));
}

test "World.removeComponent is no-op when component not present" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    try world.add(entity, .{A{ .value = 10 }});

    try std.testing.expect(world.has(entity, A));
    try std.testing.expect(!world.has(entity, B));

    _ = try world.removeComponent(entity, B);

    try std.testing.expect(world.has(entity, A));
    try std.testing.expect(!world.has(entity, B));
}

test "World.removeComponent on last component leaves entity with no components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    try world.add(entity, .{A{ .value = 42 }});

    try std.testing.expect(world.has(entity, A));

    _ = try world.removeComponent(entity, A);

    try std.testing.expect(!world.has(entity, A));

    const comps = try world.getAllComponents(std.testing.allocator, entity);
    defer std.testing.allocator.free(comps);
    try std.testing.expect(comps.len == 0);
}

test "World.removeComponent calls deinit on the removed component" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    var deinit_count: usize = 0;

    const Managed = struct {
        counter: *usize,
        pub fn deinit(self: *@This()) void {
            self.counter.* += 1;
        }
    };

    const entity = Entity{ .id = 0, .generation = 0 };
    try world.add(entity, .{ Managed{ .counter = &deinit_count }, A{ .value = 1 } });

    try std.testing.expectEqual(@as(usize, 0), deinit_count);
    _ = try world.removeComponent(entity, Managed);
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    // A is still present; no extra deinit should have fired
    try std.testing.expect(world.has(entity, A));
    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

test "World.removeComponent calls deinit(allocator) on the removed component" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    var deinit_count: usize = 0;

    const ManagedAlloc = struct {
        counter: *usize,
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            _ = allocator;
            self.counter.* += 1;
        }
    };

    const entity = Entity{ .id = 0, .generation = 0 };
    try world.add(entity, .{ ManagedAlloc{ .counter = &deinit_count }, A{ .value = 1 } });

    try std.testing.expectEqual(@as(usize, 0), deinit_count);
    _ = try world.removeComponent(entity, ManagedAlloc);
    try std.testing.expectEqual(@as(usize, 1), deinit_count);

    try std.testing.expect(world.has(entity, A));
    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

