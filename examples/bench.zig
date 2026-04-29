const std = @import("std");
const builtin = @import("builtin");
const Benchmark = @import("benchmark");
const zevy_ecs = @import("zevy_ecs");
const Manager = zevy_ecs.Manager;
const Entity = zevy_ecs.Entity;
const Commands = zevy_ecs.params.Commands;
const Query = zevy_ecs.params.Query;
const Without = zevy_ecs.Without;
const Scheduler = zevy_ecs.schedule.Scheduler;
const Stage = zevy_ecs.schedule.Stage;
const StageId = zevy_ecs.schedule.StageId;
const Stages = zevy_ecs.schedule.Stages;
const relations = zevy_ecs.relations;
const RelationManager = relations.RelationManager;
const Child = relations.kinds.Child;
const Owns = relations.kinds.Owns;

const mem = @import("zevy_mem");

pub fn main(init: std.process.Init) !void {
    //if (builtin.mode == .Debug) return;

    const allocator = init.gpa;
    var bench = Benchmark.init(allocator, .markdown);
    defer bench.deinit();
    try runBenchmarks(&bench, allocator, init.io);
}

fn runBenchmarks(bench: *Benchmark, allocator: std.mem.Allocator, io: std.Io) !void {
    const counts = [_]usize{ 100, 1_000, 10_000, 100_000, 1_000_000 };

    // Non-batch Creation
    try bench.beginSection("Creation");
    for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Create {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchCreateEntities, .{ &manager, count });
    }

    // Batch Creation
    try bench.beginSection("Batch Creation");
    for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        const label = try std.fmt.allocPrint(allocator, "Create {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, batchCreateEntities, .{ &manager, count, allocator });
    }

    // Mixed Systems
    try bench.beginSection("Mixed Systems");
    inline for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        // Setup entities
        var entities = try setupMixedEntities(&manager, allocator, count);
        defer entities.deinit(allocator);

        const systems = setupMixedSystems(&manager);

        const label = try std.fmt.allocPrint(allocator, "Run 7 Systems on {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchMixedSystems, .{ &manager, &systems });
    }

    // Scheduler
    try bench.beginSection("Scheduler");
    inline for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        var entities = try setupMixedEntities(&manager, allocator, count);
        defer entities.deinit(allocator);

        var scheduler = try Scheduler.init(bench.allocator());
        defer scheduler.deinit();

        setupScheduledMixedSystems(&manager, &scheduler);

        var stage_infos = scheduler.getStageInfo(allocator);
        defer stage_infos.deinit(allocator);
        var active_stages = try std.ArrayList(StageId).initCapacity(allocator, stage_infos.items.len);
        defer active_stages.deinit(allocator);
        for (stage_infos.items) |stage_info| {
            if (stage_info.system_count > 0) {
                try active_stages.append(allocator, stage_info.stage);
            }
        }

        const stage_count = active_stages.items.len;
        const label = try std.fmt.allocPrint(allocator, "{d} Entities, {d} Stages", .{ count, stage_count });
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchSchedulerMixedSystems, .{ &scheduler, &manager });
    }

    // CRUD Systems
    try bench.beginSection("CRUD System");
    inline for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        var entities = try setupMixedEntities(&manager, allocator, count);
        defer entities.deinit(allocator);

        const crud_system = manager.createSystemCached(systemCrudAddRemoveComponents, zevy_ecs.DefaultParamRegistry);

        const label = try std.fmt.allocPrint(allocator, "Run CRUD System on {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchRunCrudSystem, .{ &manager, crud_system.eraseType() });
    }

    // Relations
    try bench.beginSection("Relations");
    for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        // Acquire Relations, build the scene graph, then release the lock before benchmarking.
        // The system being benchmarked also acquires a lock on RelationManager, so
        // holding the lock here while running bench.run() would deadlock.
        var entities = blk: {
            const rel = manager.getResource(relations.RelationManager);
            if (rel) |r| {
                defer r.deinit(); // release Arc ref when block exits
                var rel_lock = r.lockWrite();
                defer rel_lock.deinit();
                break :blk try setupSceneGraph(&manager, rel_lock.get(), count);
            } else {
                std.debug.print("Failed to acquire RelationManager for setup\n", .{});
                break :blk try std.ArrayList(Entity).initCapacity(allocator, 0);
            }
        };
        defer entities.deinit(bench.allocator());

        // Create system that uses Query with Relation component
        const system_handle = manager.createSystemCached(systemUpdateTransforms, zevy_ecs.DefaultParamRegistry);

        const label = try std.fmt.allocPrint(allocator, "Scene Graph {d} Entities", .{count});
        defer allocator.free(label);

        // Benchmark running the system (acquires its own write lock on RelationManager)
        _ = try bench.run(label, BENCH_OPT_COUNT, benchRunTransformSystem, .{ &manager, system_handle });
    }

    // Serialization
    try bench.beginSection("Serialization");
    inline for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        var entities = try setupMixedEntities(&manager, allocator, count);
        defer entities.deinit(allocator);

        const label = try std.fmt.allocPrint(allocator, "Serialize {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchSerialize, .{ &manager, allocator, io, entities });
    }

    // Deserialization
    try bench.beginSection("Deserialization");
    inline for (counts) |count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        var entities = try setupMixedEntities(&manager, allocator, count);
        defer entities.deinit(allocator);

        const label = try std.fmt.allocPrint(allocator, "Deserialize {d} Entities", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchDeserialize, .{ &manager, allocator, io, count });
    }

    // Resource Serialization
    try bench.beginSection("Resource Serialization");
    inline for (resource_counts) |res_count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        addBenchResources(&manager, res_count);

        const label = try std.fmt.allocPrint(allocator, "Serialize {d} Resources", .{res_count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchSerializeResources, .{ &manager, allocator, res_count });
    }

    // Resource Deserialization
    try bench.beginSection("Resource Deserialization");
    inline for (resource_counts) |res_count| {
        var manager = try Manager.init(bench.allocator());
        defer manager.deinit();

        addBenchResources(&manager, res_count);

        const label = try std.fmt.allocPrint(allocator, "Deserialize {d} Resources", .{res_count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchDeserializeResources, .{ &manager, allocator, res_count });
    }

    // Manager Transfer
    try bench.beginSection("Manager Transfer");
    inline for (counts) |count| {
        var src_manager = try Manager.init(bench.allocator());
        defer src_manager.deinit();

        var dst_manager = try Manager.init(bench.allocator());
        defer dst_manager.deinit();

        var entities = try setupMixedEntities(&src_manager, allocator, count);
        defer entities.deinit(allocator);

        var transfer_state = TransferBenchmarkState{
            .src = &src_manager,
            .dst = &dst_manager,
            .entities = &entities,
            .allocator = allocator,
        };

        const label = try std.fmt.allocPrint(allocator, "Transfer {d} Entities Between Managers", .{count});
        defer allocator.free(label);

        _ = try bench.run(label, BENCH_OPT_COUNT, benchTransferEntities, .{&transfer_state});
    }

    var stdout_buf: [65536]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    try bench.print(&stdout_writer.interface);
    try stdout_writer.flush();

    try bench.writeReportWithOptions(io, .{
        .directory = ".",
        .file_name = "BENCHMARK.md",
    });
}

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

