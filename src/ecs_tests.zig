const std = @import("std");
const ecs_mod = @import("ecs.zig");
const Manager = ecs_mod.Manager;
const Entity = ecs_mod.Entity;
const scheduler_mod = @import("scheduler.zig");
const relations = @import("relations.zig");
const params = @import("systems.params.zig");
const registry = @import("systems.registry.zig");
const Query = @import("query.zig").Query;

fn pointerSystem(query: Query(struct { pcA: ?PointerComp, pcB: ?PointerCompToPointerComp })) void {
    while (query.next()) |item| {
        // Modify the pointed value to demonstrate components may contain pointers to externally-managed memory
        if (item.pcA) |pcA| {
            pcA.ptr.* = 100;
            continue;
        }
        if (item.pcB) |pcB| {
            pcB.ptr.ptr.* = 100;
        }
    }
}

// Test components
const Position = packed struct {
    x: f32,
    y: f32,
};

const Velocity = packed struct {
    x: f32,
    y: f32,
};

const Health = struct {
    current: i32,
    max: i32,
};

const Name = struct {
    value: []const u8,
};

const PointerComp = struct {
    ptr: *u8,
};

const PointerCompToPointerComp = struct {
    ptr: *PointerComp,
};

// Test resource
const GameConfig = packed struct {
    difficulty: u8,
    max_players: u32,
};

test "Manager - createEmpty entity" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .x = 1.0, .y = 2.0 };

    const entity = manager.create(.{ pos, vel });

    try std.testing.expect(entity.id == 0);
    try std.testing.expect(manager.count() == 1);
    try std.testing.expect(manager.isAlive(entity));
}

test "Manager - create multiple entities" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 5.0, .y = 10.0 };
    const vel = Velocity{ .x = 0.5, .y = -0.5 };

    const entities = try manager.createBatch(std.testing.allocator, 1000, .{ pos, vel });
    defer std.testing.allocator.free(entities);

    try std.testing.expect(entities.len == 1000);
    try std.testing.expect(manager.count() == 1000);

    for (entities) |e| {
        try std.testing.expect(manager.isAlive(e));
    }
}

test "Manager - isAlive with valid entity" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const entity = manager.createEmpty();
    try std.testing.expect(manager.isAlive(entity));
}

test "Manager - isAlive with invalid entity" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const fake_entity = Entity{ .id = 999, .generation = 0 };
    try std.testing.expect(!manager.isAlive(fake_entity));
}

test "Manager - addComponent to entity" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const fake_entity = Entity{ .id = 999, .generation = 0 };
    const pos = Position{ .x = 0.0, .y = 0.0 };

    const result = manager.addComponent(fake_entity, Position, pos);
    try std.testing.expectError(error.EntityNotAlive, result);
}

test "Manager - getComponent returns component" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 100.0, .y = 200.0 };
    const entity = manager.create(.{pos});

    const retrieved = try manager.getComponent(entity, Position);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.x == 100.0);
    try std.testing.expect(retrieved.?.y == 200.0);
}

test "Manager - getComponent mutability" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const entity = manager.create(.{pos});

    const vel = try manager.getComponent(entity, Velocity);
    try std.testing.expect(vel == null);
}

test "Manager - hasComponent returns true when present" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    const has_pos = try manager.hasComponent(entity, Position);
    try std.testing.expect(has_pos);
}

test "Manager - hasComponent returns false when absent" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    const has_vel = try manager.hasComponent(entity, Velocity);
    try std.testing.expect(!has_vel);
}

test "Manager - removeComponent" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .x = 1.0, .y = 1.0 };
    const entity = manager.create(.{ pos, vel });

    try std.testing.expect(try manager.hasComponent(entity, Velocity));

    try manager.removeComponent(entity, Velocity);

    try std.testing.expect(!try manager.hasComponent(entity, Velocity));
    try std.testing.expect(try manager.hasComponent(entity, Position));
}

test "Manager - addComponent panics for Relation types" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const entity = manager.createEmpty();

    // This should panic because Relation components must be added via RelationManager
    const relation_value = relations.Relation(relations.Child){ .target = entity, .data = relations.Child{} };
    _ = relation_value; // comment this out to test
    //try manager.addComponent(entity, relations.Relation(relations.Child), relation_value);
}

