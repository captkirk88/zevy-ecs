# zevy_ecs ECS

zevy_ecs is a high-performance, archetype-based Entity-Component-System (ECS) framework written in Zig. It provides a type-safe, efficient way to manage entities, components, systems, resources, and events in your applications.

## Features

- **Archetype-based storage**: Efficiently groups entities with the same component combinations for cache-friendly iteration
- **Type-safe queries**: Compile-time validated component queries with include/exclude filters and optional components
- **Flexible system parameters**: Systems can request resources, queries, local state, and event readers/writers
- **Resource management**: Global state accessible across systems with automatic cleanup
- **Event system**: Built-in event queue with filtering and handling capabilities
- **Batch operations**: High-performance batch entity creation
- **Component serialization**: Built-in support for serializing/deserializing components
- **Zero runtime overhead**: All parameter resolution happens at compile time

## Quick Start

## Requirements

- Zig 0.15.1 or later

### Installation

```zig
zig fetch --save git+https://github.com/captkirk88/zevy-ecs.git
```

And in your `build.zig`:

```zig
const zevy_ecs = b.dependency("zevy_ecs", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zevy_ecs", zevy_ecs.module("zevy_ecs"));
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
        struct {},
    );

    while (query.next()) |item| {
        // item.pos is *Position, item.vel is *Velocity
        item.pos.x += item.vel.dx;
        item.pos.y += item.vel.dy;
    }
}

fn movementSystem(
    manager: *zevy_ecs.Manager,
    query: zevy_ecs.Query(
        struct { pos: Position, vel: Velocity }, // Include components
        struct {}, // No exclusions
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
);

while (entity_query.next()) |item| {
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

    // Create and run system
    var system = manager.createSystem(movementSystem, zevy_ecs.DefaultRegistry);
    try system.run(&manager, system.ctx);

    // Or cache and reuse systems
    const handle = manager.createSystemCached(damageSystem, zevy_ecs.DefaultRegistry);
    try manager.runSystem(void, handle);
}
```

### System Parameters

Systems can request various parameters that are automatically injected:

- **`*Manager`**: Reference to the ECS manager (required first parameter)
- **`Query(Include, Exclude)`**: Query entities with specific components
- **`Res(T)`**: Access to a global resource of type T
- **`Local(T)`**: Per-system persistent local state
- **`EventReader(T)`**: Read events of type T
- **`EventWriter(T)`**: Write events of type T

### Resources

Resources are global singleton values accessible across systems.

```zig
const GameConfig = struct {
    width: u32,
    height: u32,
    fps: u32,
};

// Add resource
const config = try manager.addResource(GameConfig, .{
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
    writer: zevy_ecs.EventWriter(CollisionEvent),
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
    reader: zevy_ecs.EventReader(CollisionEvent),
) void {
    _ = manager;
    var event_reader = reader;
    while (event_reader.read()) |event| {
        std.debug.print("Collision between {d} and {d}\n",
            .{ event.data.entity_a.id, event.data.entity_b.id });
        event_reader.markHandled();
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

    // recommended to discard unhandled events each frame or adding a system to do so
    collision_events.discardUnhandled();
}
```

## Advanced Features

### System Composition

```zig
// Systems with injected arguments
fn damageSystemWithMultiplier(
    manager: *zevy_ecs.Manager,
    multiplier: f32,
    query: zevy_ecs.Query(struct { health: Health }, struct {}),
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
    zevy_ecs.DefaultRegistry,
);

try system.run(&manager, system.ctx);
```

### Custom System Registries

You can create custom system parameter types by implementing the `analyze` and `apply` functions, then merge them with the default registry.

```zig
const CustomParam = struct {
    pub fn analyze(comptime T: type) ?type {
        // Analyze if this param can handle type T
        // Return T or a related type if yes, null otherwise
    }

    pub fn apply(manager: *zevy_ecs.Manager, comptime T: type) T {
        // Create and return an instance of T
    }
};

const CustomRegistry = zevy_ecs.MergedSystemParamRegistry(.{
    zevy_ecs.DefaultRegistry,
    CustomParam,
});
```

### Component Serialization

```zig
const Position = struct { x: f32, y: f32 };

// Create component instance
const pos = Position{ .x = 10.0, .y = 20.0 };
const comp = zevy_ecs.ComponentInstance.from(Position, &pos);

// Serialize to writer
var buffer = std.ArrayList(u8).initCapacity(allocator, 128);
defer buffer.deinit();
const writer = buffer.writer();
try comp.writeTo(writer);

// Deserialize from reader
var fbs = std.io.fixedBufferStream(buffer.items);
const reader = fbs.reader();
const read_comp = try zevy_ecs.ComponentInstance.readFrom(reader, allocator);
defer allocator.free(read_comp.data);

// Access typed data
if (read_comp.as(Position)) |read_pos| {
    std.debug.print("Position: ({d}, {d})\n", .{ read_pos.x, read_pos.y });
}
```

## Performance

zevy_ecs includes a simple benchmarking utility to measure the performance of various operations. Below are some example benchmark results for entity creation and system execution.

### Entity Creation Benchmarks

| Benchmark               | Operations | Time/op       | Memory/op     |
| ----------------------- | ---------- | ------------- | ------------- |
| Create 100 Entities     | 3          | 14.366 us/op  | 13.474 KB/op  |
| Create 1000 Entities    | 3          | 115.266 us/op | 116.588 KB/op |
| Create 10000 Entities   | 3          | 887.766 us/op | 1.661 MB/op   |
| Create 100000 Entities  | 3          | 6.474 ms/op   | 18.296 MB/op  |
| Create 1000000 Entities | 3          | 68.861 ms/op  | 232.605 MB/op |

| Benchmark                     | Operations | Time/op       | Memory/op     |
| ----------------------------- | ---------- | ------------- | ------------- |
| Batch Create 100 Entities     | 3          | 13.266 us/op  | 13.474 KB/op  |
| Batch Create 1000 Entities    | 3          | 61.766 us/op  | 89.682 KB/op  |
| Batch Create 10000 Entities   | 3          | 364.600 us/op | 1.019 MB/op   |
| Batch Create 100000 Entities  | 3          | 3.295 ms/op   | 12.529 MB/op  |
| Batch Create 1000000 Entities | 3          | 32.735 ms/op  | 144.706 MB/op |

| Benchmark                         | Operations | Time/op       | Memory/op  |
| --------------------------------- | ---------- | ------------- | ---------- |
| Run 7 Systems on 100 Entities     | 1          | 7.100 us/op   | 0.000 B/op |
| Run 7 Systems on 1000 Entities    | 1          | 6.600 us/op   | 0.000 B/op |
| Run 7 Systems on 10000 Entities   | 1          | 52.100 us/op  | 0.000 B/op |
| Run 7 Systems on 100000 Entities  | 1          | 508.800 us/op | 0.000 B/op |
| Run 7 Systems on 1000000 Entities | 1          | 5.448 ms/op   | 0.000 B/op |

## License

MIT

## Contributing

Contributions are welcome!

- Issues: Please describe in detail.
- Pull Requests: Fork the repository, make your changes, and submit a pull request. Please ensure your code adheres to the existing style and includes tests for new functionality.
