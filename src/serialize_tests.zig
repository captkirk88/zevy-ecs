const std = @import("std");
const testing = std.testing;
const ecs = @import("ecs.zig");
const serialize = @import("serialize.zig");

const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };
const Health = struct { value: i32 };

test "ComponentInstance - from and as" {
    const pos = Position{ .x = 10.0, .y = 20.0 };
    const instance = serialize.ComponentInstance.from(Position, &pos);

    try testing.expect(instance.size == @sizeOf(Position));
    try testing.expect(instance.data.len == @sizeOf(Position));

    const retrieved = instance.as(Position);
    try testing.expect(retrieved != null);
    try testing.expectEqual(pos.x, retrieved.?.x);
    try testing.expectEqual(pos.y, retrieved.?.y);

    // Wrong type should return null
    const wrong = instance.as(Velocity);
    try testing.expect(wrong == null);
}

test "ComponentInstance - writeTo and readFrom" {
    const allocator = testing.allocator;

    const pos = Position{ .x = 42.5, .y = 100.25 };
    const original = serialize.ComponentInstance.from(Position, &pos);

    // Write to buffer
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator).any();
    try original.writeTo(writer);

    // Read from buffer
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    const restored = try serialize.ComponentInstance.readFrom(reader, allocator);
    defer allocator.free(restored.data);

    // Verify
    try testing.expectEqual(original.hash, restored.hash);
    try testing.expectEqual(original.size, restored.size);
    try testing.expectEqualSlices(u8, original.data, restored.data);

    const restored_pos = restored.as(Position);
    try testing.expect(restored_pos != null);
    try testing.expectEqual(pos.x, restored_pos.?.x);
    try testing.expectEqual(pos.y, restored_pos.?.y);
}

test "ComponentInstance - readFrom with insufficient data" {
    const allocator = testing.allocator;

    const pos = Position{ .x = 1.0, .y = 2.0 };
    const original = serialize.ComponentInstance.from(Position, &pos);

    // Write to buffer
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator).any();
    try original.writeTo(writer);

    // Truncate the buffer (remove last few bytes)
    buffer.shrinkRetainingCapacity(buffer.items.len - 2);

    // Try to read from truncated buffer - should fail
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    const result = serialize.ComponentInstance.readFrom(reader, allocator);
    try testing.expectError(error.UnexpectedEndOfStream, result);
}

test "EntityInstance - fromEntity and toEntity" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create entity with components
    const entity = manager.create(.{
        Position{ .x = 5.0, .y = 10.0 },
        Velocity{ .dx = 1.0, .dy = 2.0 },
        Health{ .value = 100 },
    });

    // Convert to EntityInstance
    const entity_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer entity_instance.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), entity_instance.components.len);

    // Create new entity from EntityInstance
    const new_entity = try entity_instance.toEntity(&manager);

    // Verify components were copied
    const pos = try manager.getComponent(new_entity, Position);
    try testing.expect(pos != null);
    try testing.expectEqual(@as(f32, 5.0), pos.?.x);
    try testing.expectEqual(@as(f32, 10.0), pos.?.y);

    const vel = try manager.getComponent(new_entity, Velocity);
    try testing.expect(vel != null);
    try testing.expectEqual(@as(f32, 1.0), vel.?.dx);
    try testing.expectEqual(@as(f32, 2.0), vel.?.dy);

    const health = try manager.getComponent(new_entity, Health);
    try testing.expect(health != null);
    try testing.expectEqual(@as(i32, 100), health.?.value);
}

test "EntityInstance - writeTo and readFrom" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create entity
    const entity = manager.create(.{
        Position{ .x = 15.5, .y = 25.5 },
        Health{ .value = 75 },
    });

    // Convert to EntityInstance and write
    const original_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer original_instance.deinit(allocator);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator).any();
    try original_instance.writeTo(writer);

    // Read back EntityInstance
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    const restored_instance = try serialize.EntityInstance.readFrom(reader, allocator);
    defer restored_instance.deinit(allocator);

    try testing.expectEqual(original_instance.components.len, restored_instance.components.len);

    // Create entity from restored instance
    const new_entity = try restored_instance.toEntity(&manager);

    // Verify
    const pos = try manager.getComponent(new_entity, Position);
    try testing.expect(pos != null);
    try testing.expectEqual(@as(f32, 15.5), pos.?.x);
    try testing.expectEqual(@as(f32, 25.5), pos.?.y);

    const health = try manager.getComponent(new_entity, Health);
    try testing.expect(health != null);
    try testing.expectEqual(@as(i32, 75), health.?.value);
}

test "EntityInstance - empty entity" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create empty entity
    const entity = manager.create(.{});

    // Convert to EntityInstance
    const entity_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer entity_instance.deinit(allocator);

    try testing.expectEqual(@as(usize, 0), entity_instance.components.len);

    // Create new entity from empty EntityInstance
    const new_entity = try entity_instance.toEntity(&manager);
    try testing.expect(new_entity.id >= 0);
}

