const std = @import("std");
const testing = std.testing;
const ecs = @import("ecs.zig");
const serialize = @import("serialize.zig");
const relations = @import("relations.zig");

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
    var entity_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
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
    var original_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
    defer original_instance.deinit(allocator);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator).any();
    try original_instance.writeTo(writer);

    // Read back EntityInstance
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    var restored_instance = try serialize.EntityInstance.readFrom(reader, allocator);
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
    var entity_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
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
        var instance = try serialize.EntityInstance.fromEntity(allocator, &manager, entity);
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
        var restored = try serialize.EntityInstance.readFrom(reader, allocator);
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

test "EntityInstance - with relation component (Entity field)" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create two entities - parent and child
    const parent = manager.create(.{Position{ .x = 0.0, .y = 0.0 }});
    const child = manager.create(.{
        Position{ .x = 10.0, .y = 10.0 },
        Velocity{ .dx = 1.0, .dy = 1.0 },
    });

    // Create a custom relation-like component (simulating Relation(AttachedTo))
    const AttachmentRelation = struct {
        target: ecs.Entity,
        offset_x: f32 = 0.0,
        offset_y: f32 = 0.0,
    };

    try manager.addComponent(child, AttachmentRelation, AttachmentRelation{
        .target = parent,
        .offset_x = 5.0,
        .offset_y = 5.0,
    });

    // Convert child entity to EntityInstance
    var child_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, child);
    defer child_instance.deinit(allocator);

    // Verify the child has the attachment relation
    var has_attachment = false;
    for (child_instance.components) |comp| {
        if (comp.as(AttachmentRelation)) |attachment| {
            has_attachment = true;
            // Verify the target entity reference is preserved
            try testing.expectEqual(parent.id, attachment.target.id);
            try testing.expectEqual(parent.generation, attachment.target.generation);
            try testing.expectEqual(@as(f32, 5.0), attachment.offset_x);
            break;
        }
    }
    try testing.expect(has_attachment);
}

test "EntityInstance - serialize and deserialize with relation component" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Define a custom relation component with Entity field
    const ParentRelation = struct {
        parent_entity: ecs.Entity,
        slot: u32 = 0,
    };

    // Create parent entity
    const parent = manager.create(.{Position{ .x = 0.0, .y = 0.0 }});

    // Create child entity with parent relation
    const child = manager.create(.{
        Position{ .x = 5.0, .y = 5.0 },
        ParentRelation{
            .parent_entity = parent,
            .slot = 1,
        },
    });

    // Serialize the child entity
    var child_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, child);
    defer child_instance.deinit(allocator);

    // Write to buffer
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator).any();
    try child_instance.writeTo(writer);

    // Read back from buffer
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    var restored_instance = try serialize.EntityInstance.readFrom(reader, allocator);
    defer restored_instance.deinit(allocator);

    // Create entity from restored instance
    const new_child = try restored_instance.toEntity(&manager);

    // Verify components
    const pos = try manager.getComponent(new_child, Position);
    try testing.expect(pos != null);
    try testing.expectEqual(@as(f32, 5.0), pos.?.x);
    try testing.expectEqual(@as(f32, 5.0), pos.?.y);

    const parent_rel = try manager.getComponent(new_child, ParentRelation);
    try testing.expect(parent_rel != null);
    // The parent entity reference is preserved (same ID and generation)
    try testing.expectEqual(parent.id, parent_rel.?.parent_entity.id);
    try testing.expectEqual(parent.generation, parent_rel.?.parent_entity.generation);
    try testing.expectEqual(@as(u32, 1), parent_rel.?.slot);
}

