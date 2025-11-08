const std = @import("std");
const ecs = @import("ecs.zig");
const relations = @import("relations.zig");
const AttachedTo = relations.AttachedTo;
const ChildOf = relations.Child;
const Owns = relations.Owns;
const Relation = relations.Relation;
const RelationConfig = relations.RelationConfig;
const RelationManager = relations.RelationManager;

// Test components
const Position = struct {
    x: f32,
    y: f32,
};

const Transform = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

/// Relation with custom data (non-indexed)
const SocketData = struct {
    socket_name: []const u8,
};

test "RelationManager - basic init/deinit" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    try std.testing.expect(rel_manager.indexCount() == 0);
}

test "RelationManager - non-indexed relation (zero overhead)" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const entity_a = manager.create(.{Position{ .x = 0, .y = 0 }});
    const entity_b = manager.create(.{Position{ .x = 1, .y = 1 }});

    // Add non-indexed relation
    try rel_manager.add(&manager, entity_a, entity_b, AttachedTo);

    // Verify no index was created
    try std.testing.expect(rel_manager.indexCount() == 0);

    // Verify component exists
    const rel = try manager.getComponent(entity_a, Relation(AttachedTo));
    try std.testing.expect(rel != null);
    try std.testing.expect(rel.?.target.eql(entity_b));

    // Get target (reads from component directly)
    const target = try rel_manager.getParent(&manager, entity_a, AttachedTo);
    try std.testing.expect(target != null);
    try std.testing.expect(target.?.eql(entity_b));
}

test "RelationManager - indexed relation creates index lazily" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child = manager.create(.{Transform{}});

    // Before adding indexed relation
    try std.testing.expect(rel_manager.indexCount() == 0);

    // Add indexed relation
    try rel_manager.add(&manager, child, parent, ChildOf);

    // Index should now exist
    try std.testing.expect(rel_manager.indexCount() == 1);

    // Verify component exists
    const rel = try manager.getComponent(child, Relation(ChildOf));
    try std.testing.expect(rel != null);
    try std.testing.expect(rel.?.target.eql(parent));
}

test "RelationManager - indexed relation reverse queries" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child1 = manager.create(.{Transform{}});
    const child2 = manager.create(.{Transform{}});
    const child3 = manager.create(.{Transform{}});

    // Add multiple children
    try rel_manager.add(&manager, child1, parent, ChildOf);
    try rel_manager.add(&manager, child2, parent, ChildOf);
    try rel_manager.add(&manager, child3, parent, ChildOf);

    // Get all children (reverse query)
    const children = try rel_manager.getChildren(parent, ChildOf);
    try std.testing.expect(children.len == 3);

    // Verify all children are present
    var found = [_]bool{false} ** 3;
    for (children) |child| {
        if (child.eql(child1)) found[0] = true;
        if (child.eql(child2)) found[1] = true;
        if (child.eql(child3)) found[2] = true;
    }
    try std.testing.expect(found[0] and found[1] and found[2]);
}

test "RelationManager - exclusive relation replaces existing" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent1 = manager.create(.{Transform{}});
    const parent2 = manager.create(.{Transform{}});
    const child = manager.create(.{Transform{}});

    // Add first parent
    try rel_manager.add(&manager, child, parent1, ChildOf);

    // Verify child has parent1
    const target1 = try rel_manager.getParent(&manager, child, ChildOf);
    try std.testing.expect(target1 != null);
    try std.testing.expect(target1.?.eql(parent1));

    // Add second parent (should replace first)
    try rel_manager.add(&manager, child, parent2, ChildOf);

    // Verify child now has parent2
    const target2 = try rel_manager.getParent(&manager, child, ChildOf);
    try std.testing.expect(target2 != null);
    try std.testing.expect(target2.?.eql(parent2));

    // Verify parent1 has no children
    const children1 = try rel_manager.getChildren(parent1, ChildOf);
    try std.testing.expect(children1.len == 0);

    // Verify parent2 has child
    const children2 = try rel_manager.getChildren(parent2, ChildOf);
    try std.testing.expect(children2.len == 1);
    try std.testing.expect(children2[0].eql(child));
}

