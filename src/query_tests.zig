const std = @import("std");
const query_mod = @import("query.zig");
const Query = query_mod.Query;
const ecs = @import("ecs.zig");
const Manager = ecs.Manager;
const Entity = ecs.Entity;

// Test components
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

const Health = struct {
    value: i32,
};

const Armor = struct {
    defense: i32,
};

const Team = struct {
    id: u8,
};

test "Query - basic iteration with single component" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create entities with Position
    for (0..10) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2) };
        _ = manager.create(.{pos});
    }

    var q = manager.query(struct { pos: Position }, struct {});
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x >= 0.0);
        count += 1;
    }

    try std.testing.expect(count == 10);
}

test "Query - multiple components" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create entities with Position and Velocity
    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    // Create entities with only Position
    for (0..3) |_| {
        const pos = Position{ .x = 100.0, .y = 100.0 };
        _ = manager.create(.{pos});
    }

    var q = manager.query(struct { pos: Position, vel: Velocity }, struct {});
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x < 100.0);
        try std.testing.expect(item.vel.dx == 1.0);
        count += 1;
    }

    // Should only match the 5 entities with both components
    try std.testing.expect(count == 5);
}

test "Query - exclude pattern" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create entities with Position and Health
    for (0..5) |_| {
        const pos = Position{ .x = 10.0, .y = 20.0 };
        const health = Health{ .value = 100 };
        _ = manager.create(.{ pos, health });
    }

    // Create entities with Position, Health, and Armor
    for (0..3) |_| {
        const pos = Position{ .x = 30.0, .y = 40.0 };
        const health = Health{ .value = 150 };
        const armor = Armor{ .defense = 50 };
        _ = manager.create(.{ pos, health, armor });
    }

    // Query for Position and Health, but exclude Armor
    var q = manager.query(struct { pos: Position, health: Health }, struct { armor: Armor });
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 10.0);
        try std.testing.expect(item.health.value == 100);
        count += 1;
    }

    // Should only match the 5 entities without Armor
    try std.testing.expect(count == 5);
}

test "Query - with Entity field" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var entities: [5]Entity = undefined;
    for (&entities) |*e| {
        const pos = Position{ .x = 1.0, .y = 2.0 };
        e.* = manager.create(.{pos});
    }

    var q = manager.query(struct { entity: Entity, pos: Position }, struct {});
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(manager.isAlive(item.entity));
        try std.testing.expect(item.pos.x == 1.0);
        count += 1;
    }

    try std.testing.expect(count == 5);
}

test "Query - only Entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..20) |_| {
        _ = manager.createEmpty();
    }

    var q = manager.query(struct { entity: Entity }, struct {});
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(manager.isAlive(item.entity));
        count += 1;
    }

    try std.testing.expect(count == 20);
}

test "Query - empty query (no entities match)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create entities with Position only
    for (0..5) |_| {
        const pos = Position{ .x = 1.0, .y = 2.0 };
        _ = manager.create(.{pos});
    }

    // Query for Velocity (no entities have it)
    var q = manager.query(struct { vel: Velocity }, struct {});
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }

    try std.testing.expect(count == 0);
}

test "Query - mutation through query" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..10) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    // First pass: mutate all positions
    var q1 = manager.query(struct { pos: Position }, struct {});
    while (q1.next()) |item| {
        item.pos.x += 100.0;
        item.pos.y = 50.0;
    }

    // Second pass: verify mutations
    var q2 = manager.query(struct { pos: Position }, struct {});
    var count: usize = 0;
    while (q2.next()) |item| {
        try std.testing.expect(item.pos.x >= 100.0);
        try std.testing.expect(item.pos.y == 50.0);
        count += 1;
    }

    try std.testing.expect(count == 10);
}

test "Query - optional components" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create entities with Position and Velocity
    for (0..3) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    // Create entities with only Position
    for (3..6) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    // Query with optional Velocity
    var q = manager.query(struct { pos: Position, vel: ?Velocity }, struct {});
    var count_with_vel: usize = 0;
    var count_without_vel: usize = 0;
    var total: usize = 0;

    while (q.next()) |item| {
        total += 1;
        if (item.vel) |vel| {
            try std.testing.expect(vel.dx == 1.0);
            count_with_vel += 1;
        } else {
            count_without_vel += 1;
        }
    }

    try std.testing.expect(total == 6);
    try std.testing.expect(count_with_vel == 3);
    try std.testing.expect(count_without_vel == 3);
}