const GameSettings = struct {
    width: u32,
    height: u32,
    fullscreen: bool,
    volume: f32,
};

const PhysicsConfig = struct {
    gravity: f32,
    max_velocity: f32,
    iterations: u32,
};

const AudioConfig = struct {
    master_volume: f32,
    music_volume: f32,
    sfx_volume: f32,
    sample_rate: u32,
};

const GraphicsConfig = struct {
    shadow_quality: u8,
    aa_samples: u8,
    fov: f32,
    draw_distance: f32,
};

const InputConfig = struct {
    mouse_sensitivity: f32,
    invert_y: bool,
    deadzone: f32,
};

const NetworkConfig = struct {
    port: u16,
    max_connections: u16,
    timeout_ms: u32,
    tick_rate: u32,
};

const DebugConfig = struct {
    show_fps: bool,
    show_colliders: bool,
    log_level: u8,
};

const CameraConfig = struct {
    near_clip: f32,
    far_clip: f32,
    aspect_ratio: f32,
};

const AIConfig = struct {
    update_interval_ms: u32,
    max_agents: u32,
    path_cache_size: u32,
};

const SaveConfig = struct {
    auto_save_interval_s: u32,
    max_save_slots: u8,
    compress: bool,
};

/// All benchmark resource types as a comptime tuple.
const BenchResources = .{
    GameSettings,
    PhysicsConfig,
    AudioConfig,
    GraphicsConfig,
    InputConfig,
    NetworkConfig,
    DebugConfig,
    CameraConfig,
    AIConfig,
    SaveConfig,
};

