# zevy_ecs

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
- [Advanced Features](#advanced-features)
  - [System Composition](#system-composition)
  - [Custom System Registries](#custom-system-registries)
  - [Component Serialization](#component-serialization)
  - [Scheduler](#scheduler)
    - [Predefined Stages](#predefined-stages)
    - [Basic Usage](#basic-usage-1)
    - [Creating Custom Stages](#creating-custom-stages)
    - [State Management](#state-management)
    - [Event Registration](#event-registration)
    - [Getting Stage Information](#getting-stage-information)
- [Performance](#performance)
- [License](#license)
- [Contributing](#contributing)

## Quick Start

## Requirements

- Zig 0.15.1

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

    const move_system = manager.createSystemCached(movementSystem, zevy_ecs.DefaultParamRegistry);
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

    // Create and run system
    var system = manager.createSystem(movementSystem, zevy_ecs.DefaultParamRegistry);
    try system.run(&manager, system.ctx);

    // Or cache and reuse systems
    const handle = manager.createSystemCached(damageSystem, zevy_ecs.DefaultParamRegistry);
    try manager.runSystem(handle);
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

- More can be added by implementing custom parameter types. (see below)

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

### Component Serialization

```zig
const Position = struct { x: f32, y: f32 };

// Create component instance
const pos = Position{ .x = 10.0, .y = 20.0 };
const comp = zevy_ecs.ComponentInstance.from(Position, &pos);

// Serialize to writer
var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
defer buffer.deinit(allocator);
try comp.writeTo(buffer.writer(allocator).any());

// Deserialize from reader
var fbs = std.io.fixedBufferStream(buffer.items);
const read_comp = try zevy_ecs.ComponentInstance.readFrom(fbs.reader().any(), allocator);
defer allocator.free(read_comp.data);

// Access typed data
if (read_comp.as(Position)) |read_pos| {
    std.debug.print("Position: ({d}, {d})\n", .{ read_pos.x, read_pos.y });
}
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

    var scheduler = try zevy_ecs.Scheduler.init(allocator, &manager);
    defer scheduler.deinit();

    // Add systems to stages using Stage() function
    const movement_handle = manager.createSystemCached(movementSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(zevy_ecs.Stages.Update), movement_handle);

    const render_handle = manager.createSystemCached(renderSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(zevy_ecs.Stages.Draw), render_handle);

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

    var scheduler = try zevy_ecs.Scheduler.init(allocator, &manager);
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
    const physics_handle = manager.createSystemCached(physicsSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(CustomStages.Physics), physics_handle);

    const ai_handle = manager.createSystemCached(aiSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(CustomStages.AI), ai_handle);

    const custom_handle = manager.createSystemCached(customSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(HashStages.CustomLogic), custom_handle);

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

    var scheduler = try zevy_ecs.Scheduler.init(allocator, &manager);
    defer scheduler.deinit();

    // Register state type (automatically adds StateManager resource)
    try scheduler.registerState(GameState);

    // Set initial state (or use NextState in a startup system)
    try scheduler.transitionTo(GameState, .MainMenu);

    // Add state-specific systems
    const menu_handle = manager.createSystemCached(menuSystem, zevy_ecs.DefaultParamRegistry);
    const game_handle = manager.createSystemCached(gameplaySystem, zevy_ecs.DefaultParamRegistry);

    // Systems run when entering/exiting states
    scheduler.addSystem(zevy_ecs.OnEnter(GameState.Playing), game_handle);
    scheduler.addSystem(zevy_ecs.OnExit(GameState.Playing), cleanup_handle);

    // Systems run while in a specific state (call manually in game loop)
    scheduler.addSystem(zevy_ecs.InState(GameState.MainMenu), menu_handle);
    scheduler.addSystem(zevy_ecs.InState(GameState.Playing), game_handle);

    // In your game loop, run systems for the active state
    try scheduler.runActiveStateSystems(GameState);
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

    var scheduler = try zevy_ecs.Scheduler.init(allocator, &manager);
    defer scheduler.deinit();

    // Register event type - creates EventStore resource and adds cleanup system
    try scheduler.registerEvent(&manager, InputEvent);

    // Add system that writes events
    const input_handle = manager.createSystemCached(inputSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(zevy_ecs.Stages.First), input_handle);

    // Add system that reads events
    const handler_handle = manager.createSystemCached(inputHandlerSystem, zevy_ecs.DefaultParamRegistry);
    scheduler.addSystem(zevy_ecs.Stage(zevy_ecs.Stages.Update), handler_handle);

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

    var scheduler = try zevy_ecs.Scheduler.init(allocator, &manager);
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

zevy_ecs includes a simple benchmarking utility to measure the performance of various operations. Below are some example benchmark results for entity creation and system execution.

### Benchmarks (4GHz CPU, single-threaded, -Doptimize=ReleaseFast)

| Benchmark               | Operations | Time/op       | Memory/op     | Allocs/op |
| ----------------------- | ---------- | ------------- | ------------- | --------- |
| Create 100 Entities     | 3          | 13.100 us/op  | 13.474 KB/op  | 3/op      |
| Create 1000 Entities    | 3          | 91.066 us/op  | 116.588 KB/op | 8/op      |
| Create 10000 Entities   | 3          | 754.666 us/op | 1.661 MB/op   | 18/op     |
| Create 100000 Entities  | 3          | 6.593 ms/op   | 18.296 MB/op  | 27/op     |
| Create 1000000 Entities | 3          | 71.098 ms/op  | 232.605 MB/op | 39/op     |

| Benchmark                     | Operations | Time/op       | Memory/op     | Allocs/op |
| ----------------------------- | ---------- | ------------- | ------------- | --------- |
| Batch Create 100 Entities     | 3          | 17.333 us/op  | 13.474 KB/op  | 3/op      |
| Batch Create 1000 Entities    | 3          | 74.166 us/op  | 89.682 KB/op  | 5/op      |
| Batch Create 10000 Entities   | 3          | 453.033 us/op | 1.019 MB/op   | 7/op      |
| Batch Create 100000 Entities  | 3          | 3.512 ms/op   | 12.529 MB/op  | 7/op      |
| Batch Create 1000000 Entities | 3          | 34.607 ms/op  | 144.706 MB/op | 8/op      |

| Benchmark                         | Operations | Time/op       | Memory/op  | Allocs/op |
| --------------------------------- | ---------- | ------------- | ---------- | --------- |
| Run 7 Systems on 100 Entities     | 1          | 7.300 us/op   | 0.000 B/op | 0/op      |
| Run 7 Systems on 1000 Entities    | 1          | 6.700 us/op   | 0.000 B/op | 0/op      |
| Run 7 Systems on 10000 Entities   | 1          | 57.500 us/op  | 0.000 B/op | 0/op      |
| Run 7 Systems on 100000 Entities  | 1          | 534.200 us/op | 0.000 B/op | 0/op      |
| Run 7 Systems on 1000000 Entities | 1          | 5.399 ms/op   | 0.000 B/op | 0/op      |

## License

MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome!

- Issues: Please describe in detail.
- Pull Requests: Fork the repository, make your changes, and submit a pull request. Please ensure your code adheres to the existing style and includes tests for new functionality.
