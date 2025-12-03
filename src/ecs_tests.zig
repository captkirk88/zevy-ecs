const std = @import("std");
const ecs = @import("ecs.zig");
const Manager = ecs.Manager;
const Entity = ecs.Entity;

// Test components
const Position = packed struct {
    x: f32,
    y: f32,
};

const Velocity = packed struct {
    dx: f32,
    dy: f32,
};

const Health = struct {
    current: i32,
    max: i32,
};

const Name = struct {
    value: []const u8,
};

// Test resource
const GameConfig = packed struct {
    difficulty: u8,
    max_players: u32,
};

test "Manager - init and deinit" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(manager.count() == 0);
    try std.testing.expect(manager.next_entity_id == 0);
}

test "Manager - createEmpty entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const entity1 = manager.createEmpty();
    const entity2 = manager.createEmpty();

    try std.testing.expect(entity1.id == 0);
    try std.testing.expect(entity2.id == 1);
    try std.testing.expect(entity1.generation == 0);
    try std.testing.expect(entity2.generation == 0);
    try std.testing.expect(manager.count() == 2);
}

test "Manager - create entity with components" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .dx = 1.0, .dy = 2.0 };

    const entity = manager.create(.{ pos, vel });

    try std.testing.expect(entity.id == 0);
    try std.testing.expect(manager.count() == 1);
    try std.testing.expect(manager.isAlive(entity));
}

test "Manager - create multiple entities" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var entities: [100]Entity = undefined;
    for (&entities, 0..) |*e, i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        e.* = manager.create(.{pos});
    }

    try std.testing.expect(manager.count() == 100);

    for (entities) |e| {
        try std.testing.expect(manager.isAlive(e));
    }
}

test "Manager - createBatch" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 5.0, .y = 10.0 };
    const vel = Velocity{ .dx = 0.5, .dy = -0.5 };

    const entities = try manager.createBatch(std.testing.allocator, 1000, .{ pos, vel });
    defer std.testing.allocator.free(entities);

    try std.testing.expect(entities.len == 1000);
    try std.testing.expect(manager.count() == 1000);

    for (entities) |e| {
        try std.testing.expect(manager.isAlive(e));
    }
}

test "Manager - isAlive with valid entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const entity = manager.createEmpty();
    try std.testing.expect(manager.isAlive(entity));
}

test "Manager - isAlive with invalid entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fake_entity = Entity{ .id = 999, .generation = 0 };
    try std.testing.expect(!manager.isAlive(fake_entity));
}

test "Manager - addComponent to entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const entity = manager.createEmpty();
    const pos = Position{ .x = 15.0, .y = 25.0 };

    try manager.addComponent(entity, Position, pos);

    const retrieved = try manager.getComponent(entity, Position);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.x == 15.0);
    try std.testing.expect(retrieved.?.y == 25.0);
}

test "Manager - addComponent to dead entity fails" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const fake_entity = Entity{ .id = 999, .generation = 0 };
    const pos = Position{ .x = 0.0, .y = 0.0 };

    const result = manager.addComponent(fake_entity, Position, pos);
    try std.testing.expectError(error.EntityNotAlive, result);
}

test "Manager - getComponent returns component" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 100.0, .y = 200.0 };
    const entity = manager.create(.{pos});

    const retrieved = try manager.getComponent(entity, Position);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.x == 100.0);
    try std.testing.expect(retrieved.?.y == 200.0);
}

test "Manager - getComponent mutability" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 50.0, .y = 60.0 };
    const entity = manager.create(.{pos});

    const retrieved = try manager.getComponent(entity, Position);
    try std.testing.expect(retrieved != null);

    // Modify the component
    retrieved.?.x = 999.0;
    retrieved.?.y = 888.0;

    // Get it again to verify mutation
    const retrieved2 = try manager.getComponent(entity, Position);
    try std.testing.expect(retrieved2 != null);
    try std.testing.expect(retrieved2.?.x == 999.0);
    try std.testing.expect(retrieved2.?.y == 888.0);
}

test "Manager - getComponent returns null for missing component" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const entity = manager.create(.{pos});

    const vel = try manager.getComponent(entity, Velocity);
    try std.testing.expect(vel == null);
}

test "Manager - hasComponent returns true when present" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    const has_pos = try manager.hasComponent(entity, Position);
    try std.testing.expect(has_pos);
}

test "Manager - hasComponent returns false when absent" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    const has_vel = try manager.hasComponent(entity, Velocity);
    try std.testing.expect(!has_vel);
}

test "Manager - removeComponent" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
    const entity = manager.create(.{ pos, vel });

    try std.testing.expect(try manager.hasComponent(entity, Velocity));

    try manager.removeComponent(entity, Velocity);

    try std.testing.expect(!try manager.hasComponent(entity, Velocity));
    try std.testing.expect(try manager.hasComponent(entity, Position));
}

test "Manager - getAllComponents" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 5.0, .y = 10.0 };
    const vel = Velocity{ .dx = 2.0, .dy = 3.0 };
    const health = Health{ .current = 100, .max = 100 };

    const entity = manager.create(.{ pos, vel, health });

    const components = try manager.getAllComponents(std.testing.allocator, entity);
    defer std.testing.allocator.free(components);

    try std.testing.expect(components.len == 3);
}

