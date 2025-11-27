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

    try world.removeComponent(entity, B);

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

    try world.removeComponent(entity, B);

    try std.testing.expect(world.has(entity, A));
    try std.testing.expect(!world.has(entity, B));
}

test "World.removeComponent on last component leaves entity with no components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    try world.add(entity, .{A{ .value = 42 }});

    try std.testing.expect(world.has(entity, A));

    try world.removeComponent(entity, A);

    try std.testing.expect(!world.has(entity, A));

    const comps = try world.getAllComponents(std.testing.allocator, entity);
    defer std.testing.allocator.free(comps);
    try std.testing.expect(comps.len == 0);
}