test "RelationManager - non-exclusive relations allow multiple" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const player = manager.create(.{Transform{}});
    const sword = manager.create(.{Transform{}});
    const shield = manager.create(.{Transform{}});
    const potion = manager.create(.{Transform{}});

    // Add multiple owned items
    try rel_manager.add(&manager, player, sword, Owns);
    try rel_manager.add(&manager, player, shield, Owns);
    try rel_manager.add(&manager, player, potion, Owns);

    // Get all owned items
    const items = try rel_manager.getParents(player, Owns);
    try std.testing.expect(items.len == 3);

    // Verify all items are present
    var found = [_]bool{false} ** 3;
    for (items) |item| {
        if (item.eql(sword)) found[0] = true;
        if (item.eql(shield)) found[1] = true;
        if (item.eql(potion)) found[2] = true;
    }
    try std.testing.expect(found[0] and found[1] and found[2]);
}

test "RelationManager - relation with custom data" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const character = manager.create(.{Transform{}});
    const weapon = manager.create(.{Transform{}});

    // Add relation with custom data
    try rel_manager.addWithData(&manager, weapon, character, SocketData, .{
        .socket_name = "right_hand",
    });

    // Verify component exists with data
    const rel = try manager.getComponent(weapon, Relation(SocketData));
    try std.testing.expect(rel != null);
    try std.testing.expect(rel.?.target.eql(character));
    try std.testing.expectEqualStrings("right_hand", rel.?.data.socket_name);
}

test "RelationManager - remove relation" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child = manager.create(.{Transform{}});

    // Add relation
    try rel_manager.add(&manager, child, parent, ChildOf);

    // Verify it exists
    try std.testing.expect(try rel_manager.has(&manager, child, parent, ChildOf));

    // Remove relation
    try rel_manager.remove(&manager, child, parent, ChildOf);

    // Verify it's gone
    try std.testing.expect(!try rel_manager.has(&manager, child, parent, ChildOf));

    // Verify component is removed
    const rel = try manager.getComponent(child, Relation(ChildOf));
    try std.testing.expect(rel == null);

    // Verify index is updated
    const children = try rel_manager.getChildren(parent, ChildOf);
    try std.testing.expect(children.len == 0);
}

test "RelationManager - removeEntity cleans up all relations" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child1 = manager.create(.{Transform{}});
    const child2 = manager.create(.{Transform{}});

    // Add relations
    try rel_manager.add(&manager, child1, parent, ChildOf);
    try rel_manager.add(&manager, child2, parent, ChildOf);

    // Verify children exist
    var children = try rel_manager.getChildren(parent, ChildOf);
    try std.testing.expect(children.len == 2);

    // Remove child1 entity
    rel_manager.removeEntity(child1);

    // Verify parent now has only one child
    children = try rel_manager.getChildren(parent, ChildOf);
    try std.testing.expect(children.len == 1);
    try std.testing.expect(children[0].eql(child2));

    // Remove parent entity
    rel_manager.removeEntity(parent);

    // Verify child2's parent reference is cleaned up
    children = try rel_manager.getChildren(parent, ChildOf);
    try std.testing.expect(children.len == 0);
}

test "RelationManager - has() checks relation existence" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const entity_a = manager.create(.{Transform{}});
    const entity_b = manager.create(.{Transform{}});
    const entity_c = manager.create(.{Transform{}});

    // No relation initially
    try std.testing.expect(!try rel_manager.has(&manager, entity_a, entity_b, AttachedTo));

    // Add relation
    try rel_manager.add(&manager, entity_a, entity_b, AttachedTo);

    // Relation exists
    try std.testing.expect(try rel_manager.has(&manager, entity_a, entity_b, AttachedTo));

    // Different target doesn't exist
    try std.testing.expect(!try rel_manager.has(&manager, entity_a, entity_c, AttachedTo));
}