test "Manager - removeComponent panics for Relation types" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const entity = manager.createEmpty();
    _ = entity; // comment this out to test
    // This should panic because Relation components must be removed via RelationManager
    // try manager.removeComponent(entity, relations.Relation(relations.Child));
}

test "Manager - getAllComponents" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 5.0, .y = 10.0 };
    const vel = Velocity{ .x = 2.0, .y = 3.0 };
    const health = Health{ .current = 100, .max = 100 };

    const entity = manager.create(.{ pos, vel, health });

    const components = try manager.getAllComponents(std.testing.allocator, entity);
    defer std.testing.allocator.free(components);

    try std.testing.expect(components.len == 3);
}

test "Manager - addResource" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 5, .max_players = 10 };
    try manager.addResourceRetained(GameConfig, config);

    var res_ref = manager.getResource(GameConfig).?;
    defer res_ref.deinit();
    var res_guard = res_ref.lockRead();
    defer res_guard.deinit();
    try std.testing.expect(res_guard.get().difficulty == 5);
    try std.testing.expect(res_guard.get().max_players == 10);
}

test "Manager - addResourceRef with ArcRwLock Ref" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 9, .max_players = 99 };
    const resource_ref = try @import("zevy_mem").pointers.ArcRwLock(GameConfig).init(std.testing.allocator, config);
    defer resource_ref.deinit();

    // Ownership of this Ref is transferred to the manager.
    try manager.addResourceRef(GameConfig, resource_ref.clone());

    var retrieved_ref = manager.getResource(GameConfig).?;
    defer retrieved_ref.deinit();
    var retrieved_guard = retrieved_ref.lockRead();
    defer retrieved_guard.deinit();

    try std.testing.expect(retrieved_guard.get().difficulty == 9);
    try std.testing.expect(retrieved_guard.get().max_players == 99);
}

test "Manager - getResource returns resource" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 7, .max_players = 15 };
    try manager.addResourceRetained(GameConfig, config);

    const retrieved = manager.getResource(GameConfig);
    try std.testing.expect(retrieved != null);
    defer retrieved.?.deinit();
    var retrieved_ref = manager.getResource(GameConfig).?;
    defer retrieved_ref.deinit();
    var retrieved_guard = retrieved_ref.lockRead();
    defer retrieved_guard.deinit();
    try std.testing.expect(retrieved_guard.get().difficulty == 7);
    try std.testing.expect(retrieved_guard.get().max_players == 15);
}

test "Manager - getResource returns null for missing resource" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const retrieved = manager.getResource(GameConfig);
    try std.testing.expect(retrieved == null);
}

test "Manager - hasResource" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    try std.testing.expect(!manager.hasResource(GameConfig));

    const config = GameConfig{ .difficulty = 3, .max_players = 5 };
    try manager.addResourceRetained(GameConfig, config);

    try std.testing.expect(manager.hasResource(GameConfig));
}

test "Manager - removeResource" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 4, .max_players = 8 };
    const config_ptr = try manager.addResource(GameConfig, config);
    defer config_ptr.deinit();
    try std.testing.expect(manager.hasResource(GameConfig));

    manager.removeResource(GameConfig);

    try std.testing.expect(!manager.hasResource(GameConfig));
    try std.testing.expectEqual(1, config_ptr.strongCount());
    config_ptr.deinit();
}

test "Manager - listResourceTypeHashes" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 1, .max_players = 4 };
    try manager.addResourceRetained(GameConfig, config);

    const score: i32 = 1000;
    try manager.addResourceRetained(i32, score);

    var types = manager.listResourceTypeHashes(std.testing.allocator);
    defer types.deinit(std.testing.allocator);

    try std.testing.expect(types.items.len == 3);
}

test "Manager - query basic" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos1 = Position{ .x = 1.0, .y = 2.0 };
    const pos2 = Position{ .x = 3.0, .y = 4.0 };
    _ = manager.create(.{pos1});
    _ = manager.create(.{pos2});

    var query = manager.query(struct { pos: Position });
    defer query.deinit();
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 10.0, .y = 20.0 };
    const vel = Velocity{ .x = 5.0, .y = -5.0 };
    const health = Health{ .current = 50, .max = 100 };

    const entity = manager.create(.{ pos, vel, health });

    try std.testing.expect(try manager.hasComponent(entity, Position));
    try std.testing.expect(try manager.hasComponent(entity, Velocity));
    try std.testing.expect(try manager.hasComponent(entity, Health));
}

