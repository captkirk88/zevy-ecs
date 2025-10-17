const std = @import("std");
const benchmark = @import("benchmark.zig");
const Benchmark = benchmark.Benchmark;
const root = @import("root.zig");
const ecs = @import("ecs.zig");
const Manager = ecs.Manager;
const Entity = @import("ecs.zig").Entity;
const Query = root.Query;

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
const MovementQueryExclude = struct {};
const HealthRegenQueryInclude = struct { health: Health };
const HealthRegenQueryExclude = struct {};
const DamageWithArmorQueryInclude = struct { health: Health, armor: Armor, damage: Damage };
const DamageWithArmorQueryExclude = struct {};
const DamageNoArmorQueryInclude = struct { health: Health, damage: Damage };
const DamageNoArmorQueryExclude = struct { armor: Armor };
const TeamCollisionQueryInclude = struct { pos: Position, team: Team };
const TeamCollisionQueryExclude = struct {};
const TargetTrackingQueryInclude = struct { pos: Position, target: Target };
const TargetTrackingQueryExclude = struct {};
const VelocityDampingQueryInclude = struct { vel: Velocity };
const VelocityDampingQueryExclude = struct {};

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
fn systemMovement(e: *Manager, query: Query(MovementQueryInclude, MovementQueryExclude)) void {
    _ = e;
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const vel: *Velocity = item.vel;
        pos.x += vel.dx;
        pos.y += vel.dy;
        pos.z += vel.dz;
    }
}

// System 2: Health Regeneration - Regenerate health over time
fn systemHealthRegen(e: *Manager, query: Query(HealthRegenQueryInclude, HealthRegenQueryExclude)) void {
    _ = e;
    while (query.next()) |item| {
        const health: *Health = item.health;
        if (health.current < health.max) {
            health.current = @min(health.current + 1, health.max);
        }
    }
}

// System 3: Damage Application - Apply damage to entities with armor
fn systemDamageWithArmor(e: *Manager, query: Query(DamageWithArmorQueryInclude, DamageWithArmorQueryExclude)) void {
    _ = e;
    while (query.next()) |item| {
        const health: *Health = item.health;
        const armor: *Armor = item.armor;
        const damage: *Damage = item.damage;
        const actual_damage = if (damage.value > armor.value) damage.value - armor.value else 0;
        if (health.current > actual_damage) {
            health.current -= actual_damage;
        } else {
            health.current = 0;
        }
    }
}

// System 4: Damage Application - Apply damage to entities without armor
fn systemDamageNoArmor(_: *Manager, query: Query(DamageNoArmorQueryInclude, DamageNoArmorQueryExclude)) void {
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
fn systemTeamCollision(_: *Manager, query: Query(TeamCollisionQueryInclude, TeamCollisionQueryExclude)) void {
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
fn systemTargetTracking(_: *Manager, query: Query(TargetTrackingQueryInclude, TargetTrackingQueryExclude)) void {
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
fn systemVelocityDamping(_: *Manager, query: Query(VelocityDampingQueryInclude, VelocityDampingQueryExclude)) void {
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

    Benchmark.printMarkdownHeader();
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Create {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, 3, benchCreateEntities, .{ &manager, count });
        Benchmark.printResultFormatted(result, .markdown);
    }

    std.debug.print("\n", .{});
}

test "ECS Benchmark - Batch Entity Creation" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeader();
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Batch Create {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, 3, batchCreateEntities, .{ &manager, count, allocator });
        Benchmark.printResultFormatted(result, .markdown);
    }

    std.debug.print("\n", .{});
}

test "ECS Benchmark - Mixed Systems" {
    const allocator = std.testing.allocator;
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    Benchmark.printMarkdownHeader();
    for (counts) |count| {
        var manager = try Manager.init(bench.getCountingAllocator());
        defer manager.deinit();

        // Setup entities
        setupMixedEntities(&manager, count);
        const systems = setupMixedSystems(&manager);

        const label = try std.fmt.allocPrint(allocator, "Run 7 Systems on {d} Entities", .{count});
        defer allocator.free(label);

        const result = try bench.run(label, 1, benchMixedSystems, .{ &manager, &systems });

        Benchmark.printResultFormatted(result, .markdown);
    }

    std.debug.print("\n", .{});
}

fn setupMixedSystems(e: *Manager) [7]ecs.SystemHandle {
    const DefaultRegistry = @import("root.zig").DefaultParamRegistry;
    var results: [7]ecs.SystemHandle = undefined;
    results[0] = e.createSystemCached(systemMovement, DefaultRegistry);
    results[1] = e.createSystemCached(systemHealthRegen, DefaultRegistry);
    results[2] = e.createSystemCached(systemDamageWithArmor, DefaultRegistry);
    results[3] = e.createSystemCached(systemDamageNoArmor, DefaultRegistry);
    results[4] = e.createSystemCached(systemTeamCollision, DefaultRegistry);
    results[5] = e.createSystemCached(systemTargetTracking, DefaultRegistry);
    results[6] = e.createSystemCached(systemVelocityDamping, DefaultRegistry);
    return results;
}

fn benchMixedSystems(e: *Manager, systems: *const [7]ecs.SystemHandle) void {
    for (systems) |sys_id| {
        _ = e.runSystem(void, sys_id) catch |err| {
            std.debug.print("Error running system {d}: {s}\n", .{ sys_id, @errorName(err) });
            break;
        };
    }
}
