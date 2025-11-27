const std = @import("std");
const archetype_storage_mod = @import("archetype_storage.zig");
const ArchetypeStorage = archetype_storage_mod.ArchetypeStorage;
const EntityMapEntry = archetype_storage_mod.EntityMapEntry;
const archetype_mod = @import("archetype.zig");
const ArchetypeSignature = archetype_mod.ArchetypeSignature;
const Entity = @import("ecs.zig").Entity;

test "ArchetypeStorage - init and deinit" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    try std.testing.expect(storage.archetypes.count() == 0);
    try std.testing.expect(storage.entity_sparse_array.items.len == 0);
}

test "ArchetypeStorage - getOrCreate creates new" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 8, 16 };

    const archetype = try storage.getOrCreate(signature, sizes);

    try std.testing.expect(archetype.signature.types.len == 2);
    try std.testing.expect(storage.archetypes.count() == 1);
}

test "ArchetypeStorage - getOrCreate returns existing" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 8, 16 };

    const archetype1 = try storage.getOrCreate(signature, sizes);
    const archetype2 = try storage.getOrCreate(signature, sizes);

    try std.testing.expect(archetype1 == archetype2);
    try std.testing.expect(storage.archetypes.count() == 1);
}

test "ArchetypeStorage - multiple different archetypes" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types1 = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    defer allocator.free(types1);
    const sig1 = ArchetypeSignature{ .types = types1 };
    _ = try storage.getOrCreate(sig1, &[_]usize{ 4, 4 });

    const types2 = try allocator.dupe(u64, &[_]u64{ 3, 4 });
    defer allocator.free(types2);
    const sig2 = ArchetypeSignature{ .types = types2 };
    _ = try storage.getOrCreate(sig2, &[_]usize{ 8, 8 });

    const types3 = try allocator.dupe(u64, &[_]u64{ 5, 6, 7 });
    defer allocator.free(types3);
    const sig3 = ArchetypeSignature{ .types = types3 };
    _ = try storage.getOrCreate(sig3, &[_]usize{ 16, 16, 16 });

    try std.testing.expect(storage.archetypes.count() == 3);
}

test "ArchetypeStorage - add" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    const entity = Entity{ .id = 0, .generation = 0 };
    var data = [_]u8{ 1, 2, 3, 4 };
    var component_data = [_][]const u8{&data};

    try storage.add(entity, signature, sizes, &component_data);

    const entry = storage.get(entity);
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.index == 0);
}

test "ArchetypeStorage - add multiple entities" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    for (0..10) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        var data = [_]u8{ @intCast(i), 0, 0, 0 };
        var component_data = [_][]const u8{&data};
        try storage.add(entity, signature, sizes, &component_data);
    }

    // Verify all entities are tracked
    for (0..10) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        const entry = storage.get(entity);
        try std.testing.expect(entry != null);
        try std.testing.expect(entry.?.index == i);
    }
}

test "ArchetypeStorage - get returns null for unknown entity" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const entity = Entity{ .id = 999, .generation = 0 };
    const entry = storage.get(entity);

    try std.testing.expect(entry == null);
}

test "ArchetypeStorage - get returns correct entry" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 4 };

    const entity = Entity{ .id = 5, .generation = 2 };
    var data1 = [_]u8{ 1, 2, 3, 4 };
    var data2 = [_]u8{ 5, 6, 7, 8 };
    var component_data = [_][]const u8{ &data1, &data2 };

    try storage.add(entity, signature, sizes, &component_data);

    const entry = storage.get(entity);
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.archetype.signature.types.len == 2);
    try std.testing.expect(entry.?.index == 0);
}

test "ArchetypeStorage - setEntityEntry" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};
    const archetype = try storage.getOrCreate(signature, sizes);

    const entity = Entity{ .id = 10, .generation = 0 };
    const entry = EntityMapEntry{ .archetype = archetype, .index = 5 };

    try storage.set(entity, entry);

    const retrieved = storage.get(entity);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.archetype == archetype);
    try std.testing.expect(retrieved.?.index == 5);
}

test "ArchetypeStorage - setEntityEntry grows sparse array" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};
    const archetype = try storage.getOrCreate(signature, sizes);

    // Set entry for entity with large ID
    const entity = Entity{ .id = 10000, .generation = 0 };
    const entry = EntityMapEntry{ .archetype = archetype, .index = 0 };

    try storage.set(entity, entry);

    try std.testing.expect(storage.entity_sparse_array.items.len > 10000);

    const retrieved = storage.get(entity);
    try std.testing.expect(retrieved != null);
}