const resource_counts = [_]usize{ 1, 2, 4, 6, 8, 10 };

const Target = struct {
    entity: Entity,
};

// Query types
const MovementQueryInclude = struct { pos: Position, vel: Velocity };
const DamageNoArmorQueryInclude = struct { health: Health, damage: Damage, no_armor: Without(Armor) };
const TeamCollisionQueryInclude = struct { pos: Position, team: Team };
const TargetTrackingQueryInclude = struct { pos: Position, target: Target };
const VelocityDampingQueryInclude = struct { vel: Velocity };

const BENCH_OPT_COUNT = 10;

const TransferBenchmarkState = struct {
    src: *Manager,
    dst: *Manager,
    entities: *std.ArrayList(Entity),
    allocator: std.mem.Allocator,

    fn swapManagers(self: *@This()) void {
        const prev_src = self.src;
        self.src = self.dst;
        self.dst = prev_src;
    }
};

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

fn benchTransferEntities(state: *TransferBenchmarkState) void {
    for (state.entities.items) |*entity| {
        const source_entity = entity.*;
        entity.* = state.src.moveEntityTo(state.allocator, state.dst, source_entity) catch |err| {
            std.debug.panic("Failed to transfer entity {d}:{d}: {s}\n", .{ source_entity.id, source_entity.generation, @errorName(err) });
        };
    }

    state.swapManagers();
}

// Benchmark 2: Mixed System Operations
// System 1: Movement - Update positions based on velocity
fn systemMovement(query: Query(struct { pos: Position, vel: Velocity })) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const vel: *Velocity = item.vel;
        pos.x += vel.dx;
        pos.y += vel.dy;
        pos.z += vel.dz;
    }
}

// System 2: Health Regeneration - Regenerate health over time
fn systemHealthRegen(query: Query(.{Health})) void {
    while (query.next()) |item| {
        const health: *Health = item[0];
        if (health.current < health.max) {
            health.current = @min(health.current + 1, health.max);
        }
    }
}

// System 3: Damage Application - Apply damage to entities with armor
fn systemDamageWithArmor(query: Query(.{ Health, Damage, Armor })) void {
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
fn systemDamageNoArmor(query: Query(DamageNoArmorQueryInclude)) void {
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
fn systemTeamCollision(query: Query(TeamCollisionQueryInclude)) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const team: *Team = item.team;
        // Simple distance calculation
        const dist_sq = pos.x * pos.x + pos.y * pos.y + pos.z * pos.z;
        std.mem.doNotOptimizeAway(dist_sq);
        std.mem.doNotOptimizeAway(team);
    }
}

// System 6: Target Tracking - Steer toward a deterministic target position
fn systemTargetTracking(query: Query(TargetTrackingQueryInclude)) void {
    while (query.next()) |item| {
        const pos: *Position = item.pos;
        const target: *Target = item.target;
        const target_bias = @as(f32, @floatFromInt(target.entity.id % 97));
        pos.x += (target_bias - pos.x) * 0.001;
        pos.y += (@as(f32, @floatFromInt((target.entity.id >> 1) % 53)) - pos.y) * 0.001;
        pos.z += (@as(f32, @floatFromInt((target.entity.id >> 2) % 29)) - pos.z) * 0.001;
    }
}

// CRUD System: collect work from a query, explicitly release it, then mutate the world.
fn systemCrudAddRemoveComponents(commands: Commands, query: Query(TargetTrackingQueryInclude)) !void {
    var released_query = query;
    defer released_query.deinit();

    var spawn_snapshot: ?Position = null;

    while (released_query.next()) |item| {
        const pos: *Position = item.pos;
        const target = item.target.entity;
        var target_commands = try commands.entity(target);

        // Read from the target entity and update the current entity inline while the query is alive.
        if (try target_commands.get(Position)) |target_pos| {
            pos.x += (target_pos.x - pos.x) * 0.01;
            pos.y += (target_pos.y - pos.y) * 0.01;
            pos.z += (target_pos.z - pos.z) * 0.01;
        }

        // Update or delete a component through deferred commands.
        if (target.id % 2 == 0) {
            try commands.addComponent(target, Armor, .{ .value = @intCast((target.id % 15) + 1) });
        } else {
            try commands.removeComponent(target, Armor);
        }

        if (spawn_snapshot == null) {
            spawn_snapshot = pos.*;
        }
    }

    released_query.deinit();

    if (spawn_snapshot) |snapshot| {
        // Create a short-lived entity after releasing the query so the world can mutate safely.
        var spawned = try commands.create();
        defer spawned.deinit();

        _ = try spawned.add(Position, snapshot);
        _ = try spawned.add(Health, .{ .current = 1, .max = 1 });
        _ = try spawned.destroy();
    }
}

