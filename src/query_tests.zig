const std = @import("std");
const query_mod = @import("query.zig");
const Query = query_mod.Query;
const With = query_mod.With;
const Without = query_mod.Without;
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

    var q = manager.query(struct { pos: Position });
    defer q.deinit();
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

    var q = manager.query(struct { pos: Position, vel: Velocity });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x < 100.0);
        try std.testing.expect(item.vel.dx == 1.0);
        count += 1;
    }

    // Should only match the 5 entities with both components
    try std.testing.expect(count == 5);
}

test "Query - Without(T) filters archetypes without yielding a field" {
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

    // Query for Position and Health, but exclude Armor without producing a result field
    var q = manager.query(struct {
        pos: Position,
        health: Health,
        no_armor: Without(Armor),
    });
    defer q.deinit();
    comptime {
        if (@hasField(@TypeOf(q).IncludeTypesTupleType, "no_armor")) {
            @compileError("Without markers must not appear in query results.");
        }
    }
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 10.0);
        try std.testing.expect(item.health.value == 100);
        count += 1;
    }

    // Should only match the 5 entities without Armor
    try std.testing.expect(count == 5);
}

test "Query - With(T) filters archetypes without yielding a field" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..4) |i| {
        _ = manager.create(.{ Position{ .x = @floatFromInt(i), .y = 0.0 }, Health{ .value = 100 } });
    }
    for (0..2) |i| {
        _ = manager.create(.{Position{ .x = @floatFromInt(i + 10), .y = 0.0 }});
    }

    var q = manager.query(struct {
        pos: Position,
        requires_health: With(Health),
    });
    defer q.deinit();
    comptime {
        if (@hasField(@TypeOf(q).IncludeTypesTupleType, "requires_health")) {
            @compileError("With markers must not appear in query results.");
        }
    }

    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x < 10.0);
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 4), count);
}

test "Query - With and Without tuple payloads" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Health{ .value = 100 }, Team{ .id = 1 } });
    _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Health{ .value = 100 }, Team{ .id = 1 }, Armor{ .defense = 5 } });
    _ = manager.create(.{ Position{ .x = 3.0, .y = 0.0 }, Health{ .value = 100 } });
    _ = manager.create(.{ Position{ .x = 4.0, .y = 0.0 }, Team{ .id = 1 } });

    var q = manager.query(struct {
        pos: Position,
        required: With(.{ Health, Team }),
        rejected: Without(.{ Armor, Velocity }),
    });
    defer q.deinit();

    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expectEqual(@as(f32, 1.0), item.pos.x);
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 1), count);
}

test "Query - with Entity field" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var entities: [5]Entity = undefined;
    for (&entities) |*e| {
        const pos = Position{ .x = 1.0, .y = 2.0 };
        e.* = manager.create(.{pos});
    }

    var q = manager.query(struct { entity: Entity, pos: Position });
    defer q.deinit();
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

    var q = manager.query(struct { entity: Entity });
    defer q.deinit();
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
    var q = manager.query(struct { vel: Velocity });
    defer q.deinit();
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
    var q1 = manager.query(struct { pos: Position });
    defer q1.deinit();
    while (q1.next()) |item| {
        item.pos.x += 100.0;
        item.pos.y = 50.0;
    }

    // Second pass: verify mutations
    var q2 = manager.query(struct { pos: Position });
    defer q2.deinit();
    var count: usize = 0;
    while (q2.next()) |item| {
        try std.testing.expect(item.pos.x >= 100.0);
        try std.testing.expect(item.pos.y == 50.0);
        count += 1;
    }

    try std.testing.expect(count == 10);
}

test "Query - entity() returns the last yielded entity" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    var expected_entities: [4]Entity = undefined;
    for (&expected_entities, 0..) |*entity, i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        entity.* = manager.create(.{pos});
    }

    var q = manager.query(struct { pos: Position });
    defer q.deinit();

    var index: usize = 0;
    while (q.next()) |_| {
        try std.testing.expectEqual(expected_entities[index], q.entity());
        index += 1;
    }

    try std.testing.expectEqual(@as(usize, expected_entities.len), index);
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
    var q = manager.query(struct { pos: Position, vel: ?Velocity });
    defer q.deinit();
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
    var q = manager.query(struct { pos: Position });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }

    try std.testing.expect(count == 20);
}