test "ArchetypeStorage - removeEntity" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    const entity = Entity{ .id = 0, .generation = 0 };
    var data = [_]u8{ 1, 2, 3, 4 };
    var component_data = [_][]const u8{&data};

    try storage.add(entity, signature, sizes, &component_data);

    try std.testing.expect(storage.get(entity) != null);

    storage.remove(entity);

    try std.testing.expect(storage.get(entity) == null);
}

test "ArchetypeStorage - removeEntity non-existent entity safe" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const entity = Entity{ .id = 999, .generation = 0 };
    storage.remove(entity); // Should not crash

    try std.testing.expect(storage.get(entity) == null);
}

test "ArchetypeStorage - getArchetype" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 4 };

    const entity = Entity{ .id = 0, .generation = 0 };
    var data1 = [_]u8{ 1, 2, 3, 4 };
    var data2 = [_]u8{ 5, 6, 7, 8 };
    var component_data = [_][]const u8{ &data1, &data2 };

    try storage.add(entity, signature, sizes, &component_data);

    const archetype = storage.getArchetype(entity);
    try std.testing.expect(archetype != null);
    try std.testing.expect(archetype.?.signature.types.len == 2);
}

test "ArchetypeStorage - getArchetype returns null for unknown entity" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const entity = Entity{ .id = 999, .generation = 0 };
    const archetype = storage.getArchetype(entity);

    try std.testing.expect(archetype == null);
}

test "ArchetypeStorage - entities in different archetypes" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    // Add entity to archetype 1
    const types1 = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types1);
    const sig1 = ArchetypeSignature{ .types = types1 };
    const entity1 = Entity{ .id = 0, .generation = 0 };
    var data1 = [_]u8{ 1, 2, 3, 4 };
    var comp_data1 = [_][]const u8{&data1};
    try storage.add(entity1, sig1, &[_]usize{4}, &comp_data1);

    // Add entity to archetype 2
    const types2 = try allocator.dupe(u64, &[_]u64{2});
    defer allocator.free(types2);
    const sig2 = ArchetypeSignature{ .types = types2 };
    const entity2 = Entity{ .id = 1, .generation = 0 };
    var data2 = [_]u8{ 5, 6, 7, 8 };
    var comp_data2 = [_][]const u8{&data2};
    try storage.add(entity2, sig2, &[_]usize{4}, &comp_data2);

    const arch1 = storage.getArchetype(entity1);
    const arch2 = storage.getArchetype(entity2);

    try std.testing.expect(arch1 != null);
    try std.testing.expect(arch2 != null);
    try std.testing.expect(arch1.? != arch2.?);
    try std.testing.expect(arch1.?.signature.types[0] == 1);
    try std.testing.expect(arch2.?.signature.types[0] == 2);
}

test "ArchetypeStorage - stress test many entities" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2, 3 });
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 4, 4 };

    const count = 100_000;

    for (0..count) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        var data1 = [_]u8{ 1, 2, 3, 4 };
        var data2 = [_]u8{ 5, 6, 7, 8 };
        var data3 = [_]u8{ 9, 10, 11, 12 };
        var component_data = [_][]const u8{ &data1, &data2, &data3 };
        try storage.add(entity, signature, sizes, &component_data);
    }

    // Verify sparse array accommodates all entities
    try std.testing.expect(storage.entity_sparse_array.items.len >= count);

    // Spot check some entities
    for ([_]usize{ 0, 1000, 10000, 50000, 99999 }) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        const entry = storage.get(entity);
        try std.testing.expect(entry != null);
    }
}

test "ArchetypeStorage - sparse array null entries" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{1});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    // Add entity with ID 10 (leaving gaps)
    const entity = Entity{ .id = 10, .generation = 0 };
    var data = [_]u8{ 1, 2, 3, 4 };
    var component_data = [_][]const u8{&data};
    try storage.add(entity, signature, sizes, &component_data);

    // Check that gaps are null
    for (0..10) |i| {
        const check_entity = Entity{ .id = @intCast(i), .generation = 0 };
        try std.testing.expect(storage.get(check_entity) == null);
    }

    // Check that entity 10 is present
    try std.testing.expect(storage.get(entity) != null);
}

test "ArchetypeStorage - empty archetype handling" {
    const allocator = std.testing.allocator;

    var storage = ArchetypeStorage.init(allocator);
    defer storage.deinit();

    const types = try allocator.dupe(u64, &[_]u64{});
    defer allocator.free(types);
    const signature = ArchetypeSignature{ .types = types };
    const sizes: []const usize = &[_]usize{};

    const entity = Entity{ .id = 0, .generation = 0 };
    const component_data: [][]const u8 = &[_][]const u8{};

    try storage.add(entity, signature, sizes, component_data);

    const entry = storage.get(entity);
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.archetype.signature.types.len == 0);
}