test "Manager - addResource" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 5, .max_players = 10 };
    const res = try manager.addResource(GameConfig, config);

    try std.testing.expect(res.difficulty == 5);
    try std.testing.expect(res.max_players == 10);
}

test "Manager - addResource duplicate fails" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config1 = GameConfig{ .difficulty = 5, .max_players = 10 };
    _ = try manager.addResource(GameConfig, config1);

    const config2 = GameConfig{ .difficulty = 8, .max_players = 20 };
    const result = manager.addResource(GameConfig, config2);
    try std.testing.expectError(error.ResourceAlreadyExists, result);
}

test "Manager - getResource returns resource" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 7, .max_players = 15 };
    _ = try manager.addResource(GameConfig, config);

    const retrieved = manager.getResource(GameConfig);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.difficulty == 7);
    try std.testing.expect(retrieved.?.max_players == 15);
}

test "Manager - getResource returns null for missing resource" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const retrieved = manager.getResource(GameConfig);
    try std.testing.expect(retrieved == null);
}

test "Manager - hasResource" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expect(!manager.hasResource(GameConfig));

    const config = GameConfig{ .difficulty = 3, .max_players = 5 };
    _ = try manager.addResource(GameConfig, config);

    try std.testing.expect(manager.hasResource(GameConfig));
}

test "Manager - removeResource" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 4, .max_players = 8 };
    _ = try manager.addResource(GameConfig, config);

    try std.testing.expect(manager.hasResource(GameConfig));

    manager.removeResource(GameConfig);

    try std.testing.expect(!manager.hasResource(GameConfig));
}

test "Manager - listResourceTypes" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 1, .max_players = 4 };
    _ = try manager.addResource(GameConfig, config);

    const score: i32 = 1000;
    _ = try manager.addResource(i32, score);

    var types = manager.listResourceTypes(std.testing.allocator);
    defer types.deinit(std.testing.allocator);

    try std.testing.expect(types.items.len == 3);
}

test "Manager - query basic" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos1 = Position{ .x = 1.0, .y = 2.0 };
    const pos2 = Position{ .x = 3.0, .y = 4.0 };
    _ = manager.create(.{pos1});
    _ = manager.create(.{pos2});

    var query = manager.query(struct { pos: Position }, struct {});
    var count: usize = 0;
    while (query.next()) |item| {
        try std.testing.expect(item.pos.x > 0.0);
        count += 1;
    }

    try std.testing.expect(count == 2);
}

test "Manager - entity eql method" {
    const e1 = Entity{ .id = 1, .generation = 0 };
    const e2 = Entity{ .id = 1, .generation = 0 };
    const e3 = Entity{ .id = 1, .generation = 1 };
    const e4 = Entity{ .id = 2, .generation = 0 };

    try std.testing.expect(e1.eql(e2));
    try std.testing.expect(!e1.eql(e3));
    try std.testing.expect(!e1.eql(e4));
}

test "Manager - multiple component types per entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .dx = 5.0, .dy = -5.0 };
    const health = Health{ .current = 50, .max = 100 };

    const entity = manager.create(.{ pos, vel, health });

    try std.testing.expect(try manager.hasComponent(entity, Position));
    try std.testing.expect(try manager.hasComponent(entity, Velocity));
    try std.testing.expect(try manager.hasComponent(entity, Health));
}

test "Manager - component migration when adding to existing entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    try std.testing.expect(try manager.hasComponent(entity, Position));
    try std.testing.expect(!try manager.hasComponent(entity, Velocity));

    const vel = Velocity{ .dx = 3.0, .dy = 4.0 };
    try manager.addComponent(entity, Velocity, vel);

    try std.testing.expect(try manager.hasComponent(entity, Position));
    try std.testing.expect(try manager.hasComponent(entity, Velocity));

    // Verify old component data is preserved
    const pos_check = try manager.getComponent(entity, Position);
    try std.testing.expect(pos_check != null);
    try std.testing.expect(pos_check.?.x == 1.0);
    try std.testing.expect(pos_check.?.y == 2.0);
}

test "Manager - stress test entity creation and component access" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const count = 10_000;
    var entities = try std.ArrayList(Entity).initCapacity(std.testing.allocator, count);
    defer entities.deinit(std.testing.allocator);

    // Create many entities
    for (0..count) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2) };
        const entity = manager.create(.{pos});
        try entities.append(std.testing.allocator, entity);
    }

    try std.testing.expect(manager.count() == count);

    // Verify all entities are alive and have correct components
    for (entities.items, 0..) |entity, i| {
        try std.testing.expect(manager.isAlive(entity));
        const pos = try manager.getComponent(entity, Position);
        try std.testing.expect(pos != null);
        try std.testing.expect(pos.?.x == @as(f32, @floatFromInt(i)));
    }
}

test "Manager - resource mutation through pointer" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 1, .max_players = 2 };
    const res = try manager.addResource(GameConfig, config);

    // Mutate through original pointer
    res.difficulty = 10;
    res.max_players = 20;

    // Get resource again and verify mutation
    const retrieved = manager.getResource(GameConfig);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.difficulty == 10);
    try std.testing.expect(retrieved.?.max_players == 20);
}