test "Query - complex Without tuple pattern" {
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
    var q = manager.query(struct {
        pos: Position,
        vel: Velocity,
        filtered: Without(.{ Team, Armor }),
    });
    defer q.deinit();
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

    var q = manager.query(struct { pos: Position, vel: Velocity });
    defer q.deinit();
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

    var q = manager.query(struct { entity: Entity, pos: Position, vel: Velocity, health: Health });
    defer q.deinit();
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
    var q = manager.query(struct { pos: Position, vel: Velocity, health: ?Health });
    defer q.deinit();
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

    var q = manager.query(struct { pos: Position });
    defer q.deinit();
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
    var q1 = manager.query(struct { pos: Position });
    defer q1.deinit();
    var count1: usize = 0;
    while (q1.next()) |_| {
        count1 += 1;
    }

    // Second iteration with new query
    var q2 = manager.query(struct { pos: Position });
    defer q2.deinit();
    var count2: usize = 0;
    while (q2.next()) |_| {
        count2 += 1;
    }

    try std.testing.expect(count1 == count2);
    try std.testing.expect(count1 == 5);
}

test "Query - component with pointer field" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Component that holds a pointer
    const ComponentWithPointer = struct {
        data: *i32,
        value: f32,
    };

    // Allocate some data on the heap
    var heap_value1: i32 = 42;
    var heap_value2: i32 = 100;
    var heap_value3: i32 = 256;

    // Create entities with components that hold pointers
    const comp1 = ComponentWithPointer{ .data = &heap_value1, .value = 1.0 };
    const comp2 = ComponentWithPointer{ .data = &heap_value2, .value = 2.0 };
    const comp3 = ComponentWithPointer{ .data = &heap_value3, .value = 3.0 };

    const e1 = manager.create(.{comp1});
    const e2 = manager.create(.{comp2});
    const e3 = manager.create(.{comp3});

    // Verify entities were created
    try std.testing.expect(manager.isAlive(e1));
    try std.testing.expect(manager.isAlive(e2));
    try std.testing.expect(manager.isAlive(e3));

    // Query for components with pointers
    var q = manager.query(struct { comp: ComponentWithPointer });
    defer q.deinit();
    var count: usize = 0;
    var sum: i32 = 0;
    var value_sum: f32 = 0.0;

    while (q.next()) |item| {
        // Dereference the pointer in the component
        const pointed_value = item.comp.data.*;
        sum += pointed_value;
        value_sum += item.comp.value;
        count += 1;

        // Verify the pointer is valid and points to expected values
        try std.testing.expect(pointed_value == 42 or pointed_value == 100 or pointed_value == 256);
    }

    try std.testing.expect(count == 3);
    try std.testing.expect(sum == 42 + 100 + 256);
    try std.testing.expect(value_sum == 1.0 + 2.0 + 3.0);

    // Test mutation through the pointer
    var q2 = manager.query(struct { comp: ComponentWithPointer });
    defer q2.deinit();
    while (q2.next()) |item| {
        item.comp.data.* += 1000;
    }

    // Verify the heap values were mutated
    try std.testing.expect(heap_value1 == 1042);
    try std.testing.expect(heap_value2 == 1100);
    try std.testing.expect(heap_value3 == 1256);
}

test "Query - component with slice field" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Component that holds a slice
    const ComponentWithSlice = struct {
        items: []const u8,
        count: usize,
    };

    // Create some string slices
    const str1 = "Hello";
    const str2 = "World";
    const str3 = "ECS";

    const comp1 = ComponentWithSlice{ .items = str1, .count = str1.len };
    const comp2 = ComponentWithSlice{ .items = str2, .count = str2.len };
    const comp3 = ComponentWithSlice{ .items = str3, .count = str3.len };

    _ = manager.create(.{comp1});
    _ = manager.create(.{comp2});
    _ = manager.create(.{comp3});

    // Query and verify slices are intact
    var q = manager.query(struct { comp: ComponentWithSlice });
    defer q.deinit();
    var count: usize = 0;
    var total_len: usize = 0;

    while (q.next()) |item| {
        try std.testing.expect(item.comp.items.len == item.comp.count);
        total_len += item.comp.items.len;
        count += 1;

        // Verify slice contents
        const valid = std.mem.eql(u8, item.comp.items, "Hello") or
            std.mem.eql(u8, item.comp.items, "World") or
            std.mem.eql(u8, item.comp.items, "ECS");
        try std.testing.expect(valid);
    }

    try std.testing.expect(count == 3);
    try std.testing.expect(total_len == str1.len + str2.len + str3.len);
}