// System 7: Velocity Damping - Apply friction/damping to velocity
fn systemVelocityDamping(query: Query(VelocityDampingQueryInclude)) void {
    while (query.next()) |item| {
        const vel: *Velocity = item.vel;
        vel.dx *= 0.99;
        vel.dy *= 0.99;
        vel.dz *= 0.99;
    }
}

// Setup function to create diverse entity archetypes
fn setupMixedEntities(manager: *Manager, allocator: std.mem.Allocator, comptime count: usize) !std.ArrayList(Entity) {
    var entities = try std.ArrayList(Entity).initCapacity(allocator, count);
    for (0..count) |i| {
        const pos = Position{ .x = @floatFromInt(i), .y = 0.0, .z = 0.0 };
        const vel = Velocity{ .dx = 1.0, .dy = 0.5, .dz = -0.5 };
        const health = Health{ .current = 100, .max = 100 };

        // Create different archetypes based on index
        switch (i % 7) {
            0 => {
                // Basic: Position, Velocity, Health
                entities.append(allocator, manager.create(.{ pos, vel, health })) catch {};
            },
            1 => {
                // With Armor
                const armor = Armor{ .value = 10 };
                entities.append(allocator, manager.create(.{ pos, vel, health, armor })) catch {};
            },
            2 => {
                // With Damage
                const damage = Damage{ .value = 5 };
                entities.append(allocator, manager.create(.{ pos, vel, health, damage })) catch {};
            },
            3 => {
                // With Armor and Damage
                const armor = Armor{ .value = 10 };
                const damage = Damage{ .value = 5 };
                entities.append(allocator, manager.create(.{ pos, vel, health, armor, damage })) catch {};
            },
            4 => {
                // With Team
                const team = Team{ .id = @intCast(i % 4) };
                entities.append(allocator, manager.create(.{ pos, vel, health, team })) catch {};
            },
            5 => {
                // With Target
                const target = Target{ .entity = Entity{ .id = @intCast(i / 2), .generation = 0 } };
                entities.append(allocator, manager.create(.{ pos, vel, health, target })) catch {};
            },
            else => {
                // With Team and Target
                const team = Team{ .id = @intCast(i % 4) };
                const target = Target{ .entity = Entity{ .id = @intCast(i / 2), .generation = 0 } };
                entities.append(allocator, manager.create(.{ pos, vel, health, team, target })) catch {};
            },
        }
    }
    _ = try manager.addResource(GameSettings, .{
        .width = 1920,
        .height = 1080,
        .fullscreen = true,
        .volume = 0.75,
    });
    return entities;
}

fn setupMixedSystems(e: *Manager) [7]zevy_ecs.UntypedSystemHandle {
    const DefaultRegistry = zevy_ecs.DefaultParamRegistry;
    var results: [7]zevy_ecs.UntypedSystemHandle = undefined;
    results[0] = e.createSystemCached(systemMovement, DefaultRegistry).eraseType();
    results[1] = e.createSystemCached(systemHealthRegen, DefaultRegistry).eraseType();
    results[2] = e.createSystemCached(systemDamageWithArmor, DefaultRegistry).eraseType();
    results[3] = e.createSystemCached(systemDamageNoArmor, DefaultRegistry).eraseType();
    results[4] = e.createSystemCached(systemTeamCollision, DefaultRegistry).eraseType();
    results[5] = e.createSystemCached(systemTargetTracking, DefaultRegistry).eraseType();
    results[6] = e.createSystemCached(systemVelocityDamping, DefaultRegistry).eraseType();
    return results;
}

