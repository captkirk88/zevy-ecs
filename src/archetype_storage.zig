const std = @import("std");
const hash = std.hash;
const errors = @import("errors.zig");
const Archetype = @import("archetype.zig").Archetype;
const ArchetypeSignature = @import("archetype.zig").ArchetypeSignature;
const Entity = @import("ecs.zig").Entity;
const archetypeSignatureHash = @import("archetype.zig").archetypeSignatureHash;
const archetypeSignatureEql = @import("archetype.zig").archetypeSignatureEql;

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
    // Sparse array: Entity ID -> (archetype ptr, index in archetype)
    // Much faster than HashMap for entity lookups
    entity_sparse_array: std.ArrayList(?EntityMapEntry),

    pub fn init(allocator: std.mem.Allocator) ArchetypeStorage {
        // Pre-allocate sparse array capacity for better performance
        const archetypes_map = std.HashMap(ArchetypeSignature, *Archetype, Context, 80).init(allocator);
        const sparse_array = std.ArrayList(?EntityMapEntry).initCapacity(allocator, 100000) catch std.ArrayList(?EntityMapEntry).initCapacity(allocator, 0) catch unreachable;
        return ArchetypeStorage{
            .allocator = allocator,
            .archetypes = archetypes_map,
            .entity_sparse_array = sparse_array,
        };
    }

    pub fn deinit(self: *ArchetypeStorage) void {
        var it = self.archetypes.valueIterator();
        while (it.next()) |archetype| {
            archetype.*.deinit();
        }
        self.archetypes.deinit();
        self.entity_sparse_array.deinit(self.allocator);
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
    pub fn add(self: *ArchetypeStorage, entity: Entity, signature: ArchetypeSignature, component_sizes: []const usize, component_data: [][]const u8) !void {
        const archetype = try self.getOrCreate(signature, component_sizes);
        try archetype.addEntity(entity, component_data);
        const idx = archetype.entities.items.len - 1;

        // Ensure sparse array has enough capacity
        const entity_id = entity.id;
        while (self.entity_sparse_array.items.len <= entity_id) {
            try self.entity_sparse_array.append(self.allocator, null);
        }
        self.entity_sparse_array.items[entity_id] = EntityMapEntry{ .archetype = archetype, .index = idx };
    }

    /// Get entity map entry (archetype + index)
    pub fn get(self: *ArchetypeStorage, entity: Entity) ?EntityMapEntry {
        if (entity.id < self.entity_sparse_array.items.len) {
            return self.entity_sparse_array.items[entity.id];
        }
        return null;
    }

    /// Update entity map entry - UNSAFE: direct write after ensuring capacity
    pub fn set(self: *ArchetypeStorage, entity: Entity, entry: EntityMapEntry) !void {
        const entity_id = entity.id;
        // Ensure capacity in one shot instead of append loop
        if (entity_id >= self.entity_sparse_array.items.len) {
            const needed = entity_id + 1 - self.entity_sparse_array.items.len;
            try self.entity_sparse_array.ensureUnusedCapacity(self.allocator, needed);
            const old_len = self.entity_sparse_array.items.len;
            self.entity_sparse_array.items.len = entity_id + 1;
            // Initialize new slots to null
            @memset(self.entity_sparse_array.items[old_len .. entity_id + 1], null);
        }
        self.entity_sparse_array.items[entity_id] = entry;
    }

    /// Remove entity from map
    pub fn remove(self: *ArchetypeStorage, entity: Entity) void {
        if (entity.id < self.entity_sparse_array.items.len) {
            self.entity_sparse_array.items[entity.id] = null;
        }
    }

    pub fn getArchetype(self: *ArchetypeStorage, entity: Entity) ?*Archetype {
        if (entity.id < self.entity_sparse_array.items.len) {
            if (self.entity_sparse_array.items[entity.id]) |entry| {
                return entry.archetype;
            }
        }
        return null;
    }
};
