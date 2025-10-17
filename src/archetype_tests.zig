const std = @import("std");
const archetype_mod = @import("archetype.zig");
const Archetype = archetype_mod.Archetype;
const ArchetypeSignature = archetype_mod.ArchetypeSignature;
const Entity = @import("ecs.zig").Entity;

test "ArchetypeSignature - hash consistency" {
    const allocator = std.testing.allocator;

    const types1 = try allocator.dupe(u64, &[_]u64{ 1, 2, 3 });
    defer allocator.free(types1);
    const types2 = try allocator.dupe(u64, &[_]u64{ 1, 2, 3 });
    defer allocator.free(types2);

    const sig1 = ArchetypeSignature{ .types = types1 };
    const sig2 = ArchetypeSignature{ .types = types2 };

    const hash1 = sig1.hash();
    const hash2 = sig2.hash();

    try std.testing.expect(hash1 == hash2);
}

test "ArchetypeSignature - hash difference" {
    const allocator = std.testing.allocator;

    const types1 = try allocator.dupe(u64, &[_]u64{ 1, 2, 3 });
    defer allocator.free(types1);
    const types2 = try allocator.dupe(u64, &[_]u64{ 4, 5, 6 });
    defer allocator.free(types2);

    const sig1 = ArchetypeSignature{ .types = types1 };
    const sig2 = ArchetypeSignature{ .types = types2 };

    const hash1 = sig1.hash();
    const hash2 = sig2.hash();

    try std.testing.expect(hash1 != hash2);
}

test "ArchetypeSignature - eql returns true for same types" {
    const allocator = std.testing.allocator;

    const types1 = try allocator.dupe(u64, &[_]u64{ 10, 20, 30 });
    defer allocator.free(types1);
    const types2 = try allocator.dupe(u64, &[_]u64{ 10, 20, 30 });
    defer allocator.free(types2);

    const sig1 = ArchetypeSignature{ .types = types1 };
    const sig2 = ArchetypeSignature{ .types = types2 };

    try std.testing.expect(sig1.eql(sig2));
}

test "ArchetypeSignature - eql returns false for different types" {
    const allocator = std.testing.allocator;

    const types1 = try allocator.dupe(u64, &[_]u64{ 10, 20, 30 });
    defer allocator.free(types1);
    const types2 = try allocator.dupe(u64, &[_]u64{ 10, 20, 40 });
    defer allocator.free(types2);

    const sig1 = ArchetypeSignature{ .types = types1 };
    const sig2 = ArchetypeSignature{ .types = types2 };

    try std.testing.expect(!sig1.eql(sig2));
}

test "ArchetypeSignature - eql returns false for different lengths" {
    const allocator = std.testing.allocator;

    const types1 = try allocator.dupe(u64, &[_]u64{ 10, 20 });
    defer allocator.free(types1);
    const types2 = try allocator.dupe(u64, &[_]u64{ 10, 20, 30 });
    defer allocator.free(types2);

    const sig1 = ArchetypeSignature{ .types = types1 };
    const sig2 = ArchetypeSignature{ .types = types2 };

    try std.testing.expect(!sig1.eql(sig2));
}

test "ArchetypeSignature - empty signature" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{});
    defer allocator.free(types);

    const sig = ArchetypeSignature{ .types = types };

    const hash_val = sig.hash();
    try std.testing.expect(hash_val != 0); // Should still produce a hash
}

test "Archetype - init and deinit" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 8, 16 };

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    try std.testing.expect(archetype.entities.items.len == 0);
    try std.testing.expect(archetype.signature.types.len == 2);
    try std.testing.expect(archetype.component_arrays.len == 2);
}

test "Archetype - addEntity single entity" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{ 100, 200 });
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 8 };

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };

    // Create component data
    var data1 = [_]u8{ 1, 2, 3, 4 };
    var data2 = [_]u8{ 5, 6, 7, 8, 9, 10, 11, 12 };
    var component_data = [_][]const u8{ &data1, &data2 };

    try archetype.addEntity(entity, &component_data);

    try std.testing.expect(archetype.entities.items.len == 1);
    try std.testing.expect(archetype.entities.items[0].id == 0);
    try std.testing.expect(archetype.component_arrays[0].items.len == 4);
    try std.testing.expect(archetype.component_arrays[1].items.len == 8);
}

test "Archetype - addEntity multiple entities" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{100});
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    // Add 10 entities
    for (0..10) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        var data = [_]u8{ @intCast(i), 0, 0, 0 };
        var component_data = [_][]const u8{&data};
        try archetype.addEntity(entity, &component_data);
    }

    try std.testing.expect(archetype.entities.items.len == 10);
    try std.testing.expect(archetype.component_arrays[0].items.len == 40); // 10 entities * 4 bytes
}