test "Query - component with multiple pointer types" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Component with different pointer types
    const ComplexComponent = struct {
        int_ptr: *i32,
        float_ptr: *f32,
        bool_ptr: *bool,
        slice: []const u8,
    };

    var int_val: i32 = 123;
    var float_val: f32 = 45.67;
    var bool_val: bool = true;
    const str_val = "test";

    const comp = ComplexComponent{
        .int_ptr = &int_val,
        .float_ptr = &float_val,
        .bool_ptr = &bool_val,
        .slice = str_val,
    };

    _ = manager.create(.{comp});

    // Query and verify all pointer types work correctly
    var q = manager.query(struct { comp: ComplexComponent });
    defer q.deinit();
    var found = false;

    while (q.next()) |item| {
        try std.testing.expect(item.comp.int_ptr.* == 123);
        try std.testing.expect(item.comp.float_ptr.* == 45.67);
        try std.testing.expect(item.comp.bool_ptr.* == true);
        try std.testing.expect(std.mem.eql(u8, item.comp.slice, "test"));

        // Mutate through pointers
        item.comp.int_ptr.* = 999;
        item.comp.float_ptr.* = 12.34;
        item.comp.bool_ptr.* = false;

        found = true;
    }

    try std.testing.expect(found);
    try std.testing.expect(int_val == 999);
    try std.testing.expect(float_val == 12.34);
    try std.testing.expect(bool_val == false);
}

test "Query - hasNext" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    for (0..3) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0 };
        _ = manager.create(.{pos});
    }

    var q = manager.query(struct { pos: Position });
    defer q.deinit();
    var count: usize = 0;

    while (q.hasNext()) {
        const item = q.next().?;
        try std.testing.expect(item.pos.x >= 0.0);
        count += 1;
    }

    try std.testing.expect(count == 3);
}

// --- Custom query filter type tests ---

/// A custom filter: only match entities that have Health.
const HasHealth = struct {
    pub const QueryFilter = With(Health);
};

/// A custom filter: only match entities without Armor.
const NoArmor = struct {
    pub const QueryFilter = Without(Armor);
};

/// A custom filter combining multiple With/Without via a tuple payload.
const RequiresPhysics = struct {
    pub const QueryFilter = With(.{ Position, Velocity });
};

/// A custom filter using a struct to express multiple constraints.
const ActiveUnit = struct {
    pub const QueryFilter = struct {
        requires_health: With(Health),
        no_armor: Without(Armor),
    };
};

test "Query - custom filter type with With(T)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Entities with Position + Health
    for (0..4) |i| {
        _ = manager.create(.{ Position{ .x = @floatFromInt(i), .y = 0.0 }, Health{ .value = 100 } });
    }
    // Entities with Position only (no Health)
    for (0..3) |_| {
        _ = manager.create(.{Position{ .x = 99.0, .y = 0.0 }});
    }

    var q = manager.query(struct {
        pos: Position,
        filter: HasHealth,
    });
    defer q.deinit();
    comptime {
        if (@hasField(@TypeOf(q).IncludeTypesTupleType, "filter")) {
            @compileError("Custom filter types must not appear in query results.");
        }
    }
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x < 99.0);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "Query - custom filter type with Without(T)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Entities with Position + Health
    for (0..5) |_| {
        _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Health{ .value = 100 } });
    }
    // Entities with Position + Health + Armor
    for (0..3) |_| {
        _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Health{ .value = 100 }, Armor{ .defense = 10 } });
    }

    var q = manager.query(struct {
        pos: Position,
        filter: NoArmor,
    });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 1.0);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 5), count);
}