fn benchMixedSystems(e: *Manager, systems: *const [7]zevy_ecs.UntypedSystemHandle) void {
    for (systems) |sys_id| {
        _ = e.runSystemUntyped(void, sys_id) catch |err| {
            std.debug.print("Error running system {d}: {s}\n", .{ sys_id, @errorName(err) });
            break;
        };
    }
}

fn setupScheduledMixedSystems(manager: *Manager, scheduler: *Scheduler) void {
    const DefaultRegistry = zevy_ecs.DefaultParamRegistry;
    scheduler.addSystem(manager, Stage(Stages.Update), systemMovement, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Update), systemHealthRegen, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Update), systemDamageWithArmor, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Draw), systemDamageNoArmor, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Draw), systemTeamCollision, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Draw), systemTargetTracking, DefaultRegistry);
    scheduler.addSystem(manager, Stage(Stages.Last), systemVelocityDamping, DefaultRegistry);
}

/// Benchmarks running the mixed systems through the scheduler from the first stage to the last stage
///
/// *Note*: This runs 7 systems through all entity counts (up to 1,000,000 entities as in the benchmarks above) split into
/// stages according to the scheduler stages (Update / Draw / Last) so that each system runs in the stage it was added to
fn benchSchedulerMixedSystems(scheduler: *Scheduler, manager: *Manager) void {
    const eg = scheduler.runStages(manager, Stage(Stages.First), Stage(Stages.Last));
    var iter = eg.iterator();
    while (iter.next()) |err| {
        std.debug.print("Error running scheduler stage: {s}\n", .{@errorName(err)});
    }
}

fn benchRunCrudSystem(e: *Manager, system_handle: zevy_ecs.UntypedSystemHandle) void {
    _ = e.runSystemUntyped(void, system_handle) catch |err| {
        std.debug.print("Error running CRUD system {d}: {s}\n", .{ system_handle, @errorName(err) });
    };
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
fn setupSceneGraph(manager: *Manager, rel: *zevy_ecs.relations.RelationManager, count: usize) !std.ArrayList(Entity) {
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
        try rel.add(manager, level_obj, root_entity, relations.kinds.Child);
        level_objects.append(allocator, level_obj) catch {};
        all_entities.append(allocator, level_obj) catch {};

        // Add 3 props per level object
        for (0..3) |j| {
            if (all_entities.items.len >= count) break;
            const prop = manager.create(.{Transform{ .local_x = @as(f32, @floatFromInt(j)), .local_y = 1, .local_z = 0 }});
            try rel.add(manager, prop, level_obj, relations.kinds.Child);
            all_entities.append(allocator, prop) catch {};
        }
    }

    // Create characters under root
    for (0..character_count) |i| {
        if (all_entities.items.len >= count) break;
        const character = manager.create(.{Transform{ .local_x = @as(f32, @floatFromInt(i)), .local_y = 0, .local_z = @as(f32, @floatFromInt(i)) * 2 }});
        try rel.add(manager, character, root_entity, relations.kinds.Child);
        all_entities.append(allocator, character) catch {};

        // Add body parts (head, left_arm, right_arm, weapon)
        const body_parts = [_][]const u8{ "head", "left_arm", "right_arm", "weapon" };
        for (body_parts, 0..) |_, j| {
            if (all_entities.items.len >= count) break;
            const part = manager.create(.{Transform{ .local_x = 0, .local_y = @as(f32, @floatFromInt(j)), .local_z = 0 }});
            try rel.add(manager, part, character, relations.kinds.Child);
            all_entities.append(allocator, part) catch {};
        }
    }

    return all_entities;
}

// System: Update world transforms based on parent hierarchy using ECS Query
fn systemUpdateTransforms(
    commands: Commands,
    query: Query(.{ Transform, relations.Relation(relations.kinds.Child) }),
) void {
    // Query all entities that have Transform and a Child relation (children with parents)
    while (query.next()) |item| {
        const transform: *Transform = item[0];
        const child_relation: *relations.Relation(relations.kinds.Child) = item[1];

        // Get parent's transform
        var parent_world_x: f32 = 0;
        var parent_world_y: f32 = 0;
        var parent_world_z: f32 = 0;

        const parent_entity = child_relation.target;
        var parent_commands = commands.entity(parent_entity) catch continue;
        if (parent_commands.get(Transform) catch null) |parent_transform| {
            parent_world_x = parent_transform.world_x;
            parent_world_y = parent_transform.world_y;
            parent_world_z = parent_transform.world_z;
        }

        // Update world transform by combining parent's world transform with local transform
        transform.world_x = parent_world_x + transform.local_x;
        transform.world_y = parent_world_y + transform.local_y;
        transform.world_z = parent_world_z + transform.local_z;
    }
}

