const std = @import("std");
const ecs = @import("ecs.zig");
const systems = @import("systems.zig");
const Entity = ecs.Entity;

/// Configuration for how a relation type should behave
pub const RelationConfig = struct {
    /// Whether this relation type should maintain an index for fast reverse lookups
    indexed: bool = false,

    /// Whether multiple relations of this type are allowed per entity
    /// If false, adding a second relation replaces the first
    exclusive: bool = true,
};

/// Non-indexed relation
pub const AttachedTo = struct {};

/// Indexed exclusive relation (parent-child)
pub const Child = struct {
    pub const relation_config = RelationConfig{
        .indexed = true,
        .exclusive = true,
    };
};

/// Indexed non-exclusive relation (ownership)
pub const Owns = struct {
    pub const relation_config = RelationConfig{
        .indexed = true,
        .exclusive = false,
    };
};

/// Relation component
pub fn Relation(comptime Kind: type) type {
    return struct {
        target: Entity,
        data: Kind,

        pub const relation_kind = Kind;

        /// Get config from Kind type or use defaults
        pub const config: RelationConfig = if (@hasDecl(Kind, "relation_config"))
            Kind.relation_config
        else
            RelationConfig{};

        pub fn init(target: Entity, data: Kind) Relation(Kind) {
            return .{
                .target = target,
                .data = data,
            };
        }
    };
}