test "RelationManager - query entities with relations" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child1 = manager.create(.{Transform{ .x = 1 }});
    const child2 = manager.create(.{Transform{ .x = 2 }});
    const child3 = manager.create(.{Transform{ .x = 3 }});

    // Add relations
    try rel_manager.add(&manager, child1, parent, ChildOf);
    try rel_manager.add(&manager, child2, parent, ChildOf);
    try rel_manager.add(&manager, child3, parent, ChildOf);

    // Query all entities with ChildOf relation
    var query = manager.query(
        struct { transform: Transform, rel: Relation(ChildOf) },
        .{},
    );

    var count: usize = 0;
    while (query.next()) |item| {
        const child: ecs.Entity = item.rel.target;
        // Verify all have the same parent
        try std.testing.expect(child.eql(parent));
        count += 1;
    }

    try std.testing.expect(count == 3);
}

test "RelationManager - mixed indexed and non-indexed relations" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    const parent = manager.create(.{Transform{}});
    const child = manager.create(.{Transform{}});
    const attachment = manager.create(.{Transform{}});

    // Add indexed relation
    try rel_manager.add(&manager, child, parent, ChildOf);

    // Add non-indexed relation
    try rel_manager.add(&manager, attachment, child, AttachedTo);

    // Only ChildOf should create an index
    try std.testing.expect(rel_manager.indexCount() == 1);

    // Both relations should work
    const parent_target = try rel_manager.getParent(&manager, child, ChildOf);
    try std.testing.expect(parent_target != null);
    try std.testing.expect(parent_target.?.eql(parent));

    const attach_target = try rel_manager.getParent(&manager, attachment, AttachedTo);
    try std.testing.expect(attach_target != null);
    try std.testing.expect(attach_target.?.eql(child));
}

test "RelationManager - hierarchy traversal" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    // Create hierarchy: root -> [a, b] where a -> [c, d]
    const root = manager.create(.{Transform{}});
    const a = manager.create(.{Transform{}});
    const b = manager.create(.{Transform{}});
    const c = manager.create(.{Transform{}});
    const d = manager.create(.{Transform{}});

    try rel_manager.add(&manager, a, root, ChildOf);
    try rel_manager.add(&manager, b, root, ChildOf);
    try rel_manager.add(&manager, c, a, ChildOf);
    try rel_manager.add(&manager, d, a, ChildOf);

    // Traverse hierarchy depth-first
    var visited = try std.ArrayList(ecs.Entity).initCapacity(allocator, 0);
    defer visited.deinit(allocator);

    const Helper = struct {
        fn traverse(
            m: *ecs.Manager,
            rm: *RelationManager,
            alloc: std.mem.Allocator,
            v: *std.ArrayList(ecs.Entity),
            entity: ecs.Entity,
        ) !void {
            try v.append(alloc, entity);
            const children = try rm.getChildren(entity, ChildOf);
            for (children) |child| {
                try traverse(m, rm, alloc, v, child);
            }
        }
    };

    try Helper.traverse(&manager, &rel_manager, allocator, &visited, root);

    // Should visit all 5 entities
    try std.testing.expect(visited.items.len == 5);
}

test "RelationManager - memory efficiency for sparse relations" {
    const allocator = std.testing.allocator;

    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    var rel_manager = RelationManager.init(allocator);
    defer rel_manager.deinit();

    // Create 100 entities
    var entities: [100]ecs.Entity = undefined;
    for (&entities) |*entity| {
        entity.* = manager.create(.{Transform{}});
    }

    // Only 10 have non-indexed relations
    for (0..10) |i| {
        try rel_manager.add(&manager, entities[i], entities[i + 10], AttachedTo);
    }

    // No indices should be created
    try std.testing.expect(rel_manager.indexCount() == 0);

    // All 10 relations should work
    for (0..10) |i| {
        const target = try rel_manager.getParent(&manager, entities[i], AttachedTo);
        try std.testing.expect(target != null);
        try std.testing.expect(target.?.eql(entities[i + 10]));
    }
}
