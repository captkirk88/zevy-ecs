const std = @import("std");
const benchmark = @import("benchmark.zig");
const Benchmark = benchmark.Benchmark;
const root = @import("root.zig");
const ecs = @import("ecs.zig");
const Manager = ecs.Manager;
const Entity = ecs.Entity;
const Commands = root.Commands;
const Query = root.Query;
const relations = @import("relations.zig");
const RelationManager = relations.RelationManager;
const Child = relations.Child;
const Owns = relations.Owns;

// Test components
const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
    dz: f32,
};

const Health = struct {
    current: u32,
    max: u32,
};

const Armor = struct {
    value: u32,
};

const Damage = struct {
    value: u32,
};

const Team = struct {
    id: u8,
};

const Target = struct {
    entity_id: u32,
};

// Query types
const MovementQueryInclude = struct { pos: Position, vel: Velocity };
const DamageNoArmorQueryInclude = struct { health: Health, damage: Damage };
const DamageNoArmorQueryExclude = struct { armor: Armor };
const TeamCollisionQueryInclude = struct { pos: Position, team: Team };
const TargetTrackingQueryInclude = struct { pos: Position, target: Target };
const VelocityDampingQueryInclude = struct { vel: Velocity };

const BENCH_OPT_COUNT = 3;

// Benchmark 1: Entity Creation Performance
fn benchCreateEntities(manager: *Manager, count: usize) void {
    for (0..count) |i| {
        const pos = Position{
            .x = @floatFromInt(i),
            .y = 0.0,
            .z = 0.0,
        };
        const vel = Velocity{ .dx = 1.0, .dy = 0.5, .dz = -0.5 };
        const health = Health{ .current = 100, .max = 100 };
        _ = manager.create(.{ pos, vel, health });
    }
}

fn batchCreateEntities(manager: *Manager, count: usize, allocator: std.mem.Allocator) void {
    // Create all entities in a single batch call
    const pos = Position{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const vel = Velocity{ .dx = 1.0, .dy = 0.5, .dz = -0.5 };
    const health = Health{ .current = 100, .max = 100 };
    const ents = manager.createBatch(allocator, count, .{ pos, vel, health }) catch |err| {
        std.debug.panic("Failed to create batch entities: {}\n", .{err});
    };
    allocator.free(ents);
}

// Benchmark 2: Mixed System Operations
// System 1: Movement - Update positions based on velocity
fn systemMovement(query: Query(MovementQueryInclude, .{})) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const vel: *Velocity = item.vel;
        pos.x += vel.dx;
        pos.y += vel.dy;
        pos.z += vel.dz;
    }
}

// System 2: Health Regeneration - Regenerate health over time
fn systemHealthRegen(query: Query(.{Health}, .{})) void {
    while (query.next()) |item| {
        const health: *Health = item[0];
        if (health.current < health.max) {
            health.current = @min(health.current + 1, health.max);
        }
    }
}

// System 3: Damage Application - Apply damage to entities with armor
fn systemDamageWithArmor(query: Query(.{ Health, Damage, Armor }, struct {})) void {
    while (query.next()) |item| {
        const health: *Health = item[0];
        const armor: *Armor = item[2];
        const damage: *Damage = item[1];
        const actual_damage = if (damage.value > armor.value) damage.value - armor.value else 0;
        if (health.current > actual_damage) {
            health.current -= actual_damage;
        } else {
            health.current = 0;
        }
    }
}

// System 4: Damage Application - Apply damage to entities without armor
fn systemDamageNoArmor(query: Query(DamageNoArmorQueryInclude, DamageNoArmorQueryExclude)) void {
    while (query.next()) |item| {
        const health: *Health = item.health;
        const damage: *Damage = item.damage;
        if (health.current > damage.value) {
            health.current -= damage.value;
        } else {
            health.current = 0;
        }
    }
}

// System 5: Team Collision - Check collisions within same team

// System 5: Team Collision - Check collisions within same team
fn systemTeamCollision(query: Query(TeamCollisionQueryInclude, .{})) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const team: *Team = item.team;
        // Simple distance calculation
        const dist_sq = pos.x * pos.x + pos.y * pos.y + pos.z * pos.z;
        std.mem.doNotOptimizeAway(dist_sq);
        std.mem.doNotOptimizeAway(team);
    }
}

// System 6: Target Tracking - Update target positions
fn systemTargetTracking(query: Query(TargetTrackingQueryInclude, .{})) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const target: *Target = item.target;
        // Simulate tracking calculation
        const dx = @as(f32, @floatFromInt(target.entity_id)) - pos.x;
        const dy = 0.0 - pos.y;
        std.mem.doNotOptimizeAway(dx);
        std.mem.doNotOptimizeAway(dy);
    }
}