test "Manager - component migration when adding to existing entity" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const entity = manager.create(.{pos});

    try std.testing.expect(try manager.hasComponent(entity, Position));
    try std.testing.expect(!try manager.hasComponent(entity, Velocity));

    const vel = Velocity{ .x = 3.0, .y = 4.0 };
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
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
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const config = GameConfig{ .difficulty = 1, .max_players = 2 };
    try manager.addResourceRetained(GameConfig, config);

    // Mutate through write guard
    var res_ref = manager.getResource(GameConfig).?;
    defer res_ref.deinit();
    var res_guard = res_ref.lockWrite();
    res_guard.get().difficulty = 10;
    res_guard.get().max_players = 20;
    res_guard.deinit();

    // Get resource again and verify mutation
    var retrieved_ref = manager.getResource(GameConfig).?;
    defer retrieved_ref.deinit();
    var retrieved_guard = retrieved_ref.lockRead();
    defer retrieved_guard.deinit();
    try std.testing.expect(retrieved_guard.get().difficulty == 10);
    try std.testing.expect(retrieved_guard.get().max_players == 20);
}

test "Manager - component with pointer field" {
    var manager = try Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    // Allocate a byte on the test allocator and store its pointer in the component
    const ptr = try manager.allocator().create(u8);
    ptr.* = 42;

    const pointer_comp = PointerComp{ .ptr = ptr };
    const entity = manager.create(.{pointer_comp});

    // Run a system that modifies the pointed value
    const sys = manager.createSystem(pointerSystem);
    try sys.run(&manager, sys.ctx);

    const retrieved = try manager.getComponent(entity, PointerComp);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.ptr.* == 100);

    // Clean up externally-managed memory
    manager.allocator().destroy(ptr);
}

test "Manager - component with pointer to another component" {
    const zevy_mem = @import("zevy_mem");
    var debug_allocator = zevy_mem.allocators.DebugAllocator.init(std.testing.allocator);
    defer {
        if (debug_allocator.detectLeaks()) {
            debug_allocator.dumpLeaks();
            @panic("Memory leaks detected");
        }
        debug_allocator.deinit();
    }
    var manager = try Manager.init(debug_allocator.allocator(), std.testing.io);
    defer manager.deinit();

    // Allocate a byte on the test allocator and store its pointer in the first component
    const ptr = try manager.allocator().create(u8);
    ptr.* = 42;

    var pointer_comp = PointerComp{ .ptr = ptr };
    const entity = manager.create(.{pointer_comp});

    const pointer_to_pointer_comp = PointerCompToPointerComp{ .ptr = &pointer_comp };
    try manager.addComponent(entity, PointerCompToPointerComp, pointer_to_pointer_comp);

    // Run a system that modifies the pointed value
    const sys = manager.createSystem(pointerSystem);
    try sys.run(&manager, sys.ctx);

    const retrieved = try manager.getComponent(entity, PointerCompToPointerComp);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.ptr.ptr.* == 100);
    try std.testing.expect(pointer_comp.ptr.* == 100);

    try manager.removeComponent(entity, PointerCompToPointerComp);

    try std.testing.expect(pointer_comp.ptr.* == 100);
    try std.testing.expect(retrieved.?.ptr.ptr.* == 100);
    // Clean up externally-managed memory
    manager.allocator().destroy(ptr);
}

test "Query with just Entity" {
    var ecs_instance = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs_instance.deinit();
    const amount = 100;
    for (0..amount) |_| {
        _ = ecs_instance.createEmpty();
    }

    var query = ecs_instance.query(struct { entity: Entity });
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
    try std.testing.expect(count == amount);
}

test "Create entity using create() with null or empty" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();
    const amount = 100;
    for (0..amount) |_| {
        _ = ecs.create(null);
        _ = ecs.create(.{});
    }

    var query = ecs.query(struct { entity: Entity });
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
    try std.testing.expect(count == amount * 2);
}

