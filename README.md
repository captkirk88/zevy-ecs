# zevy_ecs

zevy_ecs is a high-performance, archetype-based Entity-Component-System (ECS) framework written in Zig. It provides a type-safe, efficient way to manage entities, components, systems, resources, and events in your applications.

[license]: https://img.shields.io/github/license/captkirk88/zevy-ecs?style=for-the-badge&logo=opensourcehardware&label=License&logoColor=C0CAF5&labelColor=414868&color=8c73cc

[![][license]](https://github.com/captkirk88/zevy-ecs/blob/main/LICENSE)

## Features

- **Archetype-based storage**: Efficiently groups entities with the same component combinations for cache-friendly iteration
- **Type-safe queries**: Compile-time validated component queries with include/exclude filters and optional components
- **Flexible system parameters**: Built-in support for Query, Res (resources), Local (per-system state), State/NextState, EventReader/EventWriter, Relations
- **Relationship Support** : Manage entity relationships with minimal overhead using the Relations system parameter
- **Resource management**: Global state accessible across systems with automatic cleanup
- **Event system**: Built-in event queue with filtering and handling capabilities in a circular buffer
- **Batch operations**: High-performance batch entity creation
- **Component serialization**: Built-in support for serializing/deserializing components and entities
- **Extensible parameter system**: Create custom system parameters by implementing `analyze` and `apply` functions
- **Zero runtime overhead**: All parameter resolution happens at compile time

## Table of Contents

- [Quick Start](#quick-start)
  - [Requirements](#requirements)
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
  - [Serialization](#component-serialization)
    - [Basic Component Serialization](#basic-component-serialization)
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
- [Contributing](#contributing)

## Quick Start

### Requirements

- Zig 0.15.1

> [!NOTE]
> Zig 0.15.2 compatible but not required.

### Installation

```zig
zig fetch --save git+https://github.com/captkirk88/zevy_ecs
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
exe.root_module.addImport("zevy_ecs_plugin", zevy_ecs.module("plugins"));
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
        .{},
    );

    // var query = manager.query(.{Position, Velocity}, struct {}); // Alternative syntax

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
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(
        struct { pos: Position, vel: Velocity }, // Include components
        .{}, // No exclusions
    ),
) void {
    _ = manager;
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

Components are plain Zig structs that hold data. Any type can be a component.

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
// Query entities with Position and Velocity
var query = manager.query(
    struct { pos: Position, vel: Velocity },
    struct {}, // No exclusions
);

while (query.next()) |item| {
    // Mutable access to components
    item.pos.x += item.vel.dx;
    item.pos.y += item.vel.dy;
}

// Query with exclusions (entities that DON'T have Armor)
var no_armor_query = manager.query(
    struct { health: Health },
    struct { armor: Armor },
);

// Query with optional components
var optional_query = manager.query(
    struct {
        pos: Position,
        vel: ?Velocity,  // Optional - may be null
    },
    struct {},
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
    struct {},
);while (entity_query.next()) |item| {
    std.debug.print("Entity {d} at ({d}, {d})\n",
        .{ item.entity.id, item.pos.x, item.pos.y });
}
```

### Systems

Systems are functions that operate on entities and resources. They use a parameter injection system for automatic dependency resolution.

```zig
const DeltaTime = struct { value: f32 };

// System function - parameters are automatically resolved
fn movementSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(
        struct { pos: Position, vel: Velocity },
        struct {},
    ),
) void {
    _ = manager;
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}

// System with resources
fn damageSystem(
    manager: *zevy_ecs.Manager,
    dt: zevy_ecs.Res(DeltaTime),
    query: zevy_ecs.Query(
        struct { health: Health },
        struct {},
    ),
) void {
    _ = manager;
    while (query.next()) |item| {
        if (item.health.current > 0) {
            item.health.current -= 1;
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

### System Parameters

Systems can request various parameters that are automatically injected:

- **`*Manager`**: Reference to the ECS manager (required first parameter)
- **`Query(Include, Exclude)`**: Query entities with specific components
- **`Res(T)`**: Access to a global resource of type T
- **`Local(T)`**: Per-system persistent local state
- **`State(T)`**: Read-only access to check the current state (where T is an enum)
- **`NextState(T)`**: Trigger state transitions (where T is an enum)
- **`EventReader(T)`**: Read events of type T
- **`EventWriter(T)`**: Write events of type T
- **`OnAdded(T)`**: Iterate over entities that had component T added since the last system run
- **`OnRemoved(T)`**: Iterate over entities from which component T was removed since the last system run
- **`*Relations`**: Access to the RelationManager for entity relationships

- More can be added by implementing custom parameter types. (see [Custom System Registries](#custom-system-registries))

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

// List all resources
var types = manager.listResourceTypes();
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
    manager: *zevy_ecs.Manager,
    writer: zevy_ecs.EventWriter(CollisionEvent), // will add EventStore resource for CollisionEvent if not present
) void {
    _ = manager;
    // Emit event
    writer.write(.{
        .entity_a = .{ .id = 1, .generation = 0 },
        .entity_b = .{ .id = 2, .generation = 0 },
    });
}

// System that reads events
fn collisionResponseSystem(
    manager: *zevy_ecs.Manager,
    reader: zevy_ecs.EventReader(CollisionEvent), // will add EventStore resource for CollisionEvent if not present
) void {
    _ = manager;
    while (reader.read()) |event| {
        std.debug.print("Collision between {d} and {d}\n",
            .{ event.data.entity_a.id, event.data.entity_b.id });
            event.handled = true; // Mark handled if this event type won't be processed again in another system
            // Note: Alternatively, you can call reader.markHandled() after processing all events
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
    manager: *zevy_ecs.Manager,
    added: zevy_ecs.OnAdded(Position),
) void {
    _ = manager;
    for (added.iter()) |item| {
        std.debug.print("Entity {d} gained Position at ({d}, {d})\n",
            .{ item.entity.id, item.comp.x, item.comp.y });
    }
}

// System that reacts to Position components being removed
fn onPositionRemovedSystem(
    manager: *zevy_ecs.Manager,
    removed: zevy_ecs.OnRemoved(Position),
) void {
    _ = manager;
    for (removed.iter()) |entity| {
        std.debug.print("Entity {d} lost Position component\n", .{entity.id});
    }
}

// Both can be used together
fn positionChangeSystem(
    manager: *zevy_ecs.Manager,
    added: zevy_ecs.OnAdded(Position),
    removed: zevy_ecs.OnRemoved(Position),
) void {
    _ = manager;

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

Relations allow you to create connections between entities with minimal memory overhead. The `RelationManager` is automatically initialized as a built-in resource when the ECS Manager is created, since entities and relations go hand-in-hand. The system uses an adaptive hybrid approach where relations can be either component-based (minimal overhead for sparse relations) or indexed (for efficient traversal of many relations).

Relation components added via `manager.addComponent()` are automatically synced to the RelationManager for indexed relation types.

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
    ecs: *zevy_ecs.Manager,
) !void {
    // RelationManager is automatically available as a resource
    const relations = ecs.getResource(zevy_ecs.relations.RelationManager).?;

    // Create entities
    const parent = ecs.create(.{Transform{}});
    const child1 = ecs.create(.{Transform{}});
    const child2 = ecs.create(.{Transform{}});

    // Method 1: Add relation component directly (auto-syncs to index for indexed types)
    try ecs.addComponent(child1, zevy_ecs.relations.Relation(Child),
        zevy_ecs.relations.Relation(Child).init(parent, .{}));

    // Method 2: Use RelationManager API
    try relations.add(ecs, child2, parent, Child);

    // Query children of parent
    const children = relations.getChildren(parent, Child);
    for (children) |child| {
        std.debug.print("Child: {d}\n", .{child.id});
    }

    // Get parent of child
    if (try relations.getParent(ecs, child1, Child)) |p| {
        std.debug.print("Parent: {d}\n", .{p.id});
    }

    // Check if relation exists
    if (try relations.has(ecs, child1, parent, Child)) {
        std.debug.print("Child1 has parent relation\n", .{});
    }

    // Remove relation
    try relations.remove(ecs, child1, parent, Child);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    // RelationManager is automatically initialized
    try setupHierarchy(&manager);
}
```

#### Relations with Data

```zig
fn attachWeapon(
    ecs: *zevy_ecs.Manager,
) !void {
    const relations = ecs.getResource(zevy_ecs.relations.RelationManager).?;

    const character = ecs.create(.{Transform{}});
    const weapon = ecs.create(.{Transform{}});

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
    ecs: *zevy_ecs.Manager,
) !void {
    const relations = ecs.getResource(zevy_ecs.relations.RelationManager).?;

    const player = ecs.create(.{Transform{}});
    const sword = ecs.create(.{Transform{}});
    const shield = ecs.create(.{Transform{}});
    const potion = ecs.create(.{Transform{}});

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

```zig
// Systems with injected arguments
fn damageSystemWithMultiplier(
    manager: *zevy_ecs.Manager,
    multiplier: f32,
    query: zevy_ecs.Query(struct { health: Health }, .{}),
) void {
    _ = manager;
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

You can create custom system parameter types by implementing the `analyze` and `apply` functions, then merge them with the default registry. Below is an example of a `Local` parameter type that provides per-system persistent state.

```zig
pub const LocalSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and
            @hasField(T, "_value") and
            @hasField(T, "_set") and
            type_info.@"struct".fields.len == 2)
        {
            return type_info.@"struct".fields[0].type;
        } else if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(_: *ecs.Manager, comptime T: type) *systems.Local(T) {
        // Local params need static storage that persists across system calls
        // Each unique type T gets its own static storage
        const static_storage = struct {
            var local: systems.Local(T) = .{ ._value = undefined, ._set = false };
        };
        return &static_storage.local;
    }
};

const CustomParamRegistry = zevy_ecs.mergeSystemParamRegistries(
    zevy_ecs.DefaultParamRegistry,
    .{ LocalSystemParam },
);
```

### Serialization

zevy_ecs provides flexible component and entity serialization through `ComponentInstance`, `EntityInstance`, `ComponentWriter`, and `ComponentReader`.

#### Basic Component Serialization

```zig
const Position = struct { x: f32, y: f32 };

// Create component instance
const pos = Position{ .x = 10.0, .y = 20.0 };
const comp = zevy_ecs.serialize.ComponentInstance.from(Position, &pos);

// Serialize to writer
var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
defer buffer.deinit(allocator);
try comp.writeTo(buffer.writer(allocator).any());

// Deserialize from reader
var fbs = std.io.fixedBufferStream(buffer.items);
const read_comp = try zevy_ecs.serialize.ComponentInstance.readFrom(fbs.reader().any(), allocator);
defer allocator.free(read_comp.data);

// Access typed data
if (read_comp.as(Position)) |read_pos| {
    std.debug.print("Position: ({d}, {d})\n", .{ read_pos.x, read_pos.y });
}
```

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
var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
defer buffer.deinit(allocator);

var writer = zevy_ecs.serialize.ComponentWriter.init(buffer.writer(allocator).any());
try writer.writeComponents(components);
```

#### Using ComponentReader

`ComponentReader` provides methods for reading components from a stream with automatic memory management helpers.

```zig
// Deserialize components from buffer
var fbs = std.io.fixedBufferStream(buffer.items);
var reader = zevy_ecs.serialize.ComponentReader.init(fbs.reader().any());

const components = try reader.readComponents(allocator);
defer reader.freeComponents(allocator, components);

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
var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
defer buffer.deinit(allocator);
try entity_instance.writeTo(buffer.writer(allocator).any());

// Deserialize from buffer
var fbs = std.io.fixedBufferStream(buffer.items);
const restored_instance = try zevy_ecs.serialize.EntityInstance.readFrom(fbs.reader().any(), allocator);
defer restored_instance.deinit(allocator);

// Create a new entity from the restored data
const new_entity = try restored_instance.toEntity(&manager);
```

#### Batch Entity Serialization

```zig
// Serialize multiple entities
var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
defer buffer.deinit(allocator);
const writer = buffer.writer(allocator).any();

const entities = [_]zevy_ecs.Entity{ entity1, entity2, entity3 };
try writer.writeInt(usize, entities.len, .little);

for (entities) |entity| {
    const instance = try zevy_ecs.serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer instance.deinit(allocator);
    try instance.writeTo(writer);
}

// Deserialize multiple entities
var fbs = std.io.fixedBufferStream(buffer.items);
const reader = fbs.reader().any();

const count = try reader.readInt(usize, .little);
var i: usize = 0;
while (i < count) : (i += 1) {
    const restored = try zevy_ecs.serialize.EntityInstance.readFrom(reader, allocator);
    defer restored.deinit(allocator);
    _ = try restored.toEntity(&manager);
}
```

### Plugin System

The plugin system provides a modular way to organize and initialize features in your application. Plugins can register systems, resources, and perform setup tasks in a reusable manner.

#### Basic Plugin Usage

```zig
const std = @import("std");
const zevy_ecs = @import("zevy_ecs");
const zevy_plugin = @import("zevy_ecs_plugin");

// Define a plugin with state
const PhysicsPlugin = struct {
    gravity: f32,

    pub fn build(self: *@This(), manager: *zevy_ecs.Manager) !void {
        // Add resources
        _ = try manager.addResource(f32, self.gravity);

        // Register systems, setup state, etc.
    }
};

// Or use FnPlugin for simple stateless plugins
const InputPlugin = zevy_plugin.FnPlugin("Input", struct {
    fn build(manager: *zevy_ecs.Manager) !void {
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

    pub fn build(self: *@This(), manager: *zevy_ecs.Manager) !void {
        // Add window config resource
        const WindowConfig = struct { width: u32, height: u32 };
        _ = try manager.addResource(WindowConfig, .{
            .width = self.width,
            .height = self.height,
        });

        // Register render systems in a scheduler if available
        // Cache systems, setup render resources, etc.
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        // Optional: cleanup plugin-specific resources
        _ = self;
        _ = allocator;
    }
};
```

### Scheduler

The Scheduler manages system execution order through stages. Systems are organized into predefined or custom stages that run in a specific order, allowing you to control the flow of your game loop or application.

#### Predefined Stages

zevy_ecs comes with the following predefined stages (in execution order):

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
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }, .{}),
) void {
    _ = manager;
    while (query.next()) |item| {
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}

fn renderSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position }, .{}),
) void {
    _ = manager;
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
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }, .{}),
) void {
    _ = manager;
    while (query.next()) |item| {
        item.vel.dy += 9.8; // gravity
    }
}

fn aiSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position }, .{}),
) void {
    _ = manager;
    // AI logic here
    _ = query;
}

fn customSystem(
    manager: *zevy_ecs.Manager,
) void {
    _ = manager;
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
    manager: *zevy_ecs.Manager,
    state: zevy_ecs.State(GameState),
    next: *zevy_ecs.NextState(GameState),
) void {
    _ = manager;
    if (state.isActive(.MainMenu)) {
        // Handle menu input
        // Transition to playing when user presses start
        next.set(.Playing); // Immediate transition - triggers OnExit/OnEnter
    }
}

fn gameplaySystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(struct { pos: Position, vel: Velocity }, .{}),
) void {
    _ = manager;
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
    manager: *zevy_ecs.Manager,
    writer: zevy_ecs.EventWriter(InputEvent),
) void {
    _ = manager;
    writer.write(.{ .key = 32, .pressed = true }); // Space key pressed
}

fn inputHandlerSystem(
    manager: *zevy_ecs.Manager,
    reader: zevy_ecs.EventReader(InputEvent),
) void {
    _ = manager;
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

#### 4GHz CPU, single-threaded, ReleaseFast

#### Creation

| Benchmark               | Operations | Time/op       | Memory/op     | Allocs/op |
| ----------------------- | ---------- | ------------- | ------------- | --------- |
| Create 100 Entities     | 3          | 12.766 us/op  | 13.474 KB/op  | 3/op      |
| Create 1000 Entities    | 3          | 92.066 us/op  | 116.588 KB/op | 8/op      |
| Create 10000 Entities   | 3          | 969.066 us/op | 1.661 MB/op   | 18/op     |
| Create 100000 Entities  | 3          | 6.802 ms/op   | 18.296 MB/op  | 27/op     |
| Create 1000000 Entities | 3          | 70.431 ms/op  | 232.605 MB/op | 39/op     |

#### Batch Creation

| Benchmark               | Operations | Time/op       | Memory/op     | Allocs/op |
| ----------------------- | ---------- | ------------- | ------------- | --------- |
| Create 100 Entities     | 3          | 19.400 us/op  | 13.474 KB/op  | 3/op      |
| Create 1000 Entities    | 3          | 98.566 us/op  | 89.682 KB/op  | 5/op      |
| Create 10000 Entities   | 3          | 566.000 us/op | 1.019 MB/op   | 7/op      |
| Create 100000 Entities  | 3          | 3.687 ms/op   | 12.529 MB/op  | 7/op      |
| Create 1000000 Entities | 3          | 38.133 ms/op  | 144.706 MB/op | 8/op      |

#### Mixed Systems

| Benchmark                         | Operations | Time/op       | Memory/op  | Allocs/op |
| --------------------------------- | ---------- | ------------- | ---------- | --------- |
| Run 7 Systems on 100 Entities     | 3          | 2.166 us/op   | 0.000 B/op | 0/op      |
| Run 7 Systems on 1000 Entities    | 3          | 6.100 us/op   | 0.000 B/op | 0/op      |
| Run 7 Systems on 10000 Entities   | 3          | 53.700 us/op  | 0.000 B/op | 0/op      |
| Run 7 Systems on 100000 Entities  | 3          | 566.933 us/op | 0.000 B/op | 0/op      |
| Run 7 Systems on 1000000 Entities | 3          | 6.032 ms/op   | 0.000 B/op | 0/op      |

#### Relations

| Benchmark                    | Operations | Time/op       | Memory/op  | Allocs/op |
| ---------------------------- | ---------- | ------------- | ---------- | --------- |
| Scene Graph 100 Entities     | 3          | 1.833 us/op   | 0.000 B/op | 0/op      |
| Scene Graph 1000 Entities    | 3          | 5.866 us/op   | 0.000 B/op | 0/op      |
| Scene Graph 10000 Entities   | 3          | 59.633 us/op  | 0.000 B/op | 0/op      |
| Scene Graph 100000 Entities  | 3          | 569.433 us/op | 0.000 B/op | 0/op      |
| Scene Graph 1000000 Entities | 3          | 6.028 ms/op   | 0.000 B/op | 0/op      |

## Contributing

Contributions are welcome!
Please describe issues in detail. Bug reports, feature requests, etc. Pull requests are also welcome.