// System 7: Velocity Damping - Apply friction/damping to velocity
fn systemVelocityDamping(query: Query(VelocityDampingQueryInclude, .{})) void {
    while (query.next()) |item| {
        const vel: *Velocity = item.vel;
        vel.dx *= 0.99;
        vel.dy *= 0.99;
        vel.dz *= 0.99;
    }
}

// Setup function to create diverse entity archetypes
fn setupMixedEntities(manager: *Manager, count: usize) void {
    for (0..count) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0, .z = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 0.5, .dz = -0.5 };
        const health = Health{ .current = 100, .max = 100 };

        // Create different archetypes based on index
        const archetype = i % 7;
        if (archetype == 0) {
            // Basic: Position, Velocity, Health
            _ = manager.create(.{ pos, vel, health });
        } else if (archetype == 1) {
            // With Armor
            const armor = Armor{ .value = 10 };
            _ = manager.create(.{ pos, vel, health, armor });
        } else if (archetype == 2) {
            // With Damage
            const damage = Damage{ .value = 5 };
            _ = manager.create(.{ pos, vel, health, damage });
        } else if (archetype == 3) {
            // With Armor and Damage
            const armor = Armor{ .value = 10 };
            const damage = Damage{ .value = 5 };
            _ = manager.create(.{ pos, vel, health, armor, damage });
        } else if (archetype == 4) {
            // With Team
            const team = Team{ .id = @intCast(i % 4) };
            _ = manager.create(.{ pos, vel, health, team });
        } else if (archetype == 5) {
            // With Target
            const target = Target{ .entity_id = @intCast(i / 2) };
            _ = manager.create(.{ pos, vel, health, target });
        } else {
            // With Team and Target
            const team = Team{ .id = @intCast(i % 4) };
            const target = Target{ .entity_id = @intCast(i / 2) };
            _ = manager.create(.{ pos, vel, health, team, target });
        }
    }
}

test "ECS Benchmark - Entity Creation" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeaderWithTitle("Creation");
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Create {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, BENCH_OPT_COUNT, benchCreateEntities, .{ &manager, count });
        Benchmark.printResult(result, .markdown);
    }

    std.debug.print("\n", .{});
}

test "ECS Benchmark - Batch Entity Creation" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeaderWithTitle("Batch Creation");
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Create {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, BENCH_OPT_COUNT, batchCreateEntities, .{ &manager, count, allocator });
        Benchmark.printResult(result, .markdown);
    }

    std.debug.print("\n", .{});
}

test "ECS Benchmark - Mixed Systems" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeaderWithTitle("Mixed Systems");
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        // Setup entities
        setupMixedEntities(&manager, count);
        const systems = setupMixedSystems(&manager);

        const label = try std.fmt.allocPrint(allocator, "Run 7 Systems on {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, BENCH_OPT_COUNT, benchMixedSystems, .{ &manager, &systems });

        Benchmark.printResult(result, .markdown);
    }

    std.debug.print("\n", .{});
}

fn setupMixedSystems(e: *Manager) [7]root.UntypedSystemHandle {
    const DefaultRegistry = @import("root.zig").DefaultParamRegistry;
    var results: [7]root.UntypedSystemHandle = undefined;
    results[0] = e.createSystemCached(systemMovement, DefaultRegistry).eraseType();
    results[1] = e.createSystemCached(systemHealthRegen, DefaultRegistry).eraseType();
    results[2] = e.createSystemCached(systemDamageWithArmor, DefaultRegistry).eraseType();
    results[3] = e.createSystemCached(systemDamageNoArmor, DefaultRegistry).eraseType();
    results[4] = e.createSystemCached(systemTeamCollision, DefaultRegistry).eraseType();
    results[5] = e.createSystemCached(systemTargetTracking, DefaultRegistry).eraseType();
    results[6] = e.createSystemCached(systemVelocityDamping, DefaultRegistry).eraseType();
    return results;
}

fn benchMixedSystems(e: *Manager, systems: *const [7]root.UntypedSystemHandle) void {
    for (systems) |sys_id| {
        _ = e.runSystemUntyped(void, sys_id) catch |err| {
            std.debug.print("Error running system {d}: {s}\n", .{ sys_id, @errorName(err) });
            break;
        };
    }
}

// Relation Benchmarks

// Realistic scenario: Scene graph with transform hierarchy
// Each entity has a transform that's relative to its parent
const Transform = struct {
    local_x: f32,
    local_y: f32,
    local_z: f32,
    world_x: f32 = 0,
    world_y: f32 = 0,
    world_z: f32 = 0,
};