// Focused test to exercise migration/remove and check archetype invariants
test "World migration and archetype invariants" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();

    const A = struct { a: u32 };
    const B = struct { b: u64 };
    const C = struct { c: u32 };

    // Create entities with different component sets
    const e1 = ecs.create(.{ A{ .a = 1 }, B{ .b = 2 } });
    const e2 = ecs.create(.{ B{ .b = 3 }, C{ .c = 4 } });

    // Sanity: verify getAllComponents
    const comps1 = try ecs.getAllComponents(std.testing.allocator, e1);
    defer std.testing.allocator.free(comps1);
    try std.testing.expect(comps1.len == 2);

    const comps2 = try ecs.getAllComponents(std.testing.allocator, e2);
    defer std.testing.allocator.free(comps2);
    try std.testing.expect(comps2.len == 2);

    // Remove component A from e1, force migration
    try ecs.removeComponent(e1, A);

    // Now validate archetype invariants: for each archetype, arr_len == entities_count * comp_size
    var storage_guard = ecs.world().archetypes.readGuard();
    defer storage_guard.deinit();
    var it = storage_guard.get().archetypes.valueIterator();
    while (it.next()) |a_ptr| {
        const a = a_ptr.*;
        const ent_count = a.entities.items.len;
        var i: usize = 0;
        while (i < a.component_sizes.len) : (i += 1) {
            const comp_size = a.component_sizes[i];
            const arr_len = a.component_arrays[i].items.len;
            try std.testing.expect(arr_len == ent_count * comp_size);
            // Also ensure comp_size > 0
            try std.testing.expect(comp_size > 0);
        }
        // For each entity in archetype, check that getAllComponents succeeds and matches counts
        var k: usize = 0;
        while (k < ent_count) : (k += 1) {
            const ent = a.entities.items[k];
            const cl = try ecs.getAllComponents(std.testing.allocator, ent);
            defer std.testing.allocator.free(cl);
            try std.testing.expect(cl.len >= 1);
        }
    }
}