test "Query - multiple archetypes" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Create different archetype combinations, all having Position
    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i + 10), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i + 20), .y = 0.0 };
        const health = Health{ .value = 100 };
        _ = manager.create(.{ pos, health });
    }

    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i + 30), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        const health = Health{ .value = 100 };
        _ = manager.create(.{ pos, vel, health });
    }

    // Query for Position across all archetypes
    var q = manager.query(struct { pos: Position }, struct {});
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }

    try std.testing.expect(count == 20);
}

test "Query - complex exclude pattern" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Entities with Position, Velocity
    for (0..5) |_| {
        const pos = Position{ .x = 1.0, .y = 1.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    // Entities with Position, Velocity, Team
    for (0..5) |_| {
        const pos = Position{ .x = 2.0, .y = 2.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        const team = Team{ .id = 1 };
        _ = manager.create(.{ pos, vel, team });
    }

    // Entities with Position, Velocity, Armor
    for (0..5) |_| {
        const pos = Position{ .x = 3.0, .y = 3.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        const armor = Armor{ .defense = 10 };
        _ = manager.create(.{ pos, vel, armor });
    }

    // Query for Position and Velocity, but exclude both Team and Armor
    var q = manager.query(struct { pos: Position, vel: Velocity }, struct { team: Team, armor: Armor });
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 1.0);
        count += 1;
    }

    try std.testing.expect(count == 5);
}

test "Query - large dataset iteration" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const count = 10_000;

    for (0..count) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = @floatFromInt(i * 2) };
        const vel = Velocity{ .dx = 0.5, .dy = -0.5 };
        _ = manager.create(.{ pos, vel });
    }

    var q = manager.query(struct { pos: Position, vel: Velocity }, struct {});
    var iteration_count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x >= 0.0);
        try std.testing.expect(item.vel.dx == 0.5);
        iteration_count += 1;
    }

    try std.testing.expect(iteration_count == count);
}

test "Query - entity and multiple components" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var entities: [10]Entity = undefined;
    for (&entities, 0..) |*e, i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        const health = Health{ .value = 100 };
        e.* = manager.create(.{ pos, vel, health });
    }

    var q = manager.query(struct { entity: Entity, pos: Position, vel: Velocity, health: Health }, struct {});
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(manager.isAlive(item.entity));
        try std.testing.expect(item.pos.x >= 0.0);
        try std.testing.expect(item.vel.dx == 1.0);
        try std.testing.expect(item.health.value == 100);
        count += 1;
    }

    try std.testing.expect(count == 10);
}

test "Query - mixed optional and required components" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Entities with Position, Velocity, Health
    for (0..3) |_| {
        const pos = Position{ .x = 1.0, .y = 1.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        const health = Health{ .value = 100 };
        _ = manager.create(.{ pos, vel, health });
    }

    // Entities with Position, Velocity (no Health)
    for (0..2) |_| {
        const pos = Position{ .x = 2.0, .y = 2.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 1.0 };
        _ = manager.create(.{ pos, vel });
    }

    // Query with required Position, Velocity and optional Health
    var q = manager.query(struct { pos: Position, vel: Velocity, health: ?Health }, struct {});
    var count_with_health: usize = 0;
    var count_without_health: usize = 0;

    while (q.next()) |item| {
        try std.testing.expect(item.pos.x > 0.0);
        try std.testing.expect(item.vel.dx == 1.0);

        if (item.health) |health| {
            try std.testing.expect(health.value == 100);
            count_with_health += 1;
        } else {
            count_without_health += 1;
        }
    }

    try std.testing.expect(count_with_health == 3);
    try std.testing.expect(count_without_health == 2);
}

test "Query - empty entity set" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var q = manager.query(struct { pos: Position }, struct {});
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }

    try std.testing.expect(count == 0);
}

test "Query - query result consistency across multiple iterations" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..5) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    // First iteration
    var q1 = manager.query(struct { pos: Position }, struct {});
    var count1: usize = 0;
    while (q1.next()) |_| {
        count1 += 1;
    }

    // Second iteration with new query
    var q2 = manager.query(struct { pos: Position }, struct {});
    var count2: usize = 0;
    while (q2.next()) |_| {
        count2 += 1;
    }

    try std.testing.expect(count1 == count2);
    try std.testing.expect(count1 == 5);
}