// Setup hierarchical scene graph (game objects with parent-child relationships)
fn setupSceneGraph(manager: *Manager, rel: *root.Relations, count: usize) !std.ArrayList(Entity) {
    const allocator = manager.allocator;
    var all_entities = try std.ArrayList(Entity).initCapacity(allocator, count);

    // Create root scene node
    const root_entity = manager.create(.{Transform{ .local_x = 0, .local_y = 0, .local_z = 0 }});
    all_entities.append(allocator, root_entity) catch {};

    // Create a realistic scene hierarchy:
    // - Root (world)
    //   - Level objects (~10% of entities)
    //     - Props and decorations (~30% of entities)
    //   - Characters (~20% of entities)
    //     - Body parts/attachments (~40% of entities)

    const level_count = count / 10;
    const character_count = count / 5;

    var level_objects = try std.ArrayList(Entity).initCapacity(allocator, level_count);
    defer level_objects.deinit(allocator);

    // Create level objects under root
    for (0..level_count) |i| {
        const level_obj = manager.create(.{Transform{ .local_x = @as(f32, @floatFromInt(i)) * 10, .local_y = 0, .local_z = 0 }});
        try rel.add(manager, level_obj, root_entity, Child);
        level_objects.append(allocator, level_obj) catch {};
        all_entities.append(allocator, level_obj) catch {};

        // Add 3 props per level object
        for (0..3) |j| {
            if (all_entities.items.len >= count) break;
            const prop = manager.create(.{Transform{ .local_x = @as(f32, @floatFromInt(j)), .local_y = 1, .local_z = 0 }});
            try rel.add(manager, prop, level_obj, Child);
            all_entities.append(allocator, prop) catch {};
        }
    }

    // Create characters under root
    for (0..character_count) |i| {
        if (all_entities.items.len >= count) break;
        const character = manager.create(.{Transform{ .local_x = @as(f32, @floatFromInt(i)), .local_y = 0, .local_z = @as(f32, @floatFromInt(i)) * 2 }});
        try rel.add(manager, character, root_entity, Child);
        all_entities.append(allocator, character) catch {};

        // Add body parts (head, left_arm, right_arm, weapon)
        const body_parts = [_][]const u8{ "head", "left_arm", "right_arm", "weapon" };
        for (body_parts, 0..) |_, j| {
            if (all_entities.items.len >= count) break;
            const part = manager.create(.{Transform{ .local_x = 0, .local_y = @as(f32, @floatFromInt(j)), .local_z = 0 }});
            try rel.add(manager, part, character, Child);
            all_entities.append(allocator, part) catch {};
        }
    }

    return all_entities;
}

// System: Update world transforms based on parent hierarchy using ECS Query
fn systemUpdateTransforms(
    commands: *Commands,
    rel: *root.Relations,
    query: Query(.{ Transform, relations.Relation(Child) }, .{}),
) void {
    // Query all entities that have Transform and a Child relation (children with parents)
    while (query.next()) |item| {
        const transform: *Transform = item[0];
        const child_relation: *relations.Relation(Child) = item[1];

        // Get parent's transform
        var parent_world_x: f32 = 0;
        var parent_world_y: f32 = 0;
        var parent_world_z: f32 = 0;

        const parent_entity = child_relation.target;
        if (commands.manager.getComponent(parent_entity, Transform) catch null) |parent_transform| {
            parent_world_x = parent_transform.world_x;
            parent_world_y = parent_transform.world_y;
            parent_world_z = parent_transform.world_z;
        }

        // Update world transform by combining parent's world transform with local transform
        transform.world_x = parent_world_x + transform.local_x;
        transform.world_y = parent_world_y + transform.local_y;
        transform.world_z = parent_world_z + transform.local_z;
    }

    std.log.info("Relations index count: {d}", .{rel.indexCount()});
}

// Wrapper for benchmarking system execution
fn benchRunTransformSystem(manager: *Manager, system_handle: anytype) void {
    manager.runSystem(system_handle) catch |err| {
        std.debug.print("Error running transform system: {s}\n", .{@errorName(err)});
    };
}

test "ECS Benchmark - Scene Graph Relations" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeaderWithTitle("Relations");
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        // Get Relations system parameter (creates RelationManager resource automatically)
        const rel = try root.DefaultParamRegistry.apply(&manager, *root.Relations);

        var entities = try setupSceneGraph(&manager, rel, count);
        defer entities.deinit(bench.getCountingAllocator());

        // Create system that uses Query with Relation component
        const system_handle = manager.createSystemCached(systemUpdateTransforms, root.DefaultParamRegistry);

        const label = try std.fmt.allocPrint(allocator, "Scene Graph {d} Entities", .{count});
        defer allocator.free(label);

        // Benchmark running the system
        const result = try bench.run(label, BENCH_OPT_COUNT, benchRunTransformSystem, .{ &manager, system_handle });
        Benchmark.printResult(result, .markdown);
    }

    std.debug.print("\n", .{});
}