// Wrapper for benchmarking system execution
fn benchRunTransformSystem(manager: *Manager, system_handle: anytype) void {
    manager.runSystem(system_handle) catch |err| {
        std.debug.print("Error running transform system: {s}\n", .{@errorName(err)});
    };
}

fn benchSerialize(manager: *Manager, allocator: std.mem.Allocator, io: std.Io, entities: std.ArrayList(Entity)) !void {
    const label = try std.fmt.allocPrint(allocator, "test_data/benchmark_serialize_{d}.bin", .{entities.items.len});
    defer allocator.free(label);
    var buf: [65536]u8 = undefined; // 64 KiB write buffer
    std.Io.Dir.cwd().createDirPath(io, "test_data/") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var file = try std.Io.Dir.cwd().createFile(io, label, .{
        .truncate = true,
    });
    defer file.close(io);
    var file_writer = file.writer(io, &buf);
    for (entities.items) |entity| {
        // Use the plain allocator so the counting allocator isn't charged for temp work.
        const comps = try manager.getAllComponents(allocator, entity);
        defer allocator.free(comps);
        for (comps) |comp| {
            try comp.writeTo(&file_writer.interface);
        }
    }
    // Single flush at the end — flushing per-component causes N syscalls.
    try file_writer.flush();
}

fn defaultBenchResource(comptime T: type) T {
    var val: T = std.mem.zeroes(T);
    inline for (std.meta.fields(T)) |field| {
        switch (@typeInfo(field.type)) {
            .float => @field(val, field.name) = 1.0,
            .int => @field(val, field.name) = 1,
            .bool => @field(val, field.name) = false,
            else => {},
        }
    }
    return val;
}

fn addBenchResources(manager: *Manager, comptime count: usize) void {
    inline for (0..count) |i| {
        const T = BenchResources[i];
        manager.addResourceRetained(T, defaultBenchResource(T)) catch {};
    }
}

fn benchSerializeResources(manager: *Manager, allocator: std.mem.Allocator, comptime count: usize) !void {
    inline for (0..count) |i| {
        const T = BenchResources[i];
        var snapshot = try zevy_ecs.serialize.ResourceSnapshot.fromManager(allocator, manager, T);
        defer snapshot.deinit(allocator);
        var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
        defer writer_alloc.deinit();
        try snapshot.writeTo(&writer_alloc.writer);
        const buf = try writer_alloc.toOwnedSlice();
        defer allocator.free(buf);
        std.mem.doNotOptimizeAway(buf);
    }
}

fn benchDeserializeResources(manager: *Manager, allocator: std.mem.Allocator, comptime count: usize) !void {
    inline for (0..count) |i| {
        const T = BenchResources[i];
        var snapshot = try zevy_ecs.serialize.ResourceSnapshot.fromManager(allocator, manager, T);
        defer snapshot.deinit(allocator);
        var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
        defer writer_alloc.deinit();
        try snapshot.writeTo(&writer_alloc.writer);
        const buf = try writer_alloc.toOwnedSlice();
        defer allocator.free(buf);
        var reader = std.Io.Reader.fixed(buf);
        var restored = try zevy_ecs.serialize.ResourceSnapshot.readFrom(&reader, allocator);
        defer restored.deinit(allocator);
        try restored.toManager(manager);
    }
}

fn benchDeserialize(manager: *Manager, allocator: std.mem.Allocator, io: std.Io, count: usize) !void {
    _ = manager;
    var buf: [65536]u8 = undefined; // 64 KiB read buffer
    const label = try std.fmt.allocPrint(allocator, "test_data/benchmark_serialize_{d}.bin", .{count});
    defer allocator.free(label);
    var file = try std.Io.Dir.cwd().openFile(io, label, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &buf);
    while (true) {
        const comp = zevy_ecs.serialize.ComponentInstance.tryReadFrom(&file_reader.interface, allocator);
        if (comp == null) break; // EOF reached
        defer allocator.free(comp.?.data);
        // Process component data as needed (omitted for benchmark)
    }
}
