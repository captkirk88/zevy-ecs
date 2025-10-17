const std = @import("std");
const world = @import("world.zig");
const World = world.World;
const qry = @import("query.zig");
const errs = @import("errors.zig");
const hash = std.hash;
const sys = @import("systems.zig");
const registry = @import("systems.registry.zig");

pub const errors = errs.ECSError;

pub const Entity = struct {
    id: u32,
    generation: u32,

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

const ResourceEntry = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    allocated: bool,
    size: usize,
    alignment: std.mem.Alignment,
    deinit_fn: ?*const fn (*anyopaque, std.mem.Allocator) void,

    pub fn deinit(self: *ResourceEntry, allocator: std.mem.Allocator) void {
        // Call custom deinit function if provided
        if (self.deinit_fn) |deinit_fn| {
            deinit_fn(self.ptr, allocator);
        }
        // Free the memory if it was allocated
        if (self.allocated) {
            const slice = @as([*]u8, @ptrCast(@alignCast(self.ptr)))[0..self.size];
            allocator.rawFree(slice, self.alignment, @returnAddress());
        }
    }
};

pub const SystemHandle = sys.SystemHandle;

pub const Manager = struct {
    allocator: std.mem.Allocator,
    next_entity_id: u32,
    generations: std.ArrayList(u32), // Generation per entity ID
    free_ids: std.ArrayList(u32), // Reusable entity IDs
    world: World, // Manages archetypes and component storage
    resources: std.AutoHashMap(u64, ResourceEntry), // TypeHash -> ResourceEntry
    systems: std.ArrayList(?*anyopaque), // Stored systems

    /// Initialize the ECS with an optional custom allocator.
    /// If no allocator is provided, the default page allocator is used.
    pub fn init(allocator: std.mem.Allocator) !Manager {
        return Manager{
            .allocator = allocator,
            .next_entity_id = 0,
            .generations = try std.ArrayList(u32).initCapacity(allocator, 1024),
            .free_ids = try std.ArrayList(u32).initCapacity(allocator, 256),
            .world = World.init(allocator),
            .resources = std.AutoHashMap(u64, ResourceEntry).init(allocator),
            .systems = try std.ArrayList(?*anyopaque).initCapacity(allocator, 64),
        };
    }

    pub fn deinit(self: *Manager) void {
        self.generations.deinit(self.allocator);
        self.free_ids.deinit(self.allocator);
        self.world.deinit();
        var res_it = self.resources.valueIterator();
        while (res_it.next()) |entry| {
            if (entry.allocated) {
                entry.deinit(self.allocator);
            }
        }
        self.resources.deinit();

        for (self.systems.items) |item| {
            if (item) |p| {
                const system: *sys.System(void) = @ptrCast(@alignCast(p));
                self.allocator.destroy(system);
            }
        }
        self.systems.deinit(self.allocator);
    }

    /// Get the total number of alive entities
    pub fn count(self: *Manager) usize {
        return self.generations.items.len - self.free_ids.items.len;
    }

    /// Create an empty entity with no components
    pub fn createEmpty(self: *Manager) Entity {
        const entity = if (self.free_ids.pop()) |id| blk: {
            break :blk Entity{ .id = id, .generation = self.generations.items[id] };
        } else blk: {
            const id = self.next_entity_id;
            self.next_entity_id += 1;
            self.generations.append(self.allocator, 0) catch {
                @panic("Failed to allocate memory for new entity generation");
            };
            break :blk Entity{ .id = id, .generation = 0 };
        };

        // Register the entity in the archetype system with no components
        const empty_components = .{};
        self.world.add(entity, @TypeOf(empty_components), empty_components) catch @panic("Failed to add empty entity to archetype storage");
        return entity;
    }

    /// Create an entity with the specified components
    ///
    /// Example:
    /// ```zig
    /// const entity = manager.create(.{ Position{ .x = 0, .y = 0 }, Velocity{ .x = 1, .y = 1 } });
    /// ```
    pub fn create(self: *Manager, components: anytype) Entity {
        // Allocate entity ID without adding to archetype yet
        const entity = if (self.free_ids.pop()) |id| blk: {
            break :blk Entity{ .id = id, .generation = self.generations.items[id] };
        } else blk: {
            const id = self.next_entity_id;
            self.next_entity_id += 1;
            self.generations.append(self.allocator, 0) catch {
                @panic("Failed to allocate memory for new entity generation");
            };
            break :blk Entity{ .id = id, .generation = 0 };
        };

        // Add entity directly to its target archetype
        const components_type = @TypeOf(components);
        if (@typeInfo(components_type) == .null) {
            const empty_components = .{};
            self.world.add(entity, @TypeOf(empty_components), empty_components) catch @panic("Failed to add entity to archetype storage");
        } else {
            self.world.add(entity, components_type, components) catch @panic("Failed to add entity to archetype storage");
        }
        return entity;
    }

    /// Batch create multiple entities with the same components (much faster than calling create() in a loop)
    /// Returns a slice that must be freed by the caller using allocator.free()
    pub fn createBatch(self: *Manager, allocator: std.mem.Allocator, entity_count: usize, components: anytype) ![]Entity {
        if (entity_count == 0) return &[_]Entity{};

        // Allocate entity IDs in batch
        var entities = try std.ArrayList(Entity).initCapacity(allocator, entity_count);
        errdefer entities.deinit(allocator);

        for (0..entity_count) |_| {
            const entity = if (self.free_ids.pop()) |id| blk: {
                break :blk Entity{ .id = id, .generation = self.generations.items[id] };
            } else blk: {
                const id = self.next_entity_id;
                self.next_entity_id += 1;
                try self.generations.append(allocator, 0);
                break :blk Entity{ .id = id, .generation = 0 };
            };
            entities.appendAssumeCapacity(entity);
        }

        // Add all entities to archetype in one batch
        try self.world.addBatch(entities.items, @TypeOf(components), components);

        // Return owned slice
        return entities.toOwnedSlice(allocator);
    }

    /// Check if an entity is alive (not deleted)
    pub fn isAlive(self: *Manager, entity: Entity) bool {
        return entity.id < self.generations.items.len and entity.generation == self.generations.items[entity.id];
    }

    /// Add a component of type T to the given entity, or an error if entity is dead.
    pub fn addComponent(self: *Manager, entity: Entity, comptime T: type, value: T) error{ EntityNotAlive, OutOfMemory }!void {
        if (!self.isAlive(entity)) return errs.ECSError.EntityNotAlive;
        const tuple = .{value};
        try self.world.add(entity, @TypeOf(tuple), tuple);
    }

    /// Remove a component of type T from the given entity, or an error if not found or entity is dead.
    pub fn removeComponent(self: *Manager, entity: Entity, comptime T: type) error{ EntityNotAlive, OutOfMemory }!void {
        if (!self.isAlive(entity)) return errs.ECSError.EntityNotAlive;
        try self.world.removeComponent(entity, T);
    }

    /// Get a mutable pointer to a component of type T for the given entity, or an error if not found or entity is dead.
    pub fn getComponent(self: *Manager, entity: Entity, comptime T: type) error{EntityNotAlive}!?*T {
        if (!self.isAlive(entity)) return errs.ECSError.EntityNotAlive;
        return self.world.get(entity, T);
    }

    /// Check if an entity has a component of type T
    pub fn hasComponent(self: *Manager, entity: Entity, comptime T: type) error{EntityNotAlive}!bool {
        if (!self.isAlive(entity)) return errs.ECSError.EntityNotAlive;
        return self.world.has(entity, T);
    }

    /// Get all components for an entity as an array of ComponentInstance
    /// Caller is responsible for freeing the returned array
    /// Returns an error if the entity is not alive
    pub fn getAllComponents(self: *Manager, allocator: std.mem.Allocator, entity: Entity) error{ EntityNotAlive, OutOfMemory }![]world.ComponentInstance {
        if (!self.isAlive(entity)) return errs.ECSError.EntityNotAlive;
        return self.world.getAllComponents(allocator, entity);
    }

    /// Add or update a resource.
    /// Resources must be value types (no pointers allowed).
    ///
    /// *Recommended to use Plain Old Data (POD) types only or manage memory manually.*
    ///
    /// Example:
    /// ```zig
    /// const res = manager.addResource(MyResourceType, MyResourceType{ .value = 42 }) catch |err| {
    ///     // Handle error
    ///     return;
    /// };
    /// res.* = MyResourceType{ .value = 100 }; // Update resource
    /// ```
    pub fn addResource(self: *Manager, comptime T: type, value: T) error{ OutOfMemory, ResourceAlreadyExists }!*T {
        // Reject pointer types to avoid complexity
        if (@typeInfo(T) == .pointer) {
            @compileError("addResource does not accept pointer types. Use value types only.");
        }

        const type_hash = hash.Wyhash.hash(0, @typeName(T));
        const result = try self.resources.getOrPut(type_hash);
        if (!result.found_existing) {
            const ptr = try self.allocator.create(T);
            ptr.* = value;

            // Check if the type has a deinit method
            const type_info = @typeInfo(T);
            const has_deinit = if (type_info == .@"struct") @hasDecl(T, "deinit") else false;
            const deinit_fn = if (has_deinit) blk: {
                const deinit_fn_ptr = struct {
                    pub fn deinit(resource_ptr: *anyopaque, allocator: std.mem.Allocator) void {
                        const typed_ptr: *T = @ptrCast(@alignCast(resource_ptr));
                        // Check if deinit takes an allocator parameter
                        const deinit_info = @typeInfo(@TypeOf(T.deinit));
                        if (deinit_info == .@"fn" and deinit_info.@"fn".params.len == 2) {
                            typed_ptr.deinit(allocator);
                        } else {
                            typed_ptr.deinit();
                        }
                    }
                }.deinit;
                break :blk deinit_fn_ptr;
            } else null;

            try self.resources.put(type_hash, ResourceEntry{
                .ptr = @ptrCast(ptr),
                .type_name = @typeName(T),
                .allocated = true,
                .size = @sizeOf(T),
                .alignment = std.mem.Alignment.of(T),
                .deinit_fn = deinit_fn,
            });
            return ptr;
        } else {
            return error.ResourceAlreadyExists;
        }
    }

    /// Get a mutable pointer to a resource of type T, or null if it doesn't exist.
    ///
    /// Example:
    /// ```zig
    /// if (manager.getResource(MyResourceType)) |r| {
    ///     // Use resource
    ///     r.* = MyResourceType{ .value = 100 }; // Update resource
    /// } else {
    ///     // Resource not found
    /// }
    pub fn getResource(self: *Manager, comptime T: type) ?*T {
        return self.getResourcePtr(T);
    }

    fn getResourcePtr(self: *Manager, comptime T: type) ?*T {
        const type_hash = hash.Wyhash.hash(0, @typeName(T));
        if (self.resources.get(type_hash)) |entry| {
            return @ptrCast(@alignCast(entry.ptr));
        }
        return null;
    }

    /// Check if a resource of type T exists.
    pub fn hasResource(self: *Manager, comptime T: type) bool {
        const type_hash = hash.Wyhash.hash(0, @typeName(T));
        return self.resources.contains(type_hash);
    }

    /// Remove and deallocate a resource.
    /// Only deallocates memory if it was allocated by addResource (allocated field is true).
    pub fn removeResource(self: *Manager, comptime T: type) void {
        const type_hash = hash.Wyhash.hash(0, @typeName(T));

        const res = self.resources.fetchRemove(type_hash) orelse return;

        // Only deallocate memory if we allocated it
        if (res.value.allocated) {
            const ptr = @as(*T, @ptrCast(@alignCast(res.value.ptr)));
            self.allocator.destroy(ptr);
        }
    }

    /// List all resource type names currently stored in the ECS.
    pub fn listResourceTypes(self: *Manager) std.ArrayList([]const u8) {
        var types = std.ArrayList([]const u8).initCapacity(self.allocator, self.resources.count()) catch |err| @panic(@errorName(err));
        var it = self.resources.valueIterator();
        while (it.next()) |resource| {
            types.append(self.allocator, resource.type_name) catch |err| @panic(@errorName(err));
        }
        return types;
    }

    /// Create a query for iterating over entities with specified components.
    ///
    /// Example:
    /// ```zig
    /// const query = manager.query(struct{pos: Position, vel: Velocity}, struct{});
    /// while (query.next()) |q| {
    ///     const pos: *Position = q.pos;
    ///     const vel: *Velocity = q.vel;
    ///     // Process components
    /// }
    /// ```
    pub fn query(self: *Manager, comptime types: anytype, comptime exclude: anytype) qry.Query(types, exclude) {
        return self.world.query(types, exclude);
    }

    /// Create a system from a function and parameter registry.
    /// The system function should match the expected signature for systems.
    ///
    /// Example:
    /// ```zig
    /// fn my_system(manager: *Manager, res: Res(MyResourceType), query: Query(.{Position, Velocity}, .{})) void {
    ///     // System logic here
    /// }
    ///
    /// const system = manager.createSystem(my_system, DefaultRegistry);
    /// ```
    pub fn createSystem(_: *Manager, comptime system_fn: anytype, comptime ParamRegistry: type) sys.System(sys.ToSystemReturnType(system_fn)) {
        return sys.ToSystem(system_fn, ParamRegistry);
    }

    /// Create and cache a system from a function and parameter registry.
    /// The system function should match the expected signature for systems (see `createSystem`).
    /// The returned SystemHandle can be used to run the system later.
    pub fn createSystemCached(self: *Manager, comptime system_fn: anytype, comptime ParamRegistry: type) SystemHandle {
        const s = self.createSystem(system_fn, ParamRegistry);
        const sys_ptr = self.allocator.create(@TypeOf(s)) catch |err| @panic(@errorName(err));
        sys_ptr.* = s;
        const anyopaque_ptr: ?*anyopaque = @ptrCast(sys_ptr);
        self.systems.append(self.allocator, anyopaque_ptr) catch |err| @panic(@errorName(err));
        const handle: SystemHandle = self.systems.items.len - 1;
        std.log.debug("Created system handle {} for function: {s}", .{ handle, @typeName(@TypeOf(system_fn)) });
        return handle;
    }

    /// Run a cached system by its SystemHandle.
    pub fn runSystem(self: *Manager, comptime ReturnType: type, sys_handle: SystemHandle) anyerror!ReturnType {
        if (sys_handle >= self.systems.items.len) return error.InvalidSystemHandle;
        const sys_ptr = self.systems.items[sys_handle];
        if (sys_ptr == null) return error.NullSystemPointer;
        const s: *sys.System(ReturnType) = @ptrCast(@alignCast(sys_ptr.?));
        return try s.run(self, s.ctx);
    }

    /// Cache an existing system pointer.
    /// The returned SystemHandle can be used to run the system later.
    pub fn cacheSystem(self: *Manager, comptime RT: type, system: *sys.System(RT)) SystemHandle {
        const sys_ptr = @constCast(system);
        const anyopaque_ptr: ?*anyopaque = @ptrCast(sys_ptr);
        self.systems.append(self.allocator, anyopaque_ptr) catch |err| @panic(@errorName(err));
        return SystemHandle{ .handle = self.systems.items.len - 1 };
    }
};

test "Query with just Entity" {
    var ecs_instance = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_instance.deinit();
    const amount = 100;
    for (0..amount) |_| {
        _ = ecs_instance.createEmpty();
    }

    var query = ecs_instance.query(struct { entity: Entity }, struct {});
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
    std.debug.print("Counted {d} entities\n", .{count});
    try std.testing.expect(count == amount);
}

test "Create entity using create() with null or empty" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();
    const amount = 100;
    for (0..amount) |_| {
        _ = ecs.create(null);
        _ = ecs.create(.{});
    }

    var query = ecs.query(struct { entity: Entity }, struct {});
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
    std.debug.print("Counted {d} entities\n", .{count});
}