test "Query - custom filter with tuple payload (multiple requires)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Position + Velocity
    for (0..3) |_| {
        _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Velocity{ .dx = 1.0, .dy = 0.0 } });
    }
    // Position only
    for (0..4) |_| {
        _ = manager.create(.{Position{ .x = 2.0, .y = 0.0 }});
    }

    var q = manager.query(struct {
        physics: RequiresPhysics,
        health: ?Health,
    });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "Query - custom filter with struct return (multiple constraints)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Position + Health (matches: has Health, no Armor)
    for (0..4) |_| {
        _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Health{ .value = 50 } });
    }
    // Position + Health + Armor (excluded: has Armor)
    for (0..2) |_| {
        _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Health{ .value = 50 }, Armor{ .defense = 5 } });
    }
    // Position only (excluded: no Health)
    for (0..3) |_| {
        _ = manager.create(.{Position{ .x = 3.0, .y = 0.0 }});
    }

    var q = manager.query(struct {
        pos: Position,
        unit: ActiveUnit,
    });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 1.0);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "Query - multiple custom filters combined" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Position + Velocity + Health (matches all filters)
    for (0..3) |_| {
        _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Velocity{ .dx = 1.0, .dy = 0.0 }, Health{ .value = 100 } });
    }
    // Position + Velocity (missing Health)
    for (0..2) |_| {
        _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Velocity{ .dx = 1.0, .dy = 0.0 } });
    }
    // Position + Velocity + Health + Armor (has Armor, filtered out)
    for (0..2) |_| {
        _ = manager.create(.{ Position{ .x = 3.0, .y = 0.0 }, Velocity{ .dx = 1.0, .dy = 0.0 }, Health{ .value = 100 }, Armor{ .defense = 5 } });
    }

    // pos: Position is omitted here because RequiresPhysics already adds a require-Position
    // constraint via QueryFilter = With(.{Position, Velocity}).  Using Entity instead
    // avoids a duplicate-constraint compile error while still exercising multiple custom filters.
    var q = manager.query(struct {
        ent: Entity,
        physics: RequiresPhysics,
        alive: HasHealth,
        unarmored: NoArmor,
    });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "Query - custom filter combined with explicit With/Without" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Position + Health + Team (matches)
    for (0..3) |_| {
        _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Health{ .value = 100 }, Team{ .id = 1 } });
    }
    // Position + Health (no Team, excluded)
    for (0..4) |_| {
        _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Health{ .value = 100 } });
    }
    // Position + Health + Team + Armor (has Armor, excluded by NoArmor)
    for (0..2) |_| {
        _ = manager.create(.{ Position{ .x = 3.0, .y = 0.0 }, Health{ .value = 100 }, Team{ .id = 1 }, Armor{ .defense = 5 } });
    }

    var q = manager.query(struct {
        pos: Position,
        alive: HasHealth,
        has_team: With(Team),
        no_armor: Without(Armor),
    });
    defer q.deinit();
    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.pos.x == 1.0);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

// --- Custom query types with QueryResultType + query ---

/// A result-only custom type: yields the current entity from fetch context.
/// No QueryFilter — no constraints, just contributes a result field.
const CurrentEntity = struct {
    pub const QueryResultType = Entity;
    pub fn query(ctx: query_mod.QueryContext) Entity {
        return ctx.entity;
    }
};

/// A custom type that adds a constraint (require Health) AND contributes a result field
/// (the health value by copy), so it acts as both a filter and a fetcher.
const HealthValue = struct {
    pub const QueryFilter = With(Health);
    pub const QueryResultType = i32;
    pub fn query(ctx: query_mod.QueryContext) i32 {
        return ctx.get(Health).value;
    }
};

test "Query - custom type with QueryResultType only (no QueryFilter)" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    const e1 = manager.create(.{Position{ .x = 1.0, .y = 0.0 }});
    const e2 = manager.create(.{Position{ .x = 2.0, .y = 0.0 }});
    const e3 = manager.create(.{Position{ .x = 3.0, .y = 0.0 }});

    var q = manager.query(struct {
        pos: Position,
        ent: CurrentEntity,
    });
    defer q.deinit();

    var seen = std.AutoHashMap(u32, bool).init(std.testing.allocator);
    defer seen.deinit();

    while (q.next()) |item| {
        try seen.put(item.ent.id, true);
        _ = item.pos;
    }
    try std.testing.expectEqual(@as(usize, 3), seen.count());
    try std.testing.expect(seen.contains(e1.id));
    try std.testing.expect(seen.contains(e2.id));
    try std.testing.expect(seen.contains(e3.id));
}

test "Query - custom type with both QueryFilter and QueryResultType" {
    var manager = try Manager.init(std.testing.allocator);
    defer manager.deinit();

    // Entities with Health (matched)
    _ = manager.create(.{ Position{ .x = 1.0, .y = 0.0 }, Health{ .value = 42 } });
    _ = manager.create(.{ Position{ .x = 2.0, .y = 0.0 }, Health{ .value = 99 } });
    // Entities without Health (filtered out by QueryFilter = With(Health))
    _ = manager.create(.{Position{ .x = 3.0, .y = 0.0 }});
    _ = manager.create(.{Position{ .x = 4.0, .y = 0.0 }});

    var q = manager.query(struct {
        pos: Position,
        hp: HealthValue,
    });
    defer q.deinit();

    var count: usize = 0;
    while (q.next()) |item| {
        try std.testing.expect(item.hp == 42 or item.hp == 99);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
}