test "Archetype - component data integrity" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2 });
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 4 };

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    // Add entity with specific component data
    const entity = Entity{ .id = 0, .generation = 0 };
    var data1 = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    var data2 = [_]u8{ 0x11, 0x22, 0x33, 0x44 };
    var component_data = [_][]const u8{ &data1, &data2 };

    try archetype.addEntity(entity, &component_data);

    // Verify data was stored correctly
    try std.testing.expect(archetype.component_arrays[0].items[0] == 0xAA);
    try std.testing.expect(archetype.component_arrays[0].items[1] == 0xBB);
    try std.testing.expect(archetype.component_arrays[0].items[2] == 0xCC);
    try std.testing.expect(archetype.component_arrays[0].items[3] == 0xDD);

    try std.testing.expect(archetype.component_arrays[1].items[0] == 0x11);
    try std.testing.expect(archetype.component_arrays[1].items[1] == 0x22);
    try std.testing.expect(archetype.component_arrays[1].items[2] == 0x33);
    try std.testing.expect(archetype.component_arrays[1].items[3] == 0x44);
}

test "Archetype - empty archetype (no components)" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{});
    const signature = ArchetypeSignature{ .types = types };
    const sizes: []const usize = &[_]usize{};

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    const component_data: [][]const u8 = &[_][]const u8{};

    try archetype.addEntity(entity, component_data);

    try std.testing.expect(archetype.entities.items.len == 1);
    try std.testing.expect(archetype.component_arrays.len == 0);
}

test "Archetype - large component sizes" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{1});
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{1024}; // 1KB component

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    const large_data = try allocator.alloc(u8, 1024);
    defer allocator.free(large_data);
    @memset(large_data, 0xFF);

    var component_data = [_][]const u8{large_data};
    try archetype.addEntity(entity, &component_data);

    try std.testing.expect(archetype.entities.items.len == 1);
    try std.testing.expect(archetype.component_arrays[0].items.len == 1024);
    try std.testing.expect(archetype.component_arrays[0].items[0] == 0xFF);
    try std.testing.expect(archetype.component_arrays[0].items[1023] == 0xFF);
}

test "Archetype - many entities stress test" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2, 3 });
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 4, 8, 16 };

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    const count = 10_000;

    for (0..count) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = 0 };
        var data1 = [_]u8{ 1, 2, 3, 4 };
        var data2 = [_]u8{ 5, 6, 7, 8, 9, 10, 11, 12 };
        var data3 = [_]u8{ 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 };
        var component_data = [_][]const u8{ &data1, &data2, &data3 };
        try archetype.addEntity(entity, &component_data);
    }

    try std.testing.expect(archetype.entities.items.len == count);
    try std.testing.expect(archetype.component_arrays[0].items.len == count * 4);
    try std.testing.expect(archetype.component_arrays[1].items.len == count * 8);
    try std.testing.expect(archetype.component_arrays[2].items.len == count * 16);
}

test "Archetype - signature with single type" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{999});
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{16};

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    try std.testing.expect(archetype.signature.types.len == 1);
    try std.testing.expect(archetype.signature.types[0] == 999);
    try std.testing.expect(archetype.component_sizes.len == 1);
    try std.testing.expect(archetype.component_sizes[0] == 16);
}

test "Archetype - entity generation tracking" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{1});
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{4};

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    // Add entities with different generations
    for (0..5) |i| {
        const entity = Entity{ .id = @intCast(i), .generation = @intCast(i * 10) };
        var data = [_]u8{ 1, 2, 3, 4 };
        var component_data = [_][]const u8{&data};
        try archetype.addEntity(entity, &component_data);
    }

    // Verify generations are preserved
    try std.testing.expect(archetype.entities.items[0].generation == 0);
    try std.testing.expect(archetype.entities.items[1].generation == 10);
    try std.testing.expect(archetype.entities.items[2].generation == 20);
    try std.testing.expect(archetype.entities.items[3].generation == 30);
    try std.testing.expect(archetype.entities.items[4].generation == 40);
}

test "Archetype - multiple components different sizes" {
    const allocator = std.testing.allocator;

    const types = try allocator.dupe(u64, &[_]u64{ 1, 2, 3, 4 });
    const signature = ArchetypeSignature{ .types = types };
    const sizes = &[_]usize{ 1, 2, 4, 8 }; // Different sizes

    var archetype = try Archetype.init(allocator, signature, sizes);
    defer archetype.deinit();

    const entity = Entity{ .id = 0, .generation = 0 };
    var data1 = [_]u8{0xAA};
    var data2 = [_]u8{ 0xBB, 0xCC };
    var data3 = [_]u8{ 0xDD, 0xEE, 0xFF, 0x00 };
    var data4 = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 };
    var component_data = [_][]const u8{ &data1, &data2, &data3, &data4 };

    try archetype.addEntity(entity, &component_data);

    try std.testing.expect(archetype.component_arrays[0].items.len == 1);
    try std.testing.expect(archetype.component_arrays[1].items.len == 2);
    try std.testing.expect(archetype.component_arrays[2].items.len == 4);
    try std.testing.expect(archetype.component_arrays[3].items.len == 8);
}