/// Per-type relation index
const TypedRelationIndex = struct {
    allocator: std.mem.Allocator,

    // entity.id -> targets (outgoing relations)
    outgoing: std.AutoHashMap(u32, std.ArrayList(Entity)),

    // entity.id -> sources (incoming relations - for reverse queries)
    incoming: std.AutoHashMap(u32, std.ArrayList(Entity)),

    pub fn init(allocator: std.mem.Allocator) TypedRelationIndex {
        return .{
            .allocator = allocator,
            .outgoing = std.AutoHashMap(u32, std.ArrayList(Entity)).init(allocator),
            .incoming = std.AutoHashMap(u32, std.ArrayList(Entity)).init(allocator),
        };
    }

    pub fn deinit(self: *TypedRelationIndex) void {
        var out_it = self.outgoing.valueIterator();
        while (out_it.next()) |list| list.deinit(self.allocator);
        self.outgoing.deinit();

        var in_it = self.incoming.valueIterator();
        while (in_it.next()) |list| list.deinit(self.allocator);
        self.incoming.deinit();
    }

    /// Add a relation between entities
    pub fn add(self: *TypedRelationIndex, child: Entity, parent: Entity) !void {
        // Add to outgoing (child points to parent)
        const out_gop = try self.outgoing.getOrPut(child.id);
        if (!out_gop.found_existing) {
            out_gop.value_ptr.* = try std.ArrayList(Entity).initCapacity(self.allocator, 0);
        }
        try out_gop.value_ptr.append(self.allocator, parent);

        // Add to incoming (parent receives from child)
        const in_gop = try self.incoming.getOrPut(parent.id);
        if (!in_gop.found_existing) {
            in_gop.value_ptr.* = try std.ArrayList(Entity).initCapacity(self.allocator, 0);
        }
        try in_gop.value_ptr.append(self.allocator, child);
    }

    /// Remove a relation between entities
    pub fn remove(self: *TypedRelationIndex, child: Entity, parent: Entity) void {
        if (self.outgoing.getPtr(child.id)) |list| {
            for (list.items, 0..) |item, i| {
                if (item.eql(parent)) {
                    _ = list.swapRemove(i);
                    break;
                }
            }
        }

        if (self.incoming.getPtr(parent.id)) |list| {
            for (list.items, 0..) |item, i| {
                if (item.eql(child)) {
                    _ = list.swapRemove(i);
                    break;
                }
            }
        }
    }

    /// Get all parents of a child entity
    pub fn getParents(self: *TypedRelationIndex, child: Entity) []const Entity {
        if (self.outgoing.get(child.id)) |list| {
            return list.items;
        }
        return &[_]Entity{};
    }

    /// Get all children of a parent entity
    pub fn getChildren(self: *TypedRelationIndex, parent: Entity) []const Entity {
        if (self.incoming.get(parent.id)) |list| {
            return list.items;
        }
        return &[_]Entity{};
    }

    /// Clean up all relations for an entity
    pub fn removeEntity(self: *TypedRelationIndex, entity: Entity) void {
        // Remove outgoing and update parents' incoming
        if (self.outgoing.getPtr(entity.id)) |out_list| {
            for (out_list.items) |parent| {
                if (self.incoming.getPtr(parent.id)) |in_list| {
                    var i: usize = 0;
                    while (i < in_list.items.len) {
                        if (in_list.items[i].eql(entity)) {
                            _ = in_list.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }
            out_list.deinit(self.allocator);
            _ = self.outgoing.remove(entity.id);
        }

        // Remove incoming and update children's outgoing
        if (self.incoming.getPtr(entity.id)) |in_list| {
            for (in_list.items) |child| {
                if (self.outgoing.getPtr(child.id)) |out_list| {
                    var i: usize = 0;
                    while (i < out_list.items.len) {
                        if (out_list.items[i].eql(entity)) {
                            _ = out_list.swapRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }
            in_list.deinit(self.allocator);
            _ = self.incoming.remove(entity.id);
        }
    }
};

/// Manager for all relations
pub const RelationManager = struct {
    allocator: std.mem.Allocator,

    // type_hash -> index (lazy allocated, only for indexed types)
    indices: std.AutoHashMap(u64, *TypedRelationIndex),

    pub fn init(allocator: std.mem.Allocator) RelationManager {
        return .{
            .allocator = allocator,
            .indices = std.AutoHashMap(u64, *TypedRelationIndex).init(allocator),
        };
    }

    pub fn deinit(self: *RelationManager) void {
        var it = self.indices.valueIterator();
        while (it.next()) |index_ptr| {
            index_ptr.*.deinit();
            self.allocator.destroy(index_ptr.*);
        }
        self.indices.deinit();
    }

    /// Get or create index for a relation type (lazy allocation)
    pub fn getOrCreateIndex(self: *RelationManager, comptime Kind: type) !*TypedRelationIndex {
        const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(Kind));

        const gop = try self.indices.getOrPut(type_hash);
        if (!gop.found_existing) {
            const index = try self.allocator.create(TypedRelationIndex);
            index.* = TypedRelationIndex.init(self.allocator);
            gop.value_ptr.* = index;
        }
        return gop.value_ptr.*;
    }

    /// Check if a relation type has an index
    pub fn hasIndex(self: *RelationManager, comptime Kind: type) bool {
        const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(Kind));
        return self.indices.contains(type_hash);
    }

    /// Add a relation between entities
    /// For Child: add(manager, child, parent, Child) - child points to parent
    pub fn add(
        self: *RelationManager,
        manager: *ecs.Manager,
        child: Entity,
        parent: Entity,
        comptime Kind: type,
    ) !void {
        const config = comptime Relation(Kind).config;

        // Handle exclusive relations (replace existing)
        if (config.exclusive) {
            // Remove existing relation of this type if any
            if (try manager.getComponent(child, Relation(Kind))) |existing| {
                try self.remove(manager, child, existing.target, Kind);
            }
        }

        // For non-exclusive indexed relations, only use index (no component)
        // For non-indexed or exclusive relations, add component
        if (!config.indexed or config.exclusive) {
            try manager.addComponentRaw(child, Relation(Kind), .{ .target = parent, .data = .{} });
        }

        // Add to index if this type is configured as indexed
        if (config.indexed) {
            const index = try self.getOrCreateIndex(Kind);
            try index.add(child, parent);
        }
    }

    /// Add relation with custom data
    /// For Child: addWithData(manager, child, parent, Child, data)
    pub fn addWithData(
        self: *RelationManager,
        manager: *ecs.Manager,
        child: Entity,
        parent: Entity,
        comptime Kind: type,
        data: Kind,
    ) !void {
        const config = comptime Relation(Kind).config;

        if (config.exclusive) {
            if (try manager.getComponent(child, Relation(Kind))) |existing| {
                try self.remove(manager, child, existing.target, Kind);
            }
        }

        // For non-exclusive indexed relations, only use index (no component)
        // For non-indexed or exclusive relations, add component
        if (!config.indexed or config.exclusive) {
            try manager.addComponentRaw(child, Relation(Kind), .{
                .target = parent,
                .data = data,
            });
        }

        if (config.indexed) {
            const index = try self.getOrCreateIndex(Kind);
            try index.add(child, parent);
        }
    }

    /// Remove a relation
    pub fn remove(
        self: *RelationManager,
        manager: *ecs.Manager,
        child: Entity,
        parent: Entity,
        comptime Kind: type,
    ) !void {
        const config = comptime Relation(Kind).config;

        try manager.removeComponent(child, Relation(Kind));

        if (config.indexed and self.hasIndex(Kind)) {
            const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(Kind));
            if (self.indices.get(type_hash)) |index| {
                index.remove(child, parent);
            }
        }
    }

    /// Get all children of an entity (requires indexed relation type)
    pub fn getChildren(
        self: *RelationManager,
        parent: Entity,
        comptime Kind: type,
    ) []const Entity {
        const config = comptime Relation(Kind).config;

        if (!config.indexed) {
            @compileError(@typeName(Kind) ++ " is not indexed. Set indexed=true in relation_config.");
        }

        const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(Kind));
        if (self.indices.get(type_hash)) |index| {
            return index.getChildren(parent);
        }
        return &[_]Entity{};
    }

    /// Get all parents of an entity (requires indexed relation type)
    ///
    /// For a Child relation: getParents(child, Child) returns the parent
    ///
    /// For an Owns relation: getParents(item, Owns) returns all owners
    pub fn getParents(
        self: *RelationManager,
        child: Entity,
        comptime Kind: type,
    ) []const Entity {
        const config = comptime Relation(Kind).config;

        if (!config.indexed) {
            @compileError(@typeName(Kind) ++ " is not indexed. Set indexed=true in relation_config or use query instead.");
        }

        const type_hash = comptime std.hash.Wyhash.hash(0, @typeName(Kind));
        if (self.indices.get(type_hash)) |index| {
            return index.getParents(child);
        }
        return &[_]Entity{};
    }

    /// Get single parent of an entity (works for both indexed and non-indexed)
    pub fn getParent(
        self: *RelationManager,
        manager: *ecs.Manager,
        child: Entity,
        comptime Kind: type,
    ) error{EntityNotAlive}!?Entity {
        const config = comptime Relation(Kind).config;

        if (config.indexed) {
            const parents = self.getParents(child, Kind);
            return if (parents.len > 0) parents[0] else null;
        }

        if (try manager.getComponent(child, Relation(Kind))) |rel| {
            return rel.target;
        }
        return null;
    }

    /// Get single child (first child if multiple exist)
    /// For a Child relation: getChild(parent, Child) returns first child
    pub fn getChild(
        self: *RelationManager,
        _: *ecs.Manager,
        parent: Entity,
        comptime Kind: type,
    ) ?Entity {
        const config = comptime Relation(Kind).config;

        if (config.indexed) {
            const children = self.getChildren(parent, Kind);
            return if (children.len > 0) children[0] else null;
        } else {
            @compileError(@typeName(Kind) ++ " is not indexed. Use getParent for non-indexed relations.");
        }
    }

    /// Check if relation exists
    /// For Child: has(manager, child, parent, Child)
    pub fn has(
        self: *RelationManager,
        manager: *ecs.Manager,
        child: Entity,
        parent: Entity,
        comptime Kind: type,
    ) !bool {
        _ = self;
        if (try manager.getComponent(child, Relation(Kind))) |rel| {
            return rel.target.eql(parent);
        }
        return false;
    }

    /// Clean up all relations for an entity (called on entity destruction)
    pub fn removeEntity(self: *RelationManager, entity: Entity) void {
        var it = self.indices.valueIterator();
        while (it.next()) |index_ptr| {
            index_ptr.*.removeEntity(entity);
        }
    }

    /// Count total number of indices allocated
    pub fn indexCount(self: *RelationManager) usize {
        return self.indices.count();
    }
};
