const std = @import("std");
const hash = std.hash;
const errors = @import("errors.zig");
const Archetype = @import("archetype.zig").Archetype;
const ArchetypeSignature = @import("archetype.zig").ArchetypeSignature;
const Entity = @import("ecs.zig").Entity;
const archetypeSignatureHash = @import("archetype.zig").archetypeSignatureHash;
const archetypeSignatureEql = @import("archetype.zig").archetypeSignatureEql;
const SparseSet = @import("sparse_set.zig").SparseSet;

pub const Context = struct {
    pub fn hash(self: Context, key: ArchetypeSignature) u64 {
        _ = self;
        return key.hash();
    }
    pub fn eql(self: Context, a: ArchetypeSignature, b: ArchetypeSignature) bool {
        _ = self;
        return a.eql(b);
    }
};
const TypeInfo = @import("world.zig").TypeInfo;

pub const EntityMapEntry = struct { archetype: *Archetype, index: usize };

/// Manages all archetypes and entity-to-archetype mapping
pub const ArchetypeStorage = struct {
    allocator: std.mem.Allocator,
    // Map: ArchetypeSignature -> *Archetype
    archetypes: std.HashMap(ArchetypeSignature, *Archetype, Context, 80),

    entity_sparse_set: SparseSet(EntityMapEntry),

    pub fn init(allocator: std.mem.Allocator) ArchetypeStorage {
        const archetypes_map = std.HashMap(ArchetypeSignature, *Archetype, Context, 80).init(allocator);
        // Pre-allocate sparse set capacity for better performance
        const sparse_set = SparseSet(EntityMapEntry).initCapacity(allocator, 100000) catch SparseSet(EntityMapEntry).init(allocator);
        return ArchetypeStorage{
            .allocator = allocator,
            .archetypes = archetypes_map,
            .entity_sparse_set = sparse_set,
        };
    }

    pub fn deinit(self: *ArchetypeStorage) void {
        var it = self.archetypes.valueIterator();
        while (it.next()) |archetype| {
            archetype.*.deinit();
        }
        self.archetypes.deinit();
        self.entity_sparse_set.deinit();
    }

    /// Get or create an archetype for the given signature and component sizes
    pub fn getOrCreate(self: *ArchetypeStorage, signature: ArchetypeSignature, component_sizes: []const usize) !*Archetype {
        if (self.archetypes.get(signature)) |archetype| {
            return archetype;
        } else {
            // Always pass signature with heap-allocated types to Archetype.init
            const types_len = signature.types.len;
            const types_heap = try self.allocator.alloc(u64, types_len);
            std.mem.copyForwards(u64, types_heap, signature.types);
            const heap_sig = ArchetypeSignature{ .types = types_heap };
            const new_archetype = try Archetype.init(self.allocator, heap_sig, component_sizes);
            try self.archetypes.put(heap_sig, new_archetype);
            return new_archetype;
        }
    }

    /// Add an entity to the archetype with the given signature and component data
    pub fn add(self: *ArchetypeStorage, entity: Entity, signature: ArchetypeSignature, component_sizes: []const usize, component_data: [][]const u8) error{OutOfMemory}!void {
        const archetype = try self.getOrCreate(signature, component_sizes);
        try archetype.addEntity(entity, component_data);
        const idx = archetype.entities.items.len - 1;

        try self.entity_sparse_set.set(entity.id, EntityMapEntry{ .archetype = archetype, .index = idx });
    }

    /// Get entity map entry (archetype + index)
    pub fn get(self: *ArchetypeStorage, entity: Entity) ?EntityMapEntry {
        return self.entity_sparse_set.get(entity.id);
    }

    /// Update entity map entry
    pub fn set(self: *ArchetypeStorage, entity: Entity, entry: EntityMapEntry) !void {
        try self.entity_sparse_set.set(entity.id, entry);
    }

    /// Remove entity from map
    pub fn remove(self: *ArchetypeStorage, entity: Entity) void {
        self.entity_sparse_set.remove(entity.id);
    }

    pub fn getArchetype(self: *ArchetypeStorage, entity: Entity) ?*Archetype {
        if (self.entity_sparse_set.get(entity.id)) |entry| {
            return entry.archetype;
        }
        return null;
    }

    /// Get count of tracked entities
    pub fn entityCount(self: *ArchetypeStorage) usize {
        return self.entity_sparse_set.count();
    }

    /// Iterate over all entity entries (cache-friendly, no null checks)
    pub fn entityIterator(self: *ArchetypeStorage) SparseSet(EntityMapEntry).Iterator {
        return self.entity_sparse_set.iterator();
    }
};