test "removeSystem removes cached system" {
    var ecs = try Manager.init(std.testing.allocator, std.testing.io);
    defer ecs.deinit();

    // Create a test resource to verify system execution
    const TestCounter = struct { count: u32 };
    try ecs.addResourceRetained(TestCounter, .{ .count = 0 });

    // Define a test system that increments the counter
    const test_system = struct {
        pub fn run(res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    // Cache the system
    const handle = ecs.cacheSystem(ecs.createSystem(test_system));

    // Verify the system is cached and runs
    try std.testing.expect(ecs.systems().count() == 1);
    _ = try ecs.runSystem(handle);
    const ctr_ref = ecs.getResource(TestCounter).?;
    defer ctr_ref.deinit();
    var ctr_guard = ctr_ref.lockRead();
    defer ctr_guard.deinit();
    try std.testing.expect(ctr_guard.get().count == 1);

    // Remove the system
    ecs.removeSystem(handle);

    // Verify the system is removed from cache
    try std.testing.expect(ecs.systems().count() == 0);

    // Verify running the removed system returns error
    const result = ecs.runSystem(handle);
    try std.testing.expectError(error.InvalidSystemHandle, result);
}

test "removeSystem with same function cached twice returns same handle" {
    var ecs = try Manager.init(std.testing.allocator, std.testing.io);
    defer ecs.deinit();

    const TestCounter = struct { count: u32 };
    try ecs.addResourceRetained(TestCounter, .{ .count = 0 });

    const test_system = struct {
        pub fn run(_: *Manager, res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    // Cache the same system twice - should return the same handle
    const handle1 = ecs.cacheSystem(ecs.createSystem(test_system));
    const handle2 = ecs.cacheSystem(ecs.createSystem(test_system));

    // Verify they are the same handle
    try std.testing.expect(handle1.handle == handle2.handle);
    // Verify only one system is cached
    try std.testing.expect(ecs.systems().count() == 1);

    // Remove the system once
    ecs.removeSystem(handle1);

    // Verify the system is removed
    try std.testing.expect(ecs.systems().count() == 0);

    // Verify both handles now return error
    try std.testing.expectError(error.InvalidSystemHandle, ecs.runSystem(handle1));
    try std.testing.expectError(error.InvalidSystemHandle, ecs.runSystem(handle2));
}

test "Entity destruction and reuse" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();

    const entity1 = ecs.createEmpty();
    const entity2 = ecs.createEmpty();

    try std.testing.expect(ecs.isAlive(entity1));
    try std.testing.expect(ecs.isAlive(entity2));

    try ecs.destroy(entity1);
    try std.testing.expect(!ecs.isAlive(entity1));
    try std.testing.expect(ecs.isAlive(entity2));

    const entity3 = ecs.createEmpty();
    try std.testing.expect(entity3.id == entity1.id); // ID should be reused
    try std.testing.expect(entity3.generation != entity1.generation); // Generation should be incremented

    try std.testing.expect(ecs.isAlive(entity3));
    try std.testing.expect(ecs.isAlive(entity2));
}

test "copyEntityFrom copies components between managers" {
    var ecs_src = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs_src.deinit();

    var ecs_dst = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs_dst.deinit();

    const e_src = ecs_src.create(.{ Position{ .x = 1, .y = 2 }, Velocity{ .x = 3, .y = 4 } });

    const e_dst = ecs_dst.copyEntityFrom(std.testing.allocator, &ecs_src, e_src) catch unreachable;

    const pos_src = ecs_src.getComponent(e_src, Position) catch unreachable;
    const vel_src = ecs_src.getComponent(e_src, Velocity) catch unreachable;
    const pos_dst = ecs_dst.getComponent(e_dst, Position) catch unreachable;
    const vel_dst = ecs_dst.getComponent(e_dst, Velocity) catch unreachable;

    try std.testing.expect(pos_src != null and vel_src != null);
    try std.testing.expect(pos_dst != null and vel_dst != null);
    try std.testing.expectEqual(pos_src.?.x, pos_dst.?.x);
    try std.testing.expectEqual(pos_src.?.y, pos_dst.?.y);
    try std.testing.expectEqual(vel_src.?.x, vel_dst.?.x);
    try std.testing.expectEqual(vel_src.?.y, vel_dst.?.y);
}

test "moveEntityTo moves components and destroys source" {
    var ecs_src = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs_src.deinit();

    var ecs_dst = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs_dst.deinit();

    const e_src = ecs_src.create(.{Position{ .x = 10, .y = 20 }});

    const e_dst = ecs_src.moveEntityTo(std.testing.allocator, &ecs_dst, e_src) catch unreachable;

    try std.testing.expect(!ecs_src.isAlive(e_src));
    try std.testing.expect(ecs_dst.isAlive(e_dst));

    const pos_dst = ecs_dst.getComponent(e_dst, Position) catch unreachable;
    try std.testing.expect(pos_dst != null);
    try std.testing.expectEqual(@as(f32, 10), pos_dst.?.x);
    try std.testing.expectEqual(@as(f32, 20), pos_dst.?.y);
}

test "copyEntityFrom same manager duplicates components" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();

    const source = ecs.create(.{ Position{ .x = 7, .y = 9 }, Velocity{ .x = 1, .y = 2 } });
    const duplicate = ecs.copyEntityFrom(std.testing.allocator, &ecs, source) catch unreachable;

    try std.testing.expect(ecs.isAlive(source));
    try std.testing.expect(ecs.isAlive(duplicate));
    try std.testing.expect(source.id != duplicate.id);

    const src_pos = ecs.getComponent(source, Position) catch unreachable;
    const dup_pos = ecs.getComponent(duplicate, Position) catch unreachable;
    const src_vel = ecs.getComponent(source, Velocity) catch unreachable;
    const dup_vel = ecs.getComponent(duplicate, Velocity) catch unreachable;

    try std.testing.expect(src_pos != null and dup_pos != null);
    try std.testing.expect(src_vel != null and dup_vel != null);
    try std.testing.expectEqual(src_pos.?.x, dup_pos.?.x);
    try std.testing.expectEqual(src_pos.?.y, dup_pos.?.y);
    try std.testing.expectEqual(src_vel.?.x, dup_vel.?.x);
    try std.testing.expectEqual(src_vel.?.y, dup_vel.?.y);
}

test "getOrAddResource" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();

    const MyResource = struct {
        value: u32,
    };

    const res = ecs.getOrAddResource(MyResource, MyResource{ .value = 32 }, null) catch unreachable;
    res.deinit();

    try std.testing.expect(ecs.hasResource(MyResource));
}

test "addResource keeps manager-owned reference" {
    var ecs = try Manager.init(std.testing.allocator, std.testing.io);
    defer ecs.deinit();

    const res = try ecs.addResource(u32, 42);
    try std.testing.expectEqual(@as(usize, 2), res.strongCount());
    res.deinit();

    const again = ecs.getResource(u32) orelse return error.ResourceNotFound;
    defer again.deinit();

    try std.testing.expectEqual(@as(usize, 2), again.strongCount());
    var guard = again.lockRead();
    defer guard.deinit();
    try std.testing.expectEqual(@as(u32, 42), guard.get().*);
}

test "Manager-owned scheduler survives repeated access" {
    var ecs = try Manager.init(std.testing.allocator, std.testing.io);
    defer ecs.deinit();

    const TestEvent = struct { value: u32 };
    const Counter = struct { value: u32 };

    const first = ecs.scheduler();
    try first.registerEvent(&ecs, TestEvent);

    try ecs.addResourceRetained(Counter, .{ .value = 0 });

    const second = ecs.scheduler();

    const increment = struct {
        fn run(counter: params.ResMut(Counter)) void {
            counter.get().value += 1;
        }
    }.run;

    second.addSystem(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.Update), increment);
    _ = second.runStage(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.Update));

    const counter_ref = ecs.getResource(Counter) orelse return error.ResourceNotFound;
    defer counter_ref.deinit();
    var counter_guard = counter_ref.lockRead();
    defer counter_guard.deinit();
    try std.testing.expectEqual(@as(u32, 1), counter_guard.get().value);
}

