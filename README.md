# zevy_ecs

A high-performance, archetype-based Entity-Component-System (ECS) framework written in Zig. It provides a type-safe, efficient way to manage entities, components, systems, resources, and events in your applications.

[![Zig Version](https://img.shields.io/badge/zig-0.16.0.dev-blue.svg)](https://ziglang.org/)

> [!NOTE]
> See the `zig-1.51` branch (yes I messed up the branch name) version compatible with Zig 0.15.x but I'll probably delete it because the new zevy-ecs version is much better and Zig 0.16-dev has been out for a while now.

## Why Zig?

Good question.  The std API has changed to the point I don't even know anymore.  Ultimately, Zig has it's advantages over Rust (especially it's async approach) BUT the ecosystem is still very young and *rapidly* changing.  I would recommend using this library if you want to learn about ECS architecture and are comfortable with Zig's current state.


## Features

- **Archetype-based storage**: Efficiently groups entities with the same component combinations for cache-friendly iteration
- **Type-safe queries**: Compile-time validated component queries with support for optional components and filters (With/Without)
- **Flexible system parameters**: Built-in support for Query, Res (resources), Local (per-system state), State/NextState, EventReader/EventWriter, Relations
- **Relationship Support** : Manage entity relationships with minimal overhead using the Relations system parameter
- **Resource management**: Global state accessible across systems with automatic cleanup
- **Event system**: Built-in event queue with filtering and handling capabilities in a circular buffer
- **Batch operations**: High-performance batch entity creation
- **Component serialization**: Built-in support for serializing/deserializing components, resources, and entities
- **Extensible parameter system**: Create custom system parameters by implementing `matches`, `apply`, and optional `deinit` functions
- **Zero runtime overhead**: All system parameter resolution happens at compile time

## Table of Contents

- [Quick Start](#quick-start)
    - [Installation](#installation)
    - [Basic Usage](#basic-usage)
- [Core Concepts](#core-concepts)
    - [Entities](#entities)
    - [Components](#components)
    - [Queries](#queries)
    - [Systems](#systems)
    - [System Parameters](#system-parameters)
    - [Resources](#resources)
    - [Events](#events)
    - [Relations](#relations)
- [Advanced Features](#advanced-features)
    - [System Composition](#system-composition)
    - [Custom System Registries](#custom-system-registries)
    - [Serialization](#serialization)
        - [Basic Component Serialization](#basic-component-serialization)
        - [Resource Serialization](#resource-serialization)
        - [Using ComponentWriter](#using-componentwriter)
        - [Using ComponentReader](#using-componentreader)
        - [Entity Serialization](#entity-serialization)
        - [Batch Entity Serialization](#batch-entity-serialization)
    - [Plugin System](#plugin-system)
        - [Basic Plugin Usage](#basic-plugin-usage)
        - [Creating Reusable Plugins](#creating-reusable-plugins)
    - [Scheduler](#scheduler)
        - [Predefined Stages](#predefined-stages)
        - [Basic Usage](#basic-usage-1)
        - [Creating Custom Stages](#creating-custom-stages)
        - [State Management](#state-management)
        - [Event Registration](#event-registration)
        - [Getting Stage Information](#getting-stage-information)
- [Performance](#performance)
- [Dependencies](#dependencies)
- [Contributing](#contributing)

## Quick Start

### Installation

```zig
zig fetch --save https://github.com/captkirk88/zevy-ecs/archive/refs/tags/<tag name>.tar.gz
// OR for latest commit from main branch
zig fetch --save git+https://github.com/captkirk88/zevy-ecs
```

And in your `build.zig`:

```zig
const zevy_ecs = b.dependency("zevy_ecs", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zevy_ecs", zevy_ecs.module("zevy_ecs"));

// Optional: If you want to use the benchmarking utilities
exe.root_module.addImport("zevy_ecs_benchmark", zevy_ecs.module("benchmark"));

// Optional: If you want to use the plugin system
exe.root_module.addImport("zevy_ecs_plugins", zevy_ecs.module("plugins")); // Would recommend calling it something easier to work with.
```

### Basic Usage

```zig
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");

// Define your components
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    dx: f32,
    dy: f32,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create the ECS manager
    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create entities with components
    const entity1 = manager.create(.{
        Position{ .x = 0.0, .y = 0.0 },
        Velocity{ .dx = 1.0, .dy = 0.5 },
    });

    const entity2 = manager.create(.{
        Position{ .x = 10.0, .y = 5.0 },
        Velocity{ .dx = -0.5, .dy = 1.0 },
    });

    // Query and iterate over entities
    var query = manager.query(
        struct { pos: Position, vel: Velocity },
    );

    // var query = manager.query(.{Position, Velocity}); // Alternative syntax

    while (query.next()) |item| {
        // item.pos is *Position, item.vel is *Velocity
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }

    // Create and run system
    const move_system = manager.cacheSystem(zevy_ecs.ToSystem(movementSystem, zevy_ecs.DefaultParamRegistry));
    try manager.runSystem(move_system);
}

fn movementSystem(
    query: zevy_ecs.Query(
        struct { pos: Position, vel: Velocity },
    ),
) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}
```

## Core Concepts

### Entities

Entities are lightweight identifiers that tie components together. They have an ID and generation for safe reuse.

```zig
// Create an entity with components
const entity = manager.create(.{
    Position{ .x = 0.0, .y = 0.0 },
    Health{ .current = 100, .max = 100 },
});

// Create empty entity
const empty = manager.createEmpty();

const allocator = std.heap.page_allocator;

// Batch create entities (more efficient)
const entities = try manager.createBatch(allocator,1000, .{
    Position{ .x = 0.0, .y = 0.0 },
});
defer allocator.free(entities);

// Check if entity is alive
if (manager.isAlive(entity)) {
    // Entity exists
}
```

### Components

Components are plain Zig structs that hold data. You can use packed structs if you prefer.

> [!NOTE]
> Components may contain pointers to externally-managed memory.  I recommend using POD types.  If you do use pointers, ensure the allocator's lifetime exceeds that of the ECS manager and destroy any externally-managed memory after removing the component or destroying the entity.

```zig
const Position = struct {
    x: f32,
    y: f32,
};

const Health = struct {
    current: u32,
    max: u32,
};

// Add component to existing entity
try manager.addComponent(entity, Velocity, .{ .dx = 1.0, .dy = 0.0 });

// Get component (returns ?*T)
if (try manager.getComponent(entity, Position)) |pos| {
    pos.x += 1.0;
}

// Check if entity has component
const has_health = try manager.hasComponent(entity, Health);

// Remove component
try manager.removeComponent(entity, Velocity);

// Get all components for an entity
const components = try manager.getAllComponents(allocator, entity);
defer allocator.free(components);
```

### Queries

Queries allow you to iterate over entities with specific component combinations.

```zig
// Query entities with Position and Velocity while requiring Health and Team
// and excluding entities that have Armor. The marker fields only affect
// archetype filtering and do not appear in the query result.
var query = manager.query(
    struct {
        pos: Position,
        vel: Velocity,
        living: zevy_ecs.With(.{ Health, Team }),
        no_armor: zevy_ecs.Without(Armor),
    },
);

while (query.next()) |item| {
    // Mutable access to components
    item.pos.x += item.vel.dx;
    item.pos.y += item.vel.dy;
}

// Query with optional components
var optional_query = manager.query(
    struct {
        pos: Position,
        vel: ?Velocity,  // Optional - may be null
    },
);

while (optional_query.next()) |item| {
    item.pos.x += 1.0;
    if (item.vel) |vel| {
        // Only if entity has Velocity
        item.pos.y += vel.dy;
    }
}

// Query with Entity ID
var entity_query = manager.query(
    struct {
        entity: zevy_ecs.Entity,
        pos: Position,
    },
);while (entity_query.next()) |item| {
    std.debug.print("Entity {d} at ({d}, {d})\n",
        .{ item.entity.id, item.pos.x, item.pos.y });
}
```

### Systems

Systems are functions that operate on entities and resources. They use a parameter injection system for automatic dependency resolution. All parameters are automatically injected.

```zig
const DeltaTime = struct { value: f32 };

// System function - all parameters are automatically resolved
fn movementSystem(
    query: zevy_ecs.Query(
        struct { pos: Position, vel: Velocity },
    ),
) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}

// System with resources
fn damageSystem(
    dt: zevy_ecs.Res(DeltaTime),
    query: zevy_ecs.Query(
        struct { health: Health },
    ),
) void {
    while (query.next()) |item| {
        if (item.health.current > 0) {
            item.health.current -= 1;
        }
    }
}

// System with Commands for deferred operations
fn spawnSystem(
    commands: zevy_ecs.Commands,
    query: zevy_ecs.Query(
        struct { spawner: Spawner },
    ),
) !void {
    while (query.next()) |item| {
        if (item.spawner.should_spawn) {
            // Deferred entity creation - entity created when deinit() is called
            var entity_cmds = try commands.create();
            defer entity_cmds.deinit();
            _ = try entity_cmds.add(Position, .{ .x = 0, .y = 0 });
            _ = try entity_cmds.add(Velocity, .{ .dx = 1.0, .dy = 0.0 });
        }
    }
}

// Create and run system directly
pub fn main() !void {
    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // Add a resource
    _ = try manager.addResource(DeltaTime, .{ .value = 0.016 });

    // Cache and reuse systems
    const system_handle = manager.cacheSystem(zevy_ecs.ToSystem(movementSystem, zevy_ecs.DefaultParamRegistry));
    try manager.runSystem(system_handle);

    // Or cache another system
    const handle = manager.cacheSystem(zevy_ecs.ToSystem(damageSystem, zevy_ecs.DefaultParamRegistry));
    try manager.runSystem(handle);
}
```

#### Debug Information

In Debug builds, systems include additional metadata about their signature and parameters. This is useful for logging, debugging, and tooling.

```zig
const system = zevy_ecs.ToSystem(movementSystem, zevy_ecs.DefaultParamRegistry);

// In Debug builds, access system debug info
if (@import("builtin").mode == .Debug) {
    // Access function signature
    std.debug.print("System signature: {s}\n", .{system.debug_info.signature});
    // Example output: "fn(*Manager, Query(Position, Velocity))"

    // Access individual parameter types
    std.debug.print("Number of params: {}\n", .{system.debug_info.params.len});
    for (system.debug_info.params, 0..) |param, i| {
        std.debug.print("  Param {}: {s}\n", .{ i, param.type_name });
        // Example output: "Param 0: Query(Position, Velocity)"
    }
}

// System handles also have debug info
const handle = manager.createSystemCached(movementSystem, zevy_ecs.DefaultParamRegistry);
if (@import("builtin").mode == .Debug) {
    std.debug.print("Handle signature: {s}\n", .{handle.debug_info.signature});
}
```

The debug info provides clean, readable type names for all system parameters including:

- `Res(T)` - Read-only resource types
- `ResMut(T)` - Mutable resource types
- `Query(Include)` - Query types with component names
- `With(T)` / `Without(T)` - Filter-only query markers that do not appear in results
- `Local(T)` - Local storage types
- `EventReader(T)` / `EventWriter(T)` - Event types
- `OnAdded(T)` / `OnRemoved(T)` - Component lifecycle types
- And all other system parameters

In Release builds, `debug_info` is `void` and has zero runtime overhead.

### System Parameters

Systems can request various parameters that are automatically injected. All parameters are optional and resolved at compile time:

- **`Commands`**: Deferred command buffer for entity/component/resource operations (executed after system completes)
- **`Query(Include, Exclude)`**: Query entities with specific components or **`Single`** to get a single entity with specific components
- **`Res(T)`**: Shared read-only access to a global resource of type T
- **`ResMut(T)`**: Exclusive mutable access to a global resource of type T
- **`Local(T)`**: Per-system persistent local state
- **`State(T)`**: Read-only access to check the current state (where T is an enum)
- **`NextState(T)`**: Trigger state transitions (where T is an enum)
- **`EventReader(T)`**: Read events of type T
- **`EventWriter(T)`**: Write events of type T
- **`OnAdded(T)`**: Iterate over entities that had component T added since the last system run
- **`OnRemoved(T)`**: Iterate over entities from which component T was removed since the last system run
- **`Relations`**: Access to relation operations for entity relationships

> [!NOTE]
> Use `commands.manager()` when you need direct `*Manager` access inside a system. For deferred creation, call `commands.create()`, queue operations on the returned `EntityCommands`, then call `entity_cmds.flush()` and `entity_cmds.entity()` to access the created entity. For existing entities, use `commands.entity(entity)` and `EntityCommands.get(T)` when you need to read the current component value through the manager.

More can be added by implementing custom parameter types. (see [Custom System Registries](#custom-system-registries))

### Resources

Resources are global singleton values accessible across systems.

```zig
const GameConfig = struct {
    width: u32,
    height: u32,
    fps: u32,
};

// Add resource, returns pointer to resource
var config = try manager.addResource(GameConfig, .{
    .width = 1920,
    .height = 1080,
    .fps = 60,
});

// Modify resource
config.fps = 120;

// Get resource
if (manager.getResource(GameConfig)) |cfg| {
    std.debug.print("FPS: {d}\n", .{cfg.fps});
}

// Check if resource exists
const has_config = manager.hasResource(GameConfig);

// Remove resource
manager.removeResource(GameConfig);

// List all resource type hashes
var types = manager.listResourceTypeHashes();
defer types.deinit();
```

### Events

Events allow decoupled communication between systems.

```zig
const CollisionEvent = struct {
    entity_a: zevy_ecs.Entity,
    entity_b: zevy_ecs.Entity,
};

// System that writes events
fn collisionDetectionSystem(
    writer: zevy_ecs.EventWriter(CollisionEvent), // will add EventStore resource for CollisionEvent if not present
) void {
    // Emit event
    writer.write(.{
        .entity_a = .{ .id = 1, .generation = 0 },
        .entity_b = .{ .id = 2, .generation = 0 },
    });
}

// System that reads events
fn collisionResponseSystem(
    reader: zevy_ecs.EventReader(CollisionEvent), // will add EventStore resource for CollisionEvent if not present
) void {
    while (reader.read()) |event| {
        std.debug.print("Collision between {d} and {d}\n",
            .{ event.data.entity_a.id, event.data.entity_b.id });
            event.handled = true; // Mark handled if this event type won't be processed again in another system
    }
}

// Initialize event store for your event types
pub fn main() !void {
    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create event store
    var collision_events = zevy_ecs.EventStore(CollisionEvent).init(allocator, 64);
    defer collision_events.deinit();

    _ = try manager.addResource(zevy_ecs.EventStore(CollisionEvent), collision_events);

    // Run systems...

    // recommended to discard unhandled events later on
    collision_events.discardUnhandled();
}
```

### Component Lifecycle Tracking

`OnAdded` and `OnRemoved` system parameters allow you to react to component changes in real-time.

```zig
const Position = struct { x: f32, y: f32 };

// System that reacts to Position components being added
fn onPositionAddedSystem(
    added: zevy_ecs.OnAdded(Position),
) void {
    for (added.iter()) |item| {
        std.debug.print("Entity {d} gained Position at ({d}, {d})\n",
            .{ item.entity.id, item.comp.x, item.comp.y });
    }
}

// System that reacts to Position components being removed
fn onPositionRemovedSystem(
    removed: zevy_ecs.OnRemoved(Position),
) void {
    for (removed.iter()) |entity| {
        std.debug.print("Entity {d} lost Position component\n", .{entity.id});
    }
}

// Both can be used together
fn positionChangeSystem(
    added: zevy_ecs.OnAdded(Position),
    removed: zevy_ecs.OnRemoved(Position),
) void {
    // Track new entities with Position
    for (added.iter()) |item| {
        std.debug.print("Added: {d}\n", .{item.entity.id});
    }

    // Track entities losing Position
    for (removed.iter()) |entity| {
        std.debug.print("Removed: {d}\n", .{entity.id});
    }
}

pub fn main() !void {
    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create and cache systems
    const added_system = manager.cacheSystem(zevy_ecs.ToSystem(onPositionAddedSystem, zevy_ecs.DefaultParamRegistry));
    const removed_system = manager.cacheSystem(zevy_ecs.ToSystem(onPositionRemovedSystem, zevy_ecs.DefaultParamRegistry));

    // Add/remove components to trigger the systems
    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, .{ .x = 0, .y = 0 });

    try manager.runSystem(added_system);    // Prints: "Entity X gained Position..."

    try manager.removeComponent(entity, Position);

    try manager.runSystem(removed_system);  // Prints: "Entity X lost Position..."
}
```

### Relations

Relations allow you to create connections between entities with minimal memory overhead. The `RelationManager` is automatically initialized as a built-in resource when the ECS Manager is created, since entities and relations go hand-in-hand. The system uses an adaptive hybrid approach where relations can be either component-based (minimal overhead for sparse relations) or indexed (for efficient traversal of many relations).  Relationships can only be created using `RelationManager` or via the system param `Relations` (which is a alias for `RelationsManager`).

#### Relation Types

```zig
const zevy_ecs = @import("zevy_ecs");

// Non-indexed relation
const AttachedTo = struct {};

// Indexed exclusive relation (parent-child hierarchy)
const Child = struct {
    pub const relation_config = zevy_ecs.relations.RelationConfig{
        .indexed = true,    // Creates bidirectional indices
        .exclusive = true,  // Entity can only have one parent
    };
};

// Indexed non-exclusive relation (entity can own multiple items)
const Owns = struct {
    pub const relation_config = zevy_ecs.relations.RelationConfig{
        .indexed = true,
        .exclusive = false,
    };
};

// Relation with custom data
const SocketData = struct {
    socket_name: []const u8,
};
```

#### Basic Usage

```zig
// Relations can be added in two ways:
// 1. Directly via manager.addComponent() - automatically syncs to RelationManager
// 2. Via RelationManager API - explicitly manages relations

fn setupHierarchy(
    commands: zevy_ecs.Commands,
    relations: zevy_ecs.Relations,
) !void {
    const ecs = commands.manager();

    // Create entities using deferred creation
    var parent_cmds = try commands.create();
    _ = try parent_cmds.add(Transform, .{});
    try parent_cmds.flush();
    const parent = parent_cmds.entity();

    var child_cmds = try commands.create();
    _ = try child_cmds.add(Transform, .{});
    try child_cmds.flush();
    const child = child_cmds.entity();

    // Use RelationManager API
    try relations.add(ecs, child, parent, Child);

    // Query children of parent
    const children = relations.getChildren(parent, Child);
    for (children) |child| {
        std.debug.print("Child: {d}\n", .{child.id});
    }

    // Get parent of child
    if (try relations.getParent(ecs, child, Child)) |p| {
        std.debug.print("Parent: {d}\n", .{p.id});
    }

    // Check if relation exists
    if (try relations.has(ecs, child, parent, Child)) {
        std.debug.print("Child1 has parent relation\n", .{});
    }

    // Remove relation
    try relations.remove(ecs, child, parent, Child);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    const setup_system = manager.cacheSystem(zevy_ecs.ToSystem(setupHierarchy, zevy_ecs.DefaultParamRegistry));
    try manager.runSystem(setup_system);
}
```

#### Relations with Data

```zig
fn attachWeapon(
    commands: zevy_ecs.Commands,
    relations: zevy_ecs.Relations,
) !void {
    const ecs = commands.manager();

    // Create entities using deferred creation
    var char_cmds = try commands.create();
    _ = try char_cmds.add(Transform, .{});
    try char_cmds.flush();
    const character = char_cmds.entity();

    var weapon_cmds = try commands.create();
    _ = try weapon_cmds.add(Transform, .{});
    try weapon_cmds.flush();
    const weapon = weapon_cmds.entity();

    // Method 1: Add relation with custom data using RelationManager API
    try relations.addWithData(
        ecs,
        weapon,
        character,
        SocketData,
        .{ .socket_name = "hand_socket" },
    );

    // Method 2: Add relation component directly (auto-syncs)
    // try ecs.addComponent(weapon, zevy_ecs.relations.Relation(SocketData),
    //     .{ .target = character, .data = .{ .socket_name = "hand_socket" } });

    // Access relation data via component
    if (try ecs.getComponent(weapon, zevy_ecs.relations.Relation(SocketData))) |rel| {
        std.debug.print("Socket: {s}\n", .{rel.data.socket_name});
        std.debug.print("Attached to: {d}\n", .{rel.target.id});
    }
}
```

#### Non-Exclusive Relations

```zig
// Entity can own multiple items
fn setupInventory(
    commands: zevy_ecs.Commands,
    relations: zevy_ecs.Relations,
) !void {
    const ecs = commands.manager();

    // Create entities using deferred creation
    var player_cmds = try commands.create();
    _ = try player_cmds.add(Transform, .{});
    try player_cmds.flush();
    const player = player_cmds.entity();

    var sword_cmds = try commands.create();
    _ = try sword_cmds.add(Transform, .{});
    try sword_cmds.flush();
    const sword = sword_cmds.entity();

    var shield_cmds = try commands.create();
    _ = try shield_cmds.add(Transform, .{});
    try shield_cmds.flush();
    const shield = shield_cmds.entity();

    var potion_cmds = try commands.create();
    _ = try potion_cmds.add(Transform, .{});
    try potion_cmds.flush();
    const potion = potion_cmds.entity();

    // Add non-exclusive relations (entity can have multiple)
    try relations.add(ecs, player, sword, Owns);
    try relations.add(ecs, player, shield, Owns);
    try relations.add(ecs, player, potion, Owns);

    // Get all owned items
    const items = relations.getParents(player, Owns);
    std.debug.print("Player owns {d} items\n", .{items.len});
}
```

## Advanced Features

### System Composition

A few small helpers are provided for composing systems succinctly:

- **pipe**: Runs a `first` system and injects its return value as the first argument to a `second` system. Useful for producer→consumer flows; errors returned by the first system propagate.
- **runIf**: Runs the `system` only when `predicate` returns `true`. Compile-time enforced: `predicate` must return `bool`.
- **chain**: Accepts a **comptime array** of systems and runs them sequentially as one system. The argument must be a comptime array literal and cannot be empty.

```zig
// Systems with injected arguments
fn damageSystemWithMultiplier(
    multiplier: f32,
    query: zevy_ecs.Query(struct { health: Health }),
) void {
    while (query.next()) |item| {
        item.health.current = @intFromFloat(
            @as(f32, @floatFromInt(item.health.current)) * multiplier
        );
    }
}

// Create system with arguments
const system = zevy_ecs.ToSystemWithArgs(
    damageSystemWithMultiplier,
    .{0.5}, // multiplier = 0.5
    zevy_ecs.DefaultParamRegistry,
);

try system.run(&manager, system.ctx);
```

### Custom System Registries

You can create custom system parameter types by implementing `matches`, `apply`, and optional `deinit`, then merge them with the default registry. Below is an example of a custom system parameter that combines multiple built-in parameters.

```zig
const zevy_ecs = @import("zevy_ecs");
const params = zevy_ecs.params;
const param_systems = zevy_ecs.params.systems;

const ComponentA = struct { a: i32 };
const ComponentB = struct { b: u32 };

pub const ComplexType = struct {
    /// Unfortunately with the way zig handles anonymous structs we need to define this separately
    pub const IncludeTypes = struct { a: ComponentA, b: ComponentB };
    query: zevy_ecs.Query(IncludeTypes),
    res: *params.Res(i32),
    local: *params.Local(u64),
};

const CustomComplexParam = struct {
    pub fn matches(comptime T: type) bool {
        const Base = switch (@typeInfo(T)) {
            .pointer => |pointer_info| pointer_info.child,
            else => T,
        };
        const ti = @typeInfo(Base);
        return ti == .@"struct" and @hasField(Base, "query") and @hasField(Base, "res") and @hasField(Base, "local");
    }
    pub fn apply(e: *zevy_ecs.Manager, comptime T: type) anyerror!T {
        const query_val = e.query(ComplexType.IncludeTypes);
        const res_value = try param_systems.ResourceSystemParam.apply(e, *params.Res(i32));
        const local_ptr = try param_systems.LocalSystemParam.apply(e, *params.Local(u64));
        return T{
            .query = query_val,
            .res = res_value,
            .local = local_ptr,
        };
    }

    pub fn deinit(e: *zevy_ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        const complex: *T = @ptrCast(@alignCast(ptr));
        complex.query.deinit();
        param_systems.ResourceSystemParam.deinit(e, @ptrCast(complex.res), *params.Res(i32));
    }
};

const CustomParamRegistry = zevy_ecs.MergedSystemParamRegistry(.{
    zevy_ecs.DefaultParamRegistry,
    CustomComplexParam,
});
```

### Serialization

zevy_ecs provides flexible component, resource, and entity serialization through `ComponentInstance`, `ResourceSnapshot`, `EntityInstance`, `ComponentWriter`, and `ComponentReader`.

#### Basic Component Serialization

```zig
const Position = struct { x: f32, y: f32 };

// Create component instance
const pos = Position{ .x = 10.0, .y = 20.0 };
const comp = zevy_ecs.serialize.ComponentInstance.from(Position, &pos);

// Serialize to writer
var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
defer writer_alloc.deinit();
try comp.writeTo(&writer_alloc.writer);
const buffer = try writer_alloc.toOwnedSlice();
defer allocator.free(buffer);

// Deserialize from reader
var reader = std.Io.Reader.fixed(buffer);
const read_comp = try zevy_ecs.serialize.ComponentInstance.readFrom(&reader, allocator);
defer allocator.free(read_comp.data);

// Access typed data
if (read_comp.as(Position)) |read_pos| {
    std.debug.print("Position: ({d}, {d})\n", .{ read_pos.x, read_pos.y });
}
```

#### Resource Serialization

`ResourceSnapshot` captures a specific resource type and restores it later.
Deserialization writes into resources that are already registered in the target manager; if a resource is missing, restoration fails with `error.ResourceNotFound`.

```zig
const GameConfig = struct {
    width: u32,
    height: u32,
    fullscreen: bool,
};

const Score = struct { value: i32 };

_ = try manager.addResource(GameConfig, .{
    .width = 1920,
    .height = 1080,
    .fullscreen = true,
});
_ = try manager.addResource(Score, .{ .value = 42 });

const config_snapshot = try zevy_ecs.serialize.ResourceSnapshot.fromManager(
    allocator,
    &manager,
    GameConfig,
);
defer config_snapshot.deinit(allocator);

const score_snapshot = try zevy_ecs.serialize.ResourceSnapshot.fromManager(
    allocator,
    &manager,
    Score,
);
defer score_snapshot.deinit(allocator);

var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
defer writer_alloc.deinit();

try config_snapshot.writeTo(&writer_alloc.writer);
try score_snapshot.writeTo(&writer_alloc.writer);

const buffer = try writer_alloc.toOwnedSlice();
defer allocator.free(buffer);

var reader = std.Io.Reader.fixed(buffer);
var restored_config = try zevy_ecs.serialize.ResourceSnapshot.readFrom(&reader, allocator);
defer restored_config.deinit(allocator);

var restored_score = try zevy_ecs.serialize.ResourceSnapshot.readFrom(&reader, allocator);
defer restored_score.deinit(allocator);

// Target resources must already exist before restore.
_ = try manager.addResource(GameConfig, .{ .width = 0, .height = 0, .fullscreen = false });
_ = try manager.addResource(Score, .{ .value = 0 });

try restored_config.toManager(&manager);
try restored_score.toManager(&manager);
```

`ResourceSnapshot` performs a raw byte copy, so it is best suited for POD-style resource types.

#### Using ComponentWriter

`ComponentWriter` provides a convenient interface for writing multiple components to a stream.

```zig
const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };

// Create an entity with components
const entity = manager.create(.{
    Position{ .x = 10.0, .y = 20.0 },
    Velocity{ .dx = 0.5, .dy = -0.3 },
});

// Get all components from the entity
const components = try manager.getAllComponents(allocator, entity);
defer allocator.free(components);

// Serialize all components to a buffer
var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
defer writer_alloc.deinit();

var writer = zevy_ecs.serialize.ComponentWriter.init(&writer_alloc.writer);
try writer.writeComponents(components);

const buffer = try writer_alloc.toOwnedSlice();
defer allocator.free(buffer);
```

#### Using ComponentReader

`ComponentReader` provides methods for reading components from a stream with automatic memory management helpers.

```zig
// Deserialize components from buffer
var reader = std.Io.Reader.fixed(buffer);
var component_reader = zevy_ecs.serialize.ComponentReader.init(&reader);

const components = try component_reader.readComponents(allocator);
defer component_reader.freeComponents(allocator, components);

// Access the typed data
for (components) |comp| {
    if (comp.as(Position)) |pos| {
        std.debug.print("Position: ({d}, {d})\n", .{ pos.x, pos.y });
    } else if (comp.as(Velocity)) |vel| {
        std.debug.print("Velocity: ({d}, {d})\n", .{ vel.dx, vel.dy });
    }
}
```

#### Entity Serialization

`EntityInstance` provides complete entity serialization including all components.

```zig
// Create an entity with multiple components
const entity = manager.create(.{
    Position{ .x = 5.0, .y = 10.0 },
    Velocity{ .dx = 1.0, .dy = 2.0 },
    Health{ .value = 100 },
});

// Convert entity to EntityInstance (owns component data copies)
const entity_instance = try zevy_ecs.serialize.EntityInstance.fromEntity(allocator, &manager, entity);
defer entity_instance.deinit(allocator);

// Serialize to buffer
var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
defer writer_alloc.deinit();

try entity_instance.writeTo(&writer_alloc.writer);

const buffer = try writer_alloc.toOwnedSlice();
defer allocator.free(buffer);

// Deserialize from buffer
var reader = std.Io.Reader.fixed(buffer);
const restored_instance = try zevy_ecs.serialize.EntityInstance.readFrom(&reader, allocator);
defer restored_instance.deinit(allocator);

// Create a new entity from the restored data
const new_entity = try restored_instance.toEntity(&manager);
```

#### Batch Entity Serialization

```zig
// Serialize multiple entities
var writer_alloc: std.Io.Writer.Allocating = .init(allocator);
defer writer_alloc.deinit();
const writer = &writer_alloc.writer;

const entities = [_]zevy_ecs.Entity{ entity1, entity2, entity3 };
try writer.writeInt(usize, entities.len, .little);

for (entities) |entity| {
    const instance = try zevy_ecs.serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer instance.deinit(allocator);
    try instance.writeTo(writer);
}

const buffer = try writer_alloc.toOwnedSlice();
defer allocator.free(buffer);

// Deserialize multiple entities
var reader = std.Io.Reader.fixed(buffer);

const count = try reader.takeInt(usize, .little);
var i: usize = 0;
while (i < count) : (i += 1) {
    const restored = try zevy_ecs.serialize.EntityInstance.readFrom(&reader, allocator);
    defer restored.deinit(allocator);
    _ = try restored.toEntity(&manager);
}
```

### Plugin System

The plugin system provides a modular way to organize and initialize features in your application. Plugins can register systems, resources, and perform setup tasks in a reusable manner.

If you want plugin interface validation errors to report the registration site, use `plugin_manager.addAt(PluginType, plugin, @src())` or `plugin_manager.addBundleAt(BundleType, bundle, @src())`.

#### Basic Plugin Usage

```zig
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const zevy_plugin = @import("zevy_ecs_plugin");

// Define a plugin with state
const PhysicsPlugin = struct {
    gravity: f32,

    pub fn build(self: *@This(), manager: *zevy_ecs.Manager, plugins: *zevy_ecs.PluginManager) !void {
        // Add resources
        _ = try manager.addResource(f32, self.gravity);

        // Register systems, setup state, etc.
        // check if required plugins are loaded
    }
};

// Or use FnPlugin for simple stateless plugins
const InputPlugin = zevy_plugin.FnPlugin("Input", struct {
    fn build(manager: *zevy_ecs.Manager, plugins: *zevy_ecs.PluginManager) !void {
        // Setup input event handling using Scheduler
        const InputEvent = struct { key: u32 };
        const scheduler = manager.getResource(zevy_ecs.Scheduler) orelse return error.SchedulerNotFound;
        try scheduler.registerEvent(manager, InputEvent);
    }
}.build);

// maybe one day Zig will support lambda funcs 🤞

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create scheduler and add as resource so plugins can access it
    const scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();
    const sch_res = try manager.addResource(zevy_ecs.Scheduler, scheduler);

    // Create plugin manager
    var plugin_manager = zevy_plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();

    // Add plugins
    try plugin_manager.add(PhysicsPlugin, .{ .gravity = 9.8 });
    try plugin_manager.add(InputPlugin, .{});

    // Build all plugins (calls build on each)
    try plugin_manager.build(&manager);

    // Now use the ECS with initialized plugins
    const gravity = manager.getResource(f32).?;
    std.debug.print("Gravity: {d}\n", .{gravity.*});
}
```

#### Creating Reusable Plugins

```zig
const zevy_ecs = @import("zevy_ecs");

pub const RenderPlugin = struct {
    width: u32,
    height: u32,

    pub fn build(self: *@This(), manager: *zevy_ecs.Manager, plugins: *zevy_ecs.PluginManager) !void {
        // Add window config resource
        const WindowConfig = struct { width: u32, height: u32 };
        _ = try manager.addResource(WindowConfig, .{
            .width = self.width,
            .height = self.height,
        });

        // Register render systems in a scheduler if available
        // Cache systems, setup render resources, etc.
    }

    pub fn deinit(self: *@This(), manager: *zevy_ecs.Manager) void {
        // Optional: cleanup plugin-specific resources
        _ = self;
        _ = manager; // Use manager.allocator or store a custom allocator as a field in the plugin.
    }
};
```

### Scheduler

The Scheduler manages system execution order through stages. Systems are organized into predefined or custom stages that run in a specific order, allowing you to control the flow of your game loop or application.

> [!NOTE]
> The Scheduler runs stage work internally using `io.async`. If you need a specific set of systems to run synchronously and in-order within a stage, wrap them with `chain(...)` and register that chained system instead of registering those systems separately.

#### Predefined Stages

zevy_ecs comes with the following predefined stages (in execution order) but these are not required and you can create your own custom stages with any priority:

- `Stages.PreStartup` - Runs before startup initialization
- `Stages.Startup` - Initial setup and initialization
- `Stages.First` - First stage of the main loop
- `Stages.PreUpdate` - Before main update logic
- `Stages.Update` - Main game/app logic
- `Stages.PostUpdate` - After main update logic
- `Stages.PreDraw` - Before rendering
- `Stages.Draw` - Rendering stage
- `Stages.PostDraw` - After rendering
- `Stages.StateTransition` - Process state transitions
- `Stages.StateOnExit` - Systems that run when exiting states
- `Stages.StateOnEnter` - Systems that run when entering states
- `Stages.StateUpdate` - Systems that run while in states
- `Stages.Last` - Final stage of the loop
- `Stages.Exit` - Cleanup and shutdown

#### Basic Usage

```zig
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Add systems to stages using Stage() function
    scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update), movementSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Draw), renderSystem, zevy_ecs.DefaultParamRegistry);

    // Run all systems in a specific stage
    try scheduler.runStage(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update));

    // Run all systems in a range of stages
    try scheduler.runStages(&manager, zevy_ecs.Stage(zevy_ecs.Stages.First), zevy_ecs.Stage(zevy_ecs.Stages.Last));
}

fn movementSystem(
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }),
) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}

fn renderSystem(
    query: zevy_ecs.Query(struct { pos: Position }),
) void {
    while (query.next()) |item| {
        std.debug.print("Render at ({d}, {d})\n", .{ item.pos.x, item.pos.y });
    }
}
```

#### Creating Custom Stages

Stages are fully extensible! You can create custom stage types with explicit priorities for controlled ordering, or without priorities for hash-based IDs.

```zig
const zevy_ecs = @import("zevy_ecs");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Define custom stages with explicit priorities for controlled ordering
    const CustomStages = struct {
        pub const Physics = struct {
            pub const priority: zevy_ecs.StageId = 350_000; // Between Update (300,000) and PostUpdate (400,000)
        };
        pub const AI = struct {
            pub const priority: zevy_ecs.StageId = 360_000;
        };
        pub const Animation = struct {
            pub const priority: zevy_ecs.StageId = 370_000;
        };
    };

    // Or define custom stages without priorities (get hash-based IDs in 2M+ range)
    const HashStages = struct {
        pub const CustomLogic = struct {}; // Gets unique hash-based ID
        pub const SpecialEffects = struct {}; // Different hash-based ID
    };

    // Add systems to custom stages using Stage() function
    scheduler.addSystem(&manager, zevy_ecs.Stage(CustomStages.Physics), physicsSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&manager, zevy_ecs.Stage(CustomStages.AI), aiSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&manager, zevy_ecs.Stage(HashStages.CustomLogic), customSystem, zevy_ecs.DefaultParamRegistry);

    // Run stages in a range (includes all custom stages in the range)
    try scheduler.runStages(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update), zevy_ecs.Stage(zevy_ecs.Stages.PostUpdate));
}

fn physicsSystem(
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }),
) void {
    while (query.next()) |item| {
        item.vel.dy += 9.8; // gravity
    }
}

fn aiSystem(
    query: zevy_ecs.Query(struct { pos: Position }),
) void {
    // AI logic here
    _ = query;
}

fn customSystem() void {
    // Custom logic here
}
```

#### State Management

zevy_ecs provides powerful enum-based state management with automatic state transitions and lifecycle hooks.

```zig
const zevy_ecs = @import("zevy_ecs");

const GameState = enum {
    MainMenu,
    Playing,
    Paused,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Register state type (automatically adds StateManager resource)
    try scheduler.registerState(&manager, GameState);

    // Set initial state (or use NextState in a startup system)
    try scheduler.transitionTo(&manager, GameState, .MainMenu);

    // Add state-specific systems - pass raw functions and param registry
    // Systems run when entering/exiting states
    scheduler.addSystem(&manager, zevy_ecs.OnEnter(GameState.Playing), gameplaySystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&manager, zevy_ecs.OnExit(GameState.Playing), cleanupSystem, zevy_ecs.DefaultParamRegistry);

    // Systems run while in a specific state (call manually in game loop)
    scheduler.addSystem(&manager, zevy_ecs.InState(GameState.MainMenu), menuSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(&manager, zevy_ecs.InState(GameState.Playing), gameplaySystem, zevy_ecs.DefaultParamRegistry);

    // In your game loop, run systems for the active state
    try scheduler.runActiveStateSystems(&manager, GameState);
}

fn menuSystem(
    state: zevy_ecs.State(GameState),
    next: *zevy_ecs.NextState(GameState),
) void {
    if (state.isActive(.MainMenu)) {
        // Handle menu input
        // Transition to playing when user presses start
        next.set(.Playing); // Immediate transition - triggers OnExit/OnEnter
    }
}

fn gameplaySystem(
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }),
) void {
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}
```

#### Event Registration

The Scheduler can automatically set up event handling with cleanup:

```zig
const zevy_ecs = @import("zevy_ecs");

const InputEvent = struct {
    key: u32,
    pressed: bool,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Register event type - creates EventStore resource and adds cleanup system
    try scheduler.registerEvent(&manager, InputEvent);

    // Add system that writes events
    scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.First), inputSystem, zevy_ecs.DefaultParamRegistry);

    // Add system that reads events
    scheduler.addSystem(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Update), inputHandlerSystem, zevy_ecs.DefaultParamRegistry);

    // Run the stages - cleanup happens automatically in Last stage
    try scheduler.runStages(&manager, zevy_ecs.Stage(zevy_ecs.Stages.First), zevy_ecs.Stage(zevy_ecs.Stages.Last));
}

fn inputSystem(
    writer: zevy_ecs.EventWriter(InputEvent),
) void {
    writer.write(.{ .key = 32, .pressed = true }); // Space key pressed
}

fn inputHandlerSystem(
    reader: zevy_ecs.EventReader(InputEvent),
) void {
    while (reader.read()) |event| {
        std.debug.print("Key {d} pressed: {}\n", .{ event.data.key, event.data.pressed });
        event.handled = true;
    }
}
```

#### Getting Stage Information

You can inspect the scheduler's current configuration:

```zig
const zevy_ecs = @import("zevy_ecs");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Get information about all stages
    var stage_info = scheduler.getStageInfo(allocator);
    defer stage_info.deinit(allocator);

    for (stage_info.items) |info| {
        std.debug.print("Stage {d}: {d} systems\n", .{ info.stage, info.system_count });
    }
}
```

## Performance

zevy_ecs includes a simple benchmarking utility to measure the performance of various operations. Below are some benchmark results for entity creation and system execution.

### Benchmarks

This now outperforms [Bevy's ECS](https://bevy.org/).

#### 4GHz CPU, --release=fast

See [BENCHMARK.md](BENCHMARK.md) for detailed benchmark results.

## Dependencies
- [zevy-reflect](https://github.com/captkirk88/zevy-reflect) - Reflection utilities for Zig.
- [zevy-mem](https://github.com/captkirk88/zevy-mem) - Memory allocators and utilities for Zig.

## Contributing

Contributions are welcome!
Please describe issues in detail. Bug reports, feature requests, etc. Pull requests are also welcome.

## License
MIT
See [LICENSE](LICENSE) for more details.