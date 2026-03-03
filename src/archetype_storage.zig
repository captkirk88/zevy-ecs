const std = @import("std");
const hash = std.hash;
const errors = @import("errors.zig");
const zevy_mem = @import("zevy_mem");
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
    inner: *zevy_mem.lock.RwLock(Inner),

    pub const Inner = struct {
        // Map: ArchetypeSignature -> *Archetype
        archetypes: std.HashMap(ArchetypeSignature, *Archetype, Context, 80),
        entity_sparse_set: SparseSet(EntityMapEntry),
    };

    pub const ReadGuard = zevy_mem.lock.RwLock(Inner).ReadGuard;
    pub const WriteGuard = zevy_mem.lock.RwLock(Inner).WriteGuard;

    pub const EntityIterator = struct {
        guard: ReadGuard,
        iter: SparseSet(EntityMapEntry).Iterator,

        pub fn next(self: *EntityIterator) ?SparseSet(EntityMapEntry).Entry {
            return self.iter.next();
        }

        pub fn deinit(self: *EntityIterator) void {
            self.guard.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator) ArchetypeStorage {
        const archetypes_map = std.HashMap(ArchetypeSignature, *Archetype, Context, 80).init(allocator);
        // Pre-allocate sparse set capacity for better performance
        const sparse_set = SparseSet(EntityMapEntry).initCapacity(allocator, 100000) catch SparseSet(EntityMapEntry).init(allocator);
        const inner = Inner{
            .archetypes = archetypes_map,
            .entity_sparse_set = sparse_set,
        };
        const lock = zevy_mem.lock.RwLock(Inner).init(allocator, inner) catch @panic("Failed to init archetype storage lock");
        return ArchetypeStorage{
            .allocator = allocator,
            .inner = lock,
        };
    }

    pub fn deinit(self: *ArchetypeStorage) void {
        var guard = self.inner.lockWrite();
        const storage = guard.get();
        var it = storage.archetypes.valueIterator();
        while (it.next()) |archetype| {
            archetype.*.deinit();
        }
        storage.archetypes.deinit();
        storage.entity_sparse_set.deinit();
        guard.deinit();
        self.inner.deinit();
    }

    pub fn readGuard(self: *ArchetypeStorage) ReadGuard {
        return self.inner.lockRead();
    }

    pub fn writeGuard(self: *ArchetypeStorage) WriteGuard {
        return self.inner.lockWrite();
    }

    /// Get or create an archetype for the given signature and component sizes
    pub fn getOrCreate(self: *ArchetypeStorage, signature: ArchetypeSignature, component_sizes: []const usize) !*Archetype {
        var guard = self.inner.lockWrite();
        defer guard.deinit();
        return try self.getOrCreateWithStorage(guard.get(), signature, component_sizes);
    }

    pub fn getOrCreateWithStorage(self: *ArchetypeStorage, storage: *Inner, signature: ArchetypeSignature, component_sizes: []const usize) !*Archetype {
        if (storage.archetypes.get(signature)) |archetype| {
            return archetype;
        } else {
            // Always pass signature with heap-allocated types to Archetype.init
            const types_len = signature.types.len;
            const types_heap = try self.allocator.alloc(u64, types_len);
            std.mem.copyForwards(u64, types_heap, signature.types);
            const heap_sig = ArchetypeSignature{ .types = types_heap };
            const new_archetype = try Archetype.init(self.allocator, heap_sig, component_sizes);
            try storage.archetypes.put(heap_sig, new_archetype);
            return new_archetype;
        }
    }

    /// Add an entity to the archetype with the given signature and component data
    pub fn add(self: *ArchetypeStorage, entity: Entity, signature: ArchetypeSignature, component_sizes: []const usize, component_data: [][]const u8) error{OutOfMemory}!void {
        var guard = self.inner.lockWrite();
        defer guard.deinit();
        try self.addWithStorage(guard.get(), entity, signature, component_sizes, component_data);
    }

    pub fn addWithStorage(self: *ArchetypeStorage, storage: *Inner, entity: Entity, signature: ArchetypeSignature, component_sizes: []const usize, component_data: [][]const u8) error{OutOfMemory}!void {
        const archetype = try self.getOrCreateWithStorage(storage, signature, component_sizes);
        try archetype.addEntity(entity, component_data);
        const idx = archetype.entities.items.len - 1;
        try storage.entity_sparse_set.set(entity.id, EntityMapEntry{ .archetype = archetype, .index = idx });
    }

    /// Get entity map entry (archetype + index)
    pub fn get(self: *ArchetypeStorage, entity: Entity) ?EntityMapEntry {
        var guard = self.inner.lockRead();
        defer guard.deinit();
        return guard.get().entity_sparse_set.get(entity.id);
    }

    pub fn getWithStorage(storage: *const Inner, entity: Entity) ?EntityMapEntry {
        return storage.entity_sparse_set.get(entity.id);
    }

    /// Update entity map entry
    pub fn set(self: *ArchetypeStorage, entity: Entity, entry: EntityMapEntry) !void {
        var guard = self.inner.lockWrite();
        defer guard.deinit();
        try guard.get().entity_sparse_set.set(entity.id, entry);
    }

    pub fn setWithStorage(storage: *Inner, entity: Entity, entry: EntityMapEntry) !void {
        try storage.entity_sparse_set.set(entity.id, entry);
    }

    pub fn insertManyWithStorage(storage: *Inner, ids: []const u32, entries: []const EntityMapEntry) !void {
        try storage.entity_sparse_set.insertMany(ids, entries);
    }

    /// Remove entity from map
    pub fn remove(self: *ArchetypeStorage, entity: Entity) void {
        var guard = self.inner.lockWrite();
        defer guard.deinit();
        guard.get().entity_sparse_set.remove(entity.id);
    }

    pub fn removeWithStorage(storage: *Inner, entity: Entity) void {
        storage.entity_sparse_set.remove(entity.id);
    }

    pub fn getArchetype(self: *ArchetypeStorage, entity: Entity) ?*Archetype {
        var guard = self.inner.lockRead();
        if (guard.get().entity_sparse_set.get(entity.id)) |entry| {
            const archetype = entry.archetype;
            guard.deinit();
            return archetype;
        }
        guard.deinit();
        return null;
    }

    pub const ArchetypeRead = struct {
        guard: ReadGuard,
        archetype: *Archetype,

        pub fn deinit(self: *ArchetypeRead) void {
            self.guard.deinit();
        }
    };

    pub fn getArchetypeRead(self: *ArchetypeStorage, entity: Entity) ?ArchetypeRead {
        var guard = self.inner.lockRead();
        if (guard.get().entity_sparse_set.get(entity.id)) |entry| {
            return .{ .guard = guard, .archetype = entry.archetype };
        }
        guard.deinit();
        return null;
    }

    /// Get count of tracked entities
    pub fn entityCount(self: *ArchetypeStorage) usize {
        var guard = self.inner.lockRead();
        defer guard.deinit();
        return guard.get().entity_sparse_set.count();
    }

    /// Iterate over all entity entries (cache-friendly, no null checks)
    pub fn entityIterator(self: *ArchetypeStorage) EntityIterator {
        var guard = self.inner.lockRead();
        return .{ .guard = guard, .iter = guard.get().entity_sparse_set.iterator() };
    }
};