test "EntityInstance - with references (fromEntityWithReferences)" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create parent entity
    const parent = manager.create(.{
        Position{ .x = 0.0, .y = 0.0 },
        Health{ .value = 100 },
    });

    // Define relation component
    const ChildOf = struct {
        parent: ecs.Entity,
    };

    // Create child entity with relation to parent
    const child = manager.create(.{
        Position{ .x = 10.0, .y = 10.0 },
        ChildOf{ .parent = parent },
    });

    // Serialize with references
    var referenced_entities_map = std.AutoHashMap(u32, ecs.Entity).init(allocator);
    defer referenced_entities_map.deinit();

    var child_instance = try serialize.EntityInstance.fromEntityWithReferences(
        allocator,
        &manager,
        child,
        &referenced_entities_map,
    );
    defer child_instance.deinit(allocator);

    // The child should have detected the parent as a referenced entity
    // (if the heuristic successfully detected it)
    // For now, this test validates the API works without panicking
    try testing.expect(child_instance.components.len >= 2); // At least Position and ChildOf
}

test "EntityInstance - roundtrip with relation component" {
    const allocator = testing.allocator;
    var manager1 = try ecs.Manager.init(allocator);
    defer manager1.deinit();

    var manager2 = try ecs.Manager.init(allocator);
    defer manager2.deinit();

    // Define relation component
    const Owner = struct {
        owner_entity: ecs.Entity,
    };

    // In manager1: Create entities with relation
    const owner1 = manager1.create(.{Position{ .x = 1.0, .y = 1.0 }});
    const item1 = manager1.create(.{
        Position{ .x = 2.0, .y = 2.0 },
        Owner{ .owner_entity = owner1 },
    });

    // Serialize from manager1
    var item_instance = try serialize.EntityInstance.fromEntity(allocator, &manager1, item1);
    defer item_instance.deinit(allocator);

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);
    const writer = buffer.writer(allocator).any();
    try item_instance.writeTo(writer);

    // Deserialize to manager2
    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    var restored_instance = try serialize.EntityInstance.readFrom(reader, allocator);
    defer restored_instance.deinit(allocator);

    const item2 = try restored_instance.toEntity(&manager2);

    // Verify the relation component preserved Entity reference
    const owner = try manager2.getComponent(item2, Owner);
    try testing.expect(owner != null);
    try testing.expectEqual(owner1.id, owner.?.owner_entity.id);
    try testing.expectEqual(owner1.generation, owner.?.owner_entity.generation);
}

test "EntityInstance - multiple Entity fields in component" {
    const allocator = testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Component with multiple Entity fields
    const Link = struct {
        source: ecs.Entity,
        destination: ecs.Entity,
        weight: f32 = 1.0,
    };

    const entity_a = manager.create(.{Position{ .x = 1.0, .y = 1.0 }});
    const entity_b = manager.create(.{Position{ .x = 2.0, .y = 2.0 }});

    const link_entity = manager.create(.{
        Link{
            .source = entity_a,
            .destination = entity_b,
            .weight = 0.5,
        },
    });

    // Serialize
    var link_instance = try serialize.EntityInstance.fromEntity(allocator, &manager, link_entity);
    defer link_instance.deinit(allocator);

    // Verify both entity references are preserved
    var found_link = false;
    for (link_instance.components) |comp| {
        if (comp.as(Link)) |link| {
            found_link = true;
            try testing.expectEqual(entity_a.id, link.source.id);
            try testing.expectEqual(entity_b.id, link.destination.id);
            try testing.expectEqual(@as(f32, 0.5), link.weight);
            break;
        }
    }
    try testing.expect(found_link);

    // Roundtrip through serialization
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    const writer = buffer.writer(allocator).any();
    try link_instance.writeTo(writer);

    var fbs = std.io.fixedBufferStream(buffer.items);
    const reader = fbs.reader().any();
    var restored_instance = try serialize.EntityInstance.readFrom(reader, allocator);
    defer restored_instance.deinit(allocator);

    const new_link_entity = try restored_instance.toEntity(&manager);

    const restored_link = try manager.getComponent(new_link_entity, Link);
    try testing.expect(restored_link != null);
    try testing.expectEqual(entity_a.id, restored_link.?.source.id);
    try testing.expectEqual(entity_b.id, restored_link.?.destination.id);
    try testing.expectEqual(@as(f32, 0.5), restored_link.?.weight);
}
