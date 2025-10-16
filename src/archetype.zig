const std = @import("std");
const hash = std.hash;
const errors = @import("errors.zig");
const TypeInfo = @import("world.zig").TypeInfo;
const Entity = @import("ecs.zig").Entity;

/// Represents a unique set of component types (an archetype signature)
pub const ArchetypeSignature = struct {
    // Sorted array of component type hashes
    types: []const u64,

    pub fn hash(self: ArchetypeSignature) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.types));
    }

    pub fn eql(self: ArchetypeSignature, other: ArchetypeSignature) bool {
        return std.mem.eql(u64, self.types, other.types);
    }
};

/// Stores all entities with the same component set (archetype)
pub const Archetype = struct {
    allocator: std.mem.Allocator,
    signature: ArchetypeSignature,
    entities: std.ArrayList(Entity),
    // For each component type, a contiguous array of bytes
    component_arrays: []std.ArrayList(u8),
    component_sizes: []usize,

    pub fn init(
        allocator: std.mem.Allocator,
        signature: ArchetypeSignature,
        component_sizes: []const usize,
    ) !*Archetype {
        // Signature is expected to already have heap-allocated types from the caller
        const archetype = try allocator.create(Archetype);
        const initial_capacity = 1024; // Pre-allocate for many entities
        archetype.* = Archetype{
            .allocator = allocator,
            .signature = signature,
            .entities = (std.ArrayList(Entity).initCapacity(allocator, initial_capacity) catch @panic("Failed to allocate")),
            .component_arrays = try allocator.alloc(std.ArrayList(u8), component_sizes.len),
            .component_sizes = try allocator.alloc(usize, component_sizes.len),
        };
        for (component_sizes, 0..) |size, i| {
            const byte_capacity = initial_capacity * size;
            archetype.component_arrays[i] = (std.ArrayList(u8).initCapacity(allocator, byte_capacity) catch @panic("Failed to allocate"));
            archetype.component_sizes[i] = size;
        }
        return archetype;
    }

    pub fn deinit(self: *Archetype) void {
        self.entities.deinit(self.allocator);
        for (self.component_arrays) |*arr| arr.deinit(self.allocator);
        self.allocator.free(self.component_arrays);
        self.allocator.free(self.component_sizes);
        self.allocator.free(self.signature.types);
        self.allocator.destroy(self);
    }

    /// Add an entity and its component data to this archetype
    /// `component_data` is an array of pointers to bytes, one per component type, matching the signature order
    pub fn addEntity(self: *Archetype, entity: Entity, component_data: [][]const u8) !void {
        try self.entities.append(self.allocator, entity);
        for (component_data, 0..) |data, i| {
            const size = self.component_sizes[i];
            const arr = &self.component_arrays[i];
            try arr.appendSlice(self.allocator, data[0..size]);
        }
    }
};

/// Hash/compare helpers for ArchetypeSignature
pub fn archetypeSignatureHash(ctx: void, key: ArchetypeSignature) u64 {
    _ = ctx;
    return key.hash();
}
pub fn archetypeSignatureEql(ctx: void, a: ArchetypeSignature, b: ArchetypeSignature) bool {
    _ = ctx;
    return a.eql(b);
}