// Stress test to try to surface migration/invariant issues
test "World randomized churn stress test" {
    var ecs = Manager.init(std.testing.allocator, std.testing.io) catch unreachable;
    defer ecs.deinit();

    const A = struct { a: u32 };
    const B = struct { b: u64 };
    const C = struct { c: u32 };

    var rng = std.Random.DefaultPrng.init(1234);
    var rand = rng.random();
    const N: usize = 200;
    var entities = try std.ArrayList(Entity).initCapacity(std.testing.allocator, N);
    defer entities.deinit(std.testing.allocator);

    // Create initial entities with random component sets
    for (0..N) |_| {
        const v = rand.intRangeAtMost(i32, 0, 4);
        const ent = switch (v) {
            0 => ecs.create(.{A{ .a = 1 }}),
            1 => ecs.create(.{B{ .b = 2 }}),
            2 => ecs.create(.{ A{ .a = 1 }, B{ .b = 2 } }),
            else => ecs.create(.{C{ .c = 3 }}),
        };
        try entities.append(std.testing.allocator, ent);
    }

    const OPS: usize = 2000;
    var i: usize = 0;
    while (i < OPS) : (i += 1) {
        const idx = rand.uintLessThan(usize, entities.items.len);
        const ent = entities.items[idx];
        const op = rand.uintLessThan(usize, 4);
        switch (op) {
            0 => _ = ecs.addComponent(ent, A, A{ .a = 5 }) catch {},
            1 => _ = ecs.addComponent(ent, B, B{ .b = 6 }) catch {},
            2 => _ = ecs.addComponent(ent, C, C{ .c = 7 }) catch {},
            3 => {
                // Randomly remove components
                _ = ecs.removeComponent(ent, A) catch {};
                _ = ecs.removeComponent(ent, B) catch {};
                _ = ecs.removeComponent(ent, C) catch {};
            },
            else => {},
        }

        // Occasionally validate invariants
        if ((i % 50) == 0) {
            var storage_guard = ecs.world().archetypes.readGuard();
            defer storage_guard.deinit();
            var it = storage_guard.get().archetypes.valueIterator();
            while (it.next()) |a_ptr| {
                const a = a_ptr.*;
                const ent_count = a.entities.items.len;
                var j: usize = 0;
                while (j < a.component_sizes.len) : (j += 1) {
                    const comp_size = a.component_sizes[j];
                    const arr_len = a.component_arrays[j].items.len;
                    try std.testing.expect(arr_len == ent_count * comp_size);
                }
            }
        }
    }
}
