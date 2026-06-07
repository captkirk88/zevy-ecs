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

/// Erased deinit function for a single component instance.
/// Called with a type-erased pointer to the component and the world allocator.
pub const ComponentDeinitFn = *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void;

/// Stores all entities with the same component set (archetype)
pub const Archetype = struct {
    allocator: std.mem.Allocator,
    signature: ArchetypeSignature,
    entities: std.ArrayList(Entity),
    // For each component type, a contiguous array of bytes
    component_arrays: []std.ArrayList(u8),
    component_sizes: []usize,
    // Per-component deinit fn pointer; null when the component type has no deinit method.
    // Set by world.zig after archetype creation when types are known at compile time.
    component_deinit_fns: []?ComponentDeinitFn,

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
            .entities = (std.ArrayList(Entity).initCapacity(allocator, initial_capacity) catch |err| {
                std.debug.panic("Failed to allocate entities list for archetype with capacity {d}: {s}", .{ initial_capacity, @errorName(err) });
            }),
            .component_arrays = try allocator.alloc(std.ArrayList(u8), component_sizes.len),
            .component_sizes = try allocator.alloc(usize, component_sizes.len),
            .component_deinit_fns = try allocator.alloc(?ComponentDeinitFn, component_sizes.len),
        };
        @memset(archetype.component_deinit_fns, null);
        for (component_sizes, 0..) |size, i| {
            const byte_capacity = initial_capacity * size;
            archetype.component_arrays[i] = (std.ArrayList(u8).initCapacity(allocator, byte_capacity) catch |err| {
                std.debug.panic("Failed to allocate component array for archetype (component {d}, capacity {d} bytes): {s}", .{ i, byte_capacity, @errorName(err) });
            });
            archetype.component_sizes[i] = size;
        }
        return archetype;
    }

    pub fn deinit(self: *Archetype) void {
        // Call component deinit for every entity still in this archetype
        for (0..self.entities.items.len) |entity_idx| {
            self.callDeinitAt(entity_idx);
        }
        self.entities.deinit(self.allocator);
        for (self.component_arrays) |*arr| arr.deinit(self.allocator);
        self.allocator.free(self.component_arrays);
        self.allocator.free(self.component_sizes);
        self.allocator.free(self.component_deinit_fns);
        self.allocator.free(self.signature.types);
        self.allocator.destroy(self);
    }

    /// Call the deinit fn for every component of the entity at `entity_idx`.
    /// No-op for components whose type has no deinit method.
    pub fn callDeinitAt(self: *const Archetype, entity_idx: usize) void {
        for (self.component_deinit_fns, 0..) |maybe_fn, comp_idx| {
            if (maybe_fn) |deinit_fn| {
                const comp_size = self.component_sizes[comp_idx];
                const ptr: *anyopaque = @ptrCast(self.component_arrays[comp_idx].items.ptr + entity_idx * comp_size);
                deinit_fn(ptr, self.allocator);
            }
        }
    }

    /// Add an entity and its component data to this archetype
    /// `component_data` is an array of pointers to bytes, one per component type, matching the signature order
    pub fn addEntity(self: *Archetype, entity: Entity, component_data: [][]const u8) !void {
        try self.entities.append(self.allocator, entity);
        var appended_count: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < appended_count) : (i += 1) {
                self.component_arrays[i].items.len -= self.component_sizes[i];
            }
            self.entities.items.len -= 1;
        }

        for (component_data, 0..) |data, i| {
            const size = self.component_sizes[i];
            const arr = &self.component_arrays[i];
            try arr.appendSlice(self.allocator, data[0..size]);
            appended_count += 1;
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