test "EntityInstance - roundtrip serialization" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create multiple entities
    const e1 = manager.create(.{Position{ .x = 1.0, .y = 1.0 }});
    const e2 = manager.create(.{
        Position{ .x = 2.0, .y = 2.0 },
        Velocity{ .dx = 0.5, .dy = 0.5 },
    });
    const e3 = manager.create(.{
        Position{ .x = 3.0, .y = 3.0 },
        Velocity{ .dx = 1.0, .dy = 1.0 },
        Health{ .value = 50 },
    });

    // Serialize all entities
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator).any();

    const entities = [_]ecs.Entity{ e1, e2, e3 };
    try writer.writeInt(usize, entities.len, .little);

    for (entities) |entity| {
        const instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
        defer instance.deinit(allocator);
        try instance.writeTo(writer);
    }

    // Deserialize all entities
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();

    const count = try reader.readInt(usize, .little);
    try testing.expectEqual(@as(usize, 3), count);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const restored = try serialize.EntityInstance.readFrom(reader, allocator);
        defer restored.deinit(allocator);
        _ = try restored.toEntity(&manager);
    }

    // Verify we now have 6 entities total (3 original + 3 restored)
    var query_iter = manager.query(.{Position}, .{});
    var pos_count: usize = 0;
    while (query_iter.next()) |_| {
        pos_count += 1;
    }
    try testing.expectEqual(@as(usize, 6), pos_count);
}

test "Manager - createFromComponents" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create component instances
    const pos = Position{ .x = 99.0, .y = 88.0 };
    const vel = Velocity{ .dx = 5.0, .dy = 10.0 };

    const components = [_]serialize.ComponentInstance{
        serialize.ComponentInstance.from(Position, &pos),
        serialize.ComponentInstance.from(Velocity, &vel),
    };

    // Create entity from components
    const entity = try manager.createFromComponents(&components);

    // Verify
    const retrieved_pos = try manager.getComponent(entity, Position);
    try testing.expect(retrieved_pos != null);
    try testing.expectEqual(pos.x, retrieved_pos.?.x);
    try testing.expectEqual(pos.y, retrieved_pos.?.y);

    const retrieved_vel = try manager.getComponent(entity, Velocity);
    try testing.expect(retrieved_vel != null);
    try testing.expectEqual(vel.dx, retrieved_vel.?.dx);
    try testing.expectEqual(vel.dy, retrieved_vel.?.dy);
}

test "Manager - createFromComponents empty" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const components = [_]serialize.ComponentInstance{};
    const entity = try manager.createFromComponents(&components);
    try testing.expect(entity.id >= 0);
}

test "ComponentWriter and ComponentReader" {
    const allocator = testing.allocator;

    const pos = Position{ .x = 7.0, .y = 14.0 };
    const vel = Velocity{ .dx = 2.5, .dy = 3.5 };

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    // Write components
    var component_writer = serialize.ComponentWriter.init(buffer.writer(allocator).any());
    try component_writer.writeTypedComponent(Position, &pos);
    try component_writer.writeTypedComponent(Velocity, &vel);

    // Read components
    var fbs = std.io.fixedBufferStream(buffer.items);
    var component_reader = serialize.ComponentReader.init(fbs.reader().any());

    const comp1 = try component_reader.readComponent(allocator);
    defer component_reader.freeComponent(allocator, comp1);
    const comp2 = try component_reader.readComponent(allocator);
    defer component_reader.freeComponent(allocator, comp2);

    // Verify
    const restored_pos = comp1.as(Position);
    try testing.expect(restored_pos != null);
    try testing.expectEqual(pos.x, restored_pos.?.x);
    try testing.expectEqual(pos.y, restored_pos.?.y);

    const restored_vel = comp2.as(Velocity);
    try testing.expect(restored_vel != null);
    try testing.expectEqual(vel.dx, restored_vel.?.dx);
    try testing.expectEqual(vel.dy, restored_vel.?.dy);
}

test "ComponentWriter and ComponentReader - writeComponents and readComponents" {
    const allocator = testing.allocator;

    const pos = Position{ .x = 11.0, .y = 22.0 };
    const vel = Velocity{ .dx = 33.0, .dy = 44.0 };
    const health = Health{ .value = 200 };

    const components = [_]serialize.ComponentInstance{
        serialize.ComponentInstance.from(Position, &pos),
        serialize.ComponentInstance.from(Velocity, &vel),
        serialize.ComponentInstance.from(Health, &health),
    };

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    // Write components with count header
    var component_writer = serialize.ComponentWriter.init(buffer.writer(allocator).any());
    try component_writer.writeComponents(&components);

    // Read components
    var fbs = std.io.fixedBufferStream(buffer.items);
    var component_reader = serialize.ComponentReader.init(fbs.reader().any());
    const restored_components = try component_reader.readComponents(allocator);
    defer component_reader.freeComponents(allocator, restored_components);

    try testing.expectEqual(@as(usize, 3), restored_components.len);

    // Verify each component (order matters!)
    const restored_pos = restored_components[0].as(Position);
    try testing.expect(restored_pos != null);
    try testing.expectEqual(pos.x, restored_pos.?.x);

    const restored_vel = restored_components[1].as(Velocity);
    try testing.expect(restored_vel != null);
    try testing.expectEqual(vel.dx, restored_vel.?.dx);

    const restored_health = restored_components[2].as(Health);
    try testing.expect(restored_health != null);
    try testing.expectEqual(health.value, restored_health.?.value);
}
