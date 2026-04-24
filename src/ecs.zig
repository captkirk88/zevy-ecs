const std = @import("std");
const builtin = @import("builtin");
const reflect = @import("zevy_reflect");
const zevy_mem = @import("zevy_mem");
const world = @import("world.zig");
const World = world.World;
const serialize = @import("serialize.zig");
const qry = @import("query.zig");
const errs = @import("errors.zig");
const events = @import("events.zig");
const relations = @import("relations.zig");
const hash = std.hash;
const sys = @import("systems.zig");
const scheduler_mod = @import("scheduler.zig");
const params = @import("systems.params.zig");
const registry = @import("systems.registry.zig");
const command_buffer = @import("command_buffer.zig");

const is_debug = builtin.mode == .Debug;

pub const errors = errs.ECSError;

/// Entity type
pub const Entity = struct {
    id: u32,
    generation: u32,

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

pub const ResourceEntry = struct {
    ptr: *anyopaque,
    type_hash: u64,
    size: usize,
    deinit_fn: ?*const fn (*anyopaque) void,

    pub fn init(
        ptr: *anyopaque,
        type_hash: u64,
        size: usize,
        deinit_fn: ?*const fn (*anyopaque) void,
    ) ResourceEntry {
        return ResourceEntry{
            .ptr = ptr,
            .type_hash = type_hash,
            .size = size,
            .deinit_fn = deinit_fn,
        };
    }

    pub fn deinit(self: *ResourceEntry) void {
        if (self.deinit_fn) |deinit_fn| {
            deinit_fn(self.ptr);
        }
    }
};

const ResourceCodec = struct {
    size: usize,
    write_bytes_fn: *const fn (*const anyopaque, []u8) void,
    read_bytes_fn: *const fn (*anyopaque, []const u8) error{InvalidResourceData}!void,

    pub fn writeBytes(self: *const ResourceCodec, resource_ptr: *const anyopaque, dest: []u8) error{InvalidResourceData}!void {
        if (dest.len != self.size) return error.InvalidResourceData;
        self.write_bytes_fn(resource_ptr, dest);
    }

    pub fn readBytes(self: *const ResourceCodec, resource_ptr: *anyopaque, src: []const u8) error{InvalidResourceData}!void {
        if (src.len != self.size) return error.InvalidResourceData;
        try self.read_bytes_fn(resource_ptr, src);
    }
};

/// Reference-counted handle to an RwLock-protected resource or shared value.
/// Call `deinit()` when done to release the reference.
/// Call `lockRead()` or `lockWrite()` to access the value.
pub fn Ref(comptime T: type) type {
    return *zevy_mem.pointers.ArcRwLock(T);
}

/// ECS Manager responsible for entity lifecycle, archetype management, resources, and systems.
pub const Manager = struct {
    allocator: std.mem.Allocator,
    next_entity_id: u32,
    generations: std.ArrayList(u32), // Generation per entity ID
    free_ids: std.ArrayList(u32), // Reusable entity IDs
    world: World, // Manages archetypes and component storage
    resources: *zevy_mem.lock.Mutex(std.AutoHashMap(u64, ResourceEntry)), // TypeHash -> ResourceEntry
    resource_codecs: std.AutoHashMap(u64, ResourceCodec),
    systems: std.AutoHashMap(u64, *anyopaque), // SystemHash -> System pointer

    relations: Ref(relations.RelationManager),

    // Component lifecycle event stores
    component_added: events.EventStore(ComponentEvent),
    component_removed: events.EventStore(ComponentEvent),

    command_queue_mutex: std.Io.Mutex,
    queued_commands: std.ArrayList(command_buffer.CommandBuffer),
    defer_command_flush: std.atomic.Value(bool),

    /// Initialize the ECS with an optional custom allocator.
    /// If no allocator is provided, the default page allocator is used.
    pub fn init(allocator: std.mem.Allocator) !Manager {
        var manager = Manager{
            .allocator = allocator,
            .next_entity_id = 0,
            .generations = try std.ArrayList(u32).initCapacity(allocator, 1024),
            .free_ids = try std.ArrayList(u32).initCapacity(allocator, 256),
            .world = World.init(allocator),
            .resources = try zevy_mem.lock.Mutex(std.AutoHashMap(u64, ResourceEntry)).init(allocator, std.AutoHashMap(u64, ResourceEntry).init(allocator)),
            .resource_codecs = std.AutoHashMap(u64, ResourceCodec).init(allocator),
            .systems = std.AutoHashMap(u64, *anyopaque).init(allocator),
            .component_added = try events.EventStore(ComponentEvent).init(allocator, 64),
            .component_removed = try events.EventStore(ComponentEvent).init(allocator, 64),
            .command_queue_mutex = .init,
            .queued_commands = try std.ArrayList(command_buffer.CommandBuffer).initCapacity(allocator, 4),
            .defer_command_flush = std.atomic.Value(bool).init(false),
            .relations = undefined,
        };

        manager.relations = try manager.addResource(relations.RelationManager, relations.RelationManager.init(allocator));

        return manager;
    }

    pub fn deinit(self: *Manager) void {
        self.generations.deinit(self.allocator);
        self.free_ids.deinit(self.allocator);
        for (self.queued_commands.items) |*buffer| buffer.deinit(self.allocator);
        self.queued_commands.deinit(self.allocator);
        self.world.deinit();
        self.relations.deinit();
        var res_guard = self.resources.lock();
        var res_it = res_guard.get().valueIterator();
        while (res_it.next()) |entry| {
            entry.deinit();
        }
        res_guard.get().clearAndFree();
        res_guard.deinit();
        self.resources.deinit();
        self.resource_codecs.deinit();

        var sys_it = self.systems.valueIterator();
        while (sys_it.next()) |sys_ptr| {
            const system: *sys.System(void) = @ptrCast(@alignCast(sys_ptr.*));
            self.allocator.destroy(system);
        }
        self.systems.deinit();

        self.component_added.deinit();
        self.component_removed.deinit();
    }

    pub fn enqueueCommandBuffer(self: *Manager, buffer: command_buffer.CommandBuffer) error{OutOfMemory}!void {
        var owned_buffer = buffer;
        if (owned_buffer.isEmpty()) {
            owned_buffer.deinit(self.allocator);
            return;
        }

        std.Io.Threaded.mutexLock(&self.command_queue_mutex);
        defer std.Io.Threaded.mutexUnlock(&self.command_queue_mutex);
        try self.queued_commands.append(self.allocator, owned_buffer);
    }

    pub fn flushQueuedCommands(self: *Manager) anyerror!void {
        var first_err: ?anyerror = null;
        var pending = std.ArrayList(command_buffer.CommandBuffer).empty;
        defer pending.deinit(self.allocator);

        while (true) {
            std.Io.Threaded.mutexLock(&self.command_queue_mutex);
            const has_pending = self.queued_commands.items.len > 0;
            if (has_pending) {
                std.mem.swap(std.ArrayList(command_buffer.CommandBuffer), &pending, &self.queued_commands);
            }
            std.Io.Threaded.mutexUnlock(&self.command_queue_mutex);

            if (!has_pending) break;

            for (pending.items) |*buffer| {
                if (buffer.flush(self.allocator, @ptrCast(self))) |_| {} else |err| {
                    if (first_err == null) first_err = err;
                }
                buffer.deinit(self.allocator);
            }
            pending.clearAndFree(self.allocator);
        }

        if (first_err) |err| return err;
    }

    pub const ComponentEvent = struct {
        entity: Entity,
        type_hash: u64,
    };

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
        self.world.add(entity, empty_components) catch @panic("Failed to add empty entity to archetype storage");
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
            self.world.add(entity, empty_components) catch |err| std.debug.panic("Failed to add entity to archetype storage: {s}", .{@errorName(err)});
        } else {
            self.world.add(entity, components) catch |err| std.debug.panic("Failed to add entity to archetype storage: {s}", .{@errorName(err)});
        }
        return entity;
    }

    /// Create an entity from an array of ComponentInstance
    pub fn createFromComponents(self: *Manager, components: []const serialize.ComponentInstance) !Entity {
        // Allocate entity ID
        const entity = try self.allocateEntityId();

        if (components.len == 0) {
            // Empty entity
            const empty_components = .{};
            self.world.add(entity, empty_components) catch |err| std.debug.panic("Failed to add empty entity to archetype storage: {s}", .{@errorName(err)});
            return entity;
        }

        // Add entity to world with the component instances
        try self.world.addFromComponentInstances(entity, components);
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
        try self.world.addBatch(entities.items, components);

        // Return owned slice
        return entities.toOwnedSlice(allocator);
    }

    /// Check if an entity is alive (not deleted)
    pub fn isAlive(self: *Manager, entity: Entity) bool {
        return entity.id < self.generations.items.len and entity.generation == self.generations.items[entity.id];
    }

    pub fn destroy(self: *Manager, entity: Entity) error{ EntityNotAlive, OutOfMemory }!void {
        if (!self.isAlive(entity)) {
            return error.EntityNotAlive;
        }

        // Remove all relations involving this entity
        var rel_guard = self.relations.lockWrite();
        rel_guard.get().removeEntity(entity);
        rel_guard.deinit();

        // Remove from archetype storage
        self.world.remove(entity);

        // Invalidate entity by incrementing its generation
        self.generations.items[entity.id] += 1;

        // Add ID to free list for reuse
        try self.free_ids.append(self.allocator, entity.id);
    }

    /// Add a component of type T to the given entity, or an error if entity is dead.
    pub fn addComponent(self: *Manager, entity: Entity, comptime T: type, value: T) error{ EntityNotAlive, OutOfMemory }!void {
        if (@hasDecl(T, "relation_config")) {
            std.debug.panic("Use RelationManager methods to add/remove Relation components. type: {s}, entity: {d}", .{ comptime reflect.TypeInfo.from(T).toStringEx(true), entity.id });
        }
        return _addComponent(self, entity, T, value);
    }

    pub fn addComponentBatch(self: *Manager, entities: []const Entity, comptime T: type, values: []const T) error{ EntityNotAlive, OutOfMemory }!void {
        if (@hasDecl(T, "relation_config")) {
            std.debug.panic("Use RelationManager methods to add/remove Relation components. type: {s}", .{comptime reflect.TypeInfo.from(T).toStringEx(true)});
        }
        try _addComponentBatch(self, entities, T, values);
    }

    /// Remove a component of type T from the given entity, or an error if not found or entity is dead.
    pub fn removeComponent(self: *Manager, entity: Entity, comptime T: type) error{ EntityNotAlive, OutOfMemory }!void {
        if (@hasDecl(T, "relation_config")) {
            std.debug.panic("Use RelationManager methods to add/remove Relation components. type: {s}, entity: {d}", .{ comptime reflect.TypeInfo.from(T).toStringEx(true), entity.id });
        }
        return _removeComponent(self, entity, T);
    }

    pub fn removeComponentBatch(self: *Manager, entities: []const Entity, comptime T: type) error{ EntityNotAlive, OutOfMemory }!void {
        if (@hasDecl(T, "relation_config")) {
            std.debug.panic("Use RelationManager methods to add/remove Relation components. type: {s}", .{comptime reflect.TypeInfo.from(T).toStringEx(true)});
        }
        try _removeComponentBatch(self, entities, T);
    }

    /// Get a mutable pointer to a component of type T for the given entity, or an error if entity is not alive.
    pub fn getComponent(self: *Manager, entity: Entity, comptime T: type) error{EntityNotAlive}!?*T {
        if (!self.isAlive(entity)) return error.EntityNotAlive;
        return self.world.getPtr(entity, T);
    }

    /// Check if an entity has a component of type T
    pub fn hasComponent(self: *Manager, entity: Entity, comptime T: type) error{EntityNotAlive}!bool {
        if (!self.isAlive(entity)) return error.EntityNotAlive;
        return self.world.has(entity, T);
    }

    /// Get all components for an entity as an array of ComponentInstance.
    ///
    /// Caller is responsible for freeing the returned array
    pub fn getAllComponents(self: *Manager, allocator: std.mem.Allocator, entity: Entity) error{ EntityNotAlive, OutOfMemory }![]serialize.ComponentInstance {
        if (!self.isAlive(entity)) return error.EntityNotAlive;
        return self.world.getAllComponents(allocator, entity);
    }

    /// Copy an entity and all of its components from another Manager into this Manager.
    /// Returns the newly created Entity in the destination Manager.
    pub fn copyEntityFrom(self: *Manager, allocator: std.mem.Allocator, src: *Manager, entity: Entity) error{ EntityNotAlive, OutOfMemory }!Entity {
        _ = allocator;
        if (!src.isAlive(entity)) return error.EntityNotAlive;

        const new_entity = try self.allocateEntityId();
        const copied = try src.world.copyEntityTo(entity, &self.world, new_entity);
        if (!copied) return error.EntityNotAlive;
        return new_entity;
    }

    /// Move an entity and all of its components from this Manager into another Manager.
    /// The source entity will be destroyed if the copy succeeds.
    pub fn moveEntityTo(self: *Manager, allocator: std.mem.Allocator, dest: *Manager, entity: Entity) error{ EntityNotAlive, OutOfMemory }!Entity {
        const new_entity = try dest.copyEntityFrom(allocator, self, entity);
        try self.destroy(entity);
        return new_entity;
    }

    fn allocateEntityId(self: *Manager) error{OutOfMemory}!Entity {
        if (self.free_ids.pop()) |id| {
            return Entity{ .id = id, .generation = self.generations.items[id] };
        }

        const id = self.next_entity_id;
        self.next_entity_id += 1;
        try self.generations.append(self.allocator, 0);
        return Entity{ .id = id, .generation = 0 };
    }

    /// Add or update a resource.
    /// Resources must be value types (no pointers allowed).
    ///
    /// *Recommended to use Plain Old Data (POD) types only.*
    ///
    /// Example:
    /// ```zig
    /// const res = manager.addResource(MyResourceType, MyResourceType{ .value = 42 }) catch |err| {
    ///     // Handle error
    ///     return;
    /// };
    /// var guard = res.lockWrite();
    /// defer guard.deinit();
    /// guard.get().field = newValue;
    /// ```
    fn initResourceEntry(self: *Manager, comptime T: type, value: T) error{OutOfMemory}!struct {
        entry: ResourceEntry,
        reference: Ref(T),
    } {
        if (@typeInfo(T) == .pointer) {
            @compileError("resource APIs do not accept pointer types. Use value types only.");
        }

        const type_hash = comptime reflect.typeHash(T);
        const type_size = @sizeOf(T);
        const arc_ptr = try zevy_mem.pointers.ArcRwLock(T).init(self.allocator, value);
        const deinit_fn = struct {
            pub fn deinit(resource_ptr: *anyopaque) void {
                const typed_ptr: Ref(T) = @ptrCast(@alignCast(resource_ptr));
                typed_ptr.deinit();
            }
        }.deinit;
        const write_bytes_fn = struct {
            pub fn write(resource_ptr: *const anyopaque, dest: []u8) void {
                const typed_ptr: Ref(T) = @ptrCast(@alignCast(@constCast(resource_ptr)));
                var guard = typed_ptr.lockRead();
                defer guard.deinit();
                @memcpy(dest, std.mem.asBytes(guard.get()));
            }
        }.write;
        const read_bytes_fn = struct {
            pub fn read(resource_ptr: *anyopaque, src: []const u8) error{InvalidResourceData}!void {
                if (src.len != type_size) return error.InvalidResourceData;

                const typed_ptr: Ref(T) = @ptrCast(@alignCast(resource_ptr));
                var guard = typed_ptr.lockWrite();
                defer guard.deinit();
                @memcpy(std.mem.asBytes(guard.get()), src);
            }
        }.read;

        const manager_ref = arc_ptr.clone();

        try self.resource_codecs.put(type_hash, .{
            .size = type_size,
            .write_bytes_fn = write_bytes_fn,
            .read_bytes_fn = read_bytes_fn,
        });

        return .{
            .entry = .init(
                @ptrCast(@alignCast(manager_ref)),
                type_hash,
                type_size,
                deinit_fn,
            ),
            .reference = arc_ptr,
        };
    }

    pub fn addResource(self: *Manager, comptime T: type, value: T) error{ OutOfMemory, ResourceAlreadyExists }!Ref(T) {
        const type_hash = comptime reflect.typeHash(T);
        var guard = self.resources.lock();
        defer guard.deinit();
        const result = try guard.get().getOrPut(type_hash);
        if (result.found_existing) return error.ResourceAlreadyExists;

        const resource = try self.initResourceEntry(T, value);
        result.value_ptr.* = resource.entry;
        return resource.reference;
    }

    /// Add a resource and immediately release the caller's temporary Ref.
    /// Use this when the caller only needs the Manager-owned resource.
    pub fn addResourceRetained(self: *Manager, comptime T: type, value: T) error{ OutOfMemory, ResourceAlreadyExists }!void {
        const ref = try self.addResource(T, value);
        ref.deinit();
    }

    /// Get a reference-counted handle to a resource of type T, or null if it doesn't exist.
    ///
    /// Example:
    /// ```zig
    /// if (manager.getResource(MyResourceType)) |r| {
    ///     var guard = r.lockRead();
    ///     defer guard.deinit();
    ///     _ = guard.get();
    /// } else {
    ///     // Resource not found
    /// }
    /// Returns a cloned `Ref(T)` handle. Caller must call `.deinit()` when done.
    /// Use `.lockRead()` for shared access or `.lockWrite()` for mutable access.
    pub fn getResource(self: *Manager, comptime T: type) ?Ref(T) {
        const type_hash = reflect.typeHash(T);
        var guard = self.resources.lock();
        defer guard.deinit();
        if (guard.get().get(type_hash)) |entry| {
            const arc_ptr: Ref(T) = @ptrCast(@alignCast(entry.ptr));
            return arc_ptr.clone();
        }

        return null;
    }

    /// Get a mutable pointer to a resource of type T, adding it with default_value if it doesn't exist.
    /// The default_value will be deinitialized if the resource already exists and has a deinit method.
    ///
    /// If no allocator is specified, defaults to the `Manager`'s allocator.
    pub fn getOrAddResource(self: *Manager, comptime T: type, default_value: T, allocator: ?std.mem.Allocator) error{OutOfMemory}!Ref(T) {
        if (self.getResource(T)) |res| {
            if (comptime reflect.hasFuncWithArgs(T, "deinit", &[_]type{std.mem.Allocator})) {
                @constCast(&default_value).deinit(allocator orelse self.allocator);
            } else if (comptime reflect.hasFunc(T, "deinit")) {
                @constCast(&default_value).deinit();
            }
            return res;
        }
        return self.addResource(T, default_value) catch |err| switch (err) {
            error.ResourceAlreadyExists => {
                return self.getResource(T) orelse @panic("You should not reach here.. Take the red pill.");
            },
            else => return error.OutOfMemory,
        };
    }

    /// Check if a resource of type T exists.
    pub fn hasResource(self: *Manager, comptime T: type) bool {
        const type_hash = reflect.typeHash(T);
        var guard = self.resources.lock();
        defer guard.deinit();
        return guard.get().contains(type_hash);
    }

    /// Remove and deallocate a resource.
    /// Only deallocates memory if it was allocated by addResource (allocated field is true).
    pub fn removeResource(self: *Manager, comptime T: type) void {
        const type_hash = reflect.typeHash(T);
        var guard = self.resources.lock();
        const res = guard.get().fetchRemove(type_hash) orelse {
            guard.deinit();
            return;
        };
        @constCast(&res.value).deinit();
        guard.deinit();
    }

    /// List all resource type hashes currently stored in the ECS.
    pub fn listResourceTypeHashes(self: *Manager, allocator: std.mem.Allocator) std.ArrayList(u64) {
        var guard = self.resources.lock();
        var types = std.ArrayList(u64).initCapacity(allocator, guard.get().count()) catch |err| @panic(@errorName(err));
        var it = guard.get().valueIterator();
        while (it.next()) |resource| {
            types.append(allocator, resource.type_hash) catch |err| @panic(@errorName(err));
        }
        guard.deinit();
        return types;
    }

    /// Create a query for iterating over entities with specified components.
    ///
    /// Example:
    /// ```zig
    /// const query = manager.query(struct{pos: Position, vel: Velocity});
    /// // or
    /// const query = manager.query(.{Position, Velocity});
    /// while (query.next()) |q| {
    ///     const pos: *Position = q.pos; // q[0]
    ///     const vel: *Velocity = q.vel; // q[1]
    ///     // Process components
    /// }
    /// ```
    pub fn query(self: *Manager, comptime types: anytype) qry.Query(types) {
        return self.world.query(types);
    }

    /// Create a system from a function and parameter registry.
    /// The system function should match the expected signature for systems.
    ///
    /// Example:
    /// ```zig
    /// fn my_system(manager: *Manager, res: Res(MyResourceType), query: Query(.{Position, Velocity})) void {
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
    /// If the system is already cached, returns the existing handle instead of creating a duplicate.
    pub fn createSystemCached(self: *Manager, comptime system_fn: anytype, comptime ParamRegistry: type) sys.SystemHandle(sys.ToSystemReturnType(system_fn)) {
        const ReturnType = sys.ToSystemReturnType(system_fn);

        // Generate a stable hash from the function type name and parameter registry type
        // Using type names ensures stability across optimization levels
        const FnType = @TypeOf(system_fn);
        const param_registry_name = @typeName(ParamRegistry);
        const fn_hash = reflect.typeHash(FnType);
        const system_hash = reflect.hashWithSeed(param_registry_name, fn_hash);

        // Check if system already exists
        if (self.systems.get(system_hash)) |_| {
            const debug_info = if (is_debug) blk: {
                break :blk sys.SystemDebugInfo{
                    .signature = @typeName(@TypeOf(system_fn)),
                    .params = &[_]sys.ParamDebugInfo{},
                };
            } else {};
            return sys.SystemHandle(ReturnType){ .handle = system_hash, .debug_info = debug_info };
        }

        // Create and cache new system
        const s = self.createSystem(system_fn, ParamRegistry);
        const sys_ptr = self.allocator.create(@TypeOf(s)) catch |err| @panic(@errorName(err));
        sys_ptr.* = s;
        const anyopaque_ptr: *anyopaque = @ptrCast(@alignCast(sys_ptr));
        self.systems.put(system_hash, anyopaque_ptr) catch |err| @panic(@errorName(err));
        const debug_info = if (is_debug) blk: {
            break :blk sys.SystemDebugInfo{
                .signature = @typeName(@TypeOf(system_fn)),
                .params = &[_]sys.ParamDebugInfo{},
            };
        } else {};
        return sys.SystemHandle(ReturnType){ .handle = system_hash, .debug_info = debug_info };
    }

    /// Run a cached system by its SystemHandle.
    pub fn runSystem(self: *Manager, sys_handle: anytype) anyerror!@TypeOf(sys_handle).return_type {
        const ReturnType = @TypeOf(sys_handle).return_type;
        const sys_ptr = self.systems.get(sys_handle.handle) orelse {
            return error.InvalidSystemHandle;
        };
        const s: *sys.System(ReturnType) = @ptrCast(@alignCast(sys_ptr));
        return try s.run(self, s.ctx);
    }

    /// Run a cached system by its untyped handle.
    pub fn runSystemUntyped(self: *Manager, comptime ReturnType: type, sys_handle: sys.UntypedSystemHandle) anyerror!ReturnType {
        const sys_ptr = self.systems.get(sys_handle.handle) orelse return error.InvalidSystemHandle;
        const s: *sys.System(ReturnType) = @ptrCast(@alignCast(sys_ptr));
        return try s.run(self, s.ctx);
    }

    /// Cache an existing system value.
    /// The returned SystemHandle can be used to run the system later.
    /// If the system is already cached (based on its run function address), returns the existing handle.
    pub fn cacheSystem(self: *Manager, system: anytype) blk: {
        const SystemType = @TypeOf(system);
        const type_info = @typeInfo(SystemType);
        if (type_info != .@"struct") {
            @compileError(std.fmt.comptimePrint(
                "cacheSystem expects a System struct, got: {s}",
                .{@typeName(SystemType)},
            ));
        }
        if (!@hasDecl(SystemType, "return_type")) {
            @compileError(std.fmt.comptimePrint(
                "System struct must have a return_type declaration",
                .{},
            ));
        }
        break :blk sys.SystemHandle(SystemType.return_type);
    } {
        const SystemType = @TypeOf(system);
        const ReturnType = SystemType.return_type;

        // Use the stable type-name-based hash embedded at construction time,
        // consistent with createSystemCached.
        const system_hash = system.hash;

        // Check if system already exists
        if (self.systems.get(system_hash)) |_| {
            return sys.SystemHandle(ReturnType){ .handle = system_hash, .debug_info = system.debug_info };
        }

        // Create and cache new system
        const sys_ptr = self.allocator.create(SystemType) catch |err| @panic(@errorName(err));
        sys_ptr.* = system;
        const anyopaque_ptr: *anyopaque = @ptrCast(@alignCast(sys_ptr));
        self.systems.put(system_hash, anyopaque_ptr) catch |err| @panic(@errorName(err));
        return sys.SystemHandle(ReturnType){ .handle = system_hash, .debug_info = system.debug_info };
    }

    pub fn removeSystem(self: *Manager, sys_handle: anytype) void {
        const sys_ptr = self.systems.fetchRemove(sys_handle.handle) orelse return;

        const system: *sys.System(@TypeOf(sys_handle).return_type) = @ptrCast(@alignCast(sys_ptr.value));
        self.allocator.destroy(system);
    }
};

/// Internal helpers used by serialize.zig — not re-exported via root.zig.
pub fn resourceEntryByHash(manager: *Manager, type_hash: u64) ?ResourceEntry {
    var guard = manager.resources.lock();
    defer guard.deinit();
    if (guard.get().get(type_hash)) |entry| {
        return entry;
    }
    return null;
}

pub fn readResourceBytesByHash(manager: *Manager, type_hash: u64, dest: []u8) error{ ResourceNotFound, InvalidResourceData }!void {
    var guard = manager.resources.lock();
    defer guard.deinit();

    const entry = guard.get().getPtr(type_hash) orelse return error.ResourceNotFound;
    const codec = manager.resource_codecs.getPtr(type_hash) orelse return error.ResourceNotFound;
    if (entry.size != codec.size) return error.InvalidResourceData;
    try codec.writeBytes(entry.ptr, dest);
}

pub fn writeResourceBytesByHash(manager: *Manager, type_hash: u64, src: []const u8) error{ ResourceNotFound, InvalidResourceData }!void {
    var guard = manager.resources.lock();
    defer guard.deinit();

    const entry = guard.get().getPtr(type_hash) orelse return error.ResourceNotFound;
    const codec = manager.resource_codecs.getPtr(type_hash) orelse return error.ResourceNotFound;
    if (entry.size != codec.size) return error.InvalidResourceData;
    try codec.readBytes(entry.ptr, src);
}

/// Add a component of type T to the given entity, or an error if entity is dead.
pub fn _addComponent(self: *Manager, entity: Entity, comptime T: type, value: T) error{ EntityNotAlive, OutOfMemory }!void {
    if (!self.isAlive(entity)) return error.EntityNotAlive;
    const tuple = .{value};
    try self.world.add(entity, tuple);

    const type_hash = reflect.typeHash(T);
    try self.component_added.push(.{ .entity = entity, .type_hash = type_hash });
}

pub fn _addComponentBatch(self: *Manager, entities: []const Entity, comptime T: type, values: []const T) error{ EntityNotAlive, OutOfMemory }!void {
    std.debug.assert(entities.len == values.len);
    for (entities) |entity| {
        if (!self.isAlive(entity)) return error.EntityNotAlive;
    }

    try self.world.addSingleComponentBatch(entities, T, values);

    const type_hash = reflect.typeHash(T);
    for (entities) |entity| {
        try self.component_added.push(.{ .entity = entity, .type_hash = type_hash });
    }
}

/// Remove a component of type T from the given entity, or an error if not found or entity is dead.
pub fn _removeComponent(self: *Manager, entity: Entity, comptime T: type) error{ EntityNotAlive, OutOfMemory }!void {
    if (!self.isAlive(entity)) {
        return error.EntityNotAlive;
    }
    const removed = try self.world.removeComponent(entity, T);
    if (removed) {
        const type_hash = comptime reflect.typeHash(T);
        try self.component_removed.push(.{ .entity = entity, .type_hash = type_hash });
    }
}

pub fn _removeComponentBatch(self: *Manager, entities: []const Entity, comptime T: type) error{ EntityNotAlive, OutOfMemory }!void {
    for (entities) |entity| {
        if (!self.isAlive(entity)) return error.EntityNotAlive;
    }

    const removed_mask = try self.allocator.alloc(bool, entities.len);
    defer self.allocator.free(removed_mask);

    try self.world.removeSingleComponentBatch(entities, T, removed_mask);

    const type_hash = reflect.typeHash(T);
    for (entities, 0..) |entity, i| {
        if (removed_mask[i]) {
            try self.component_removed.push(.{ .entity = entity, .type_hash = type_hash });
        }
    }
}

test "Query with just Entity" {
    var ecs_instance = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_instance.deinit();
    const amount = 100;
    for (0..amount) |_| {
        _ = ecs_instance.createEmpty();
    }

    var query = ecs_instance.query(struct { entity: Entity });
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
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

    var query = ecs.query(struct { entity: Entity });
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |q| {
        _ = q.entity;
        count += 1;
    }
    try std.testing.expect(count == amount * 2);
}

// Focused test to exercise migration/remove and check archetype invariants
test "World migration and archetype invariants" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();

    const A = struct { a: u32 };
    const B = struct { b: u64 };
    const C = struct { c: u32 };

    // Create entities with different component sets
    const e1 = ecs.create(.{ A{ .a = 1 }, B{ .b = 2 } });
    const e2 = ecs.create(.{ B{ .b = 3 }, C{ .c = 4 } });

    // Sanity: verify getAllComponents
    const comps1 = try ecs.getAllComponents(std.testing.allocator, e1);
    defer std.testing.allocator.free(comps1);
    try std.testing.expect(comps1.len == 2);

    const comps2 = try ecs.getAllComponents(std.testing.allocator, e2);
    defer std.testing.allocator.free(comps2);
    try std.testing.expect(comps2.len == 2);

    // Remove component A from e1, force migration
    try ecs.removeComponent(e1, A);

    // Now validate archetype invariants: for each archetype, arr_len == entities_count * comp_size
    var storage_guard = ecs.world.archetypes.readGuard();
    defer storage_guard.deinit();
    var it = storage_guard.get().archetypes.valueIterator();
    while (it.next()) |a_ptr| {
        const a = a_ptr.*;
        const ent_count = a.entities.items.len;
        var i: usize = 0;
        while (i < a.component_sizes.len) : (i += 1) {
            const comp_size = a.component_sizes[i];
            const arr_len = a.component_arrays[i].items.len;
            try std.testing.expect(arr_len == ent_count * comp_size);
            // Also ensure comp_size > 0
            try std.testing.expect(comp_size > 0);
        }
        // For each entity in archetype, check that getAllComponents succeeds and matches counts
        var k: usize = 0;
        while (k < ent_count) : (k += 1) {
            const ent = a.entities.items[k];
            const cl = try ecs.getAllComponents(std.testing.allocator, ent);
            defer std.testing.allocator.free(cl);
            try std.testing.expect(cl.len >= 1);
        }
    }
}

test "removeSystem removes cached system" {
    var ecs = try Manager.init(std.testing.allocator);
    defer ecs.deinit();

    // Create a test resource to verify system execution
    const TestCounter = struct { count: u32 };
    try ecs.addResourceRetained(TestCounter, .{ .count = 0 });

    // Define a test system that increments the counter
    const test_system = struct {
        pub fn run(res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    // Cache the system
    const handle = ecs.createSystemCached(test_system, registry.DefaultParamRegistry);

    // Verify the system is cached and runs
    try std.testing.expect(ecs.systems.count() == 1);
    _ = try ecs.runSystem(handle);
    const ctr_ref = ecs.getResource(TestCounter).?;
    defer ctr_ref.deinit();
    var ctr_guard = ctr_ref.lockRead();
    defer ctr_guard.deinit();
    try std.testing.expect(ctr_guard.get().count == 1);

    // Remove the system
    ecs.removeSystem(handle);

    // Verify the system is removed from cache
    try std.testing.expect(ecs.systems.count() == 0);

    // Verify running the removed system returns error
    const result = ecs.runSystem(handle);
    try std.testing.expectError(error.InvalidSystemHandle, result);
}

test "removeSystem with same function cached twice returns same handle" {
    var ecs = try Manager.init(std.testing.allocator);
    defer ecs.deinit();

    const TestCounter = struct { count: u32 };
    try ecs.addResourceRetained(TestCounter, .{ .count = 0 });

    const test_system = struct {
        pub fn run(_: *Manager, res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    // Cache the same system twice - should return the same handle
    const handle1 = ecs.createSystemCached(test_system, registry.DefaultParamRegistry);
    const handle2 = ecs.createSystemCached(test_system, registry.DefaultParamRegistry);

    // Verify they are the same handle
    try std.testing.expect(handle1.handle == handle2.handle);
    // Verify only one system is cached
    try std.testing.expect(ecs.systems.count() == 1);

    // Remove the system once
    ecs.removeSystem(handle1);

    // Verify the system is removed
    try std.testing.expect(ecs.systems.count() == 0);

    // Verify both handles now return error
    try std.testing.expectError(error.InvalidSystemHandle, ecs.runSystem(handle1));
    try std.testing.expectError(error.InvalidSystemHandle, ecs.runSystem(handle2));
}

test "Entity destruction and reuse" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();

    const entity1 = ecs.createEmpty();
    const entity2 = ecs.createEmpty();

    try std.testing.expect(ecs.isAlive(entity1));
    try std.testing.expect(ecs.isAlive(entity2));

    try ecs.destroy(entity1);
    try std.testing.expect(!ecs.isAlive(entity1));
    try std.testing.expect(ecs.isAlive(entity2));

    const entity3 = ecs.createEmpty();
    try std.testing.expect(entity3.id == entity1.id); // ID should be reused
    try std.testing.expect(entity3.generation != entity1.generation); // Generation should be incremented

    try std.testing.expect(ecs.isAlive(entity3));
    try std.testing.expect(ecs.isAlive(entity2));
}

test "copyEntityFrom copies components between managers" {
    var ecs_src = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_src.deinit();

    var ecs_dst = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_dst.deinit();

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { x: f32, y: f32 };

    const e_src = ecs_src.create(.{ Position{ .x = 1, .y = 2 }, Velocity{ .x = 3, .y = 4 } });

    const e_dst = ecs_dst.copyEntityFrom(std.testing.allocator, &ecs_src, e_src) catch unreachable;

    const pos_src = ecs_src.getComponent(e_src, Position) catch unreachable;
    const vel_src = ecs_src.getComponent(e_src, Velocity) catch unreachable;
    const pos_dst = ecs_dst.getComponent(e_dst, Position) catch unreachable;
    const vel_dst = ecs_dst.getComponent(e_dst, Velocity) catch unreachable;

    try std.testing.expect(pos_src != null and vel_src != null);
    try std.testing.expect(pos_dst != null and vel_dst != null);
    try std.testing.expectEqual(pos_src.?.x, pos_dst.?.x);
    try std.testing.expectEqual(pos_src.?.y, pos_dst.?.y);
    try std.testing.expectEqual(vel_src.?.x, vel_dst.?.x);
    try std.testing.expectEqual(vel_src.?.y, vel_dst.?.y);
}

test "moveEntityTo moves components and destroys source" {
    var ecs_src = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_src.deinit();

    var ecs_dst = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs_dst.deinit();

    const Position = struct { x: f32, y: f32 };

    const e_src = ecs_src.create(.{Position{ .x = 10, .y = 20 }});

    const e_dst = ecs_src.moveEntityTo(std.testing.allocator, &ecs_dst, e_src) catch unreachable;

    try std.testing.expect(!ecs_src.isAlive(e_src));
    try std.testing.expect(ecs_dst.isAlive(e_dst));

    const pos_dst = ecs_dst.getComponent(e_dst, Position) catch unreachable;
    try std.testing.expect(pos_dst != null);
    try std.testing.expectEqual(@as(f32, 10), pos_dst.?.x);
    try std.testing.expectEqual(@as(f32, 20), pos_dst.?.y);
}

test "copyEntityFrom same manager duplicates components" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { x: f32, y: f32 };

    const source = ecs.create(.{ Position{ .x = 7, .y = 9 }, Velocity{ .x = 1, .y = 2 } });
    const duplicate = ecs.copyEntityFrom(std.testing.allocator, &ecs, source) catch unreachable;

    try std.testing.expect(ecs.isAlive(source));
    try std.testing.expect(ecs.isAlive(duplicate));
    try std.testing.expect(source.id != duplicate.id);

    const src_pos = ecs.getComponent(source, Position) catch unreachable;
    const dup_pos = ecs.getComponent(duplicate, Position) catch unreachable;
    const src_vel = ecs.getComponent(source, Velocity) catch unreachable;
    const dup_vel = ecs.getComponent(duplicate, Velocity) catch unreachable;

    try std.testing.expect(src_pos != null and dup_pos != null);
    try std.testing.expect(src_vel != null and dup_vel != null);
    try std.testing.expectEqual(src_pos.?.x, dup_pos.?.x);
    try std.testing.expectEqual(src_pos.?.y, dup_pos.?.y);
    try std.testing.expectEqual(src_vel.?.x, dup_vel.?.x);
    try std.testing.expectEqual(src_vel.?.y, dup_vel.?.y);
}

test "getOrAddResource" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();

    const MyResource = struct {
        value: u32,
    };

    const res = ecs.getOrAddResource(MyResource, MyResource{ .value = 32 }, null) catch unreachable;
    res.deinit();

    try std.testing.expect(ecs.hasResource(MyResource));
}

test "addResource keeps manager-owned reference" {
    var ecs = try Manager.init(std.testing.allocator);
    defer ecs.deinit();

    const res = try ecs.addResource(u32, 42);
    try std.testing.expectEqual(@as(usize, 2), res.strongCount());
    res.deinit();

    const again = ecs.getResource(u32) orelse return error.ResourceNotFound;
    defer again.deinit();

    try std.testing.expectEqual(@as(usize, 2), again.strongCount());
    var guard = again.lockRead();
    defer guard.deinit();
    try std.testing.expectEqual(@as(u32, 42), guard.get().*);
}

test "Scheduler resource survives repeated access" {
    var ecs = try Manager.init(std.testing.allocator);
    defer ecs.deinit();

    const TestEvent = struct { value: u32 };
    const Counter = struct { value: u32 };

    const first = try ecs.getOrAddResource(scheduler_mod.Scheduler, try scheduler_mod.Scheduler.init(std.testing.allocator), null);
    {
        var first_guard = first.lockWrite();
        defer first_guard.deinit();
        try first_guard.get().registerEvent(&ecs, TestEvent, registry.DefaultParamRegistry);
    }
    first.deinit();

    try ecs.addResourceRetained(Counter, .{ .value = 0 });

    const second = ecs.getResource(scheduler_mod.Scheduler) orelse return error.ResourceNotFound;
    defer second.deinit();

    const increment = struct {
        fn run(counter: params.ResMut(Counter)) void {
            counter.get().value += 1;
        }
    }.run;

    {
        var second_guard = second.lockWrite();
        defer second_guard.deinit();
        second_guard.get().addSystem(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.Update), increment, registry.DefaultParamRegistry);
        try second_guard.get().runStage(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.Update));
    }

    const counter_ref = ecs.getResource(Counter) orelse return error.ResourceNotFound;
    defer counter_ref.deinit();
    var counter_guard = counter_ref.lockRead();
    defer counter_guard.deinit();
    try std.testing.expectEqual(@as(u32, 1), counter_guard.get().value);
}

// Stress test to try to surface migration/invariant issues
test "World randomized churn stress test" {
    var ecs = Manager.init(std.testing.allocator) catch unreachable;
    defer ecs.deinit();

    const A = struct { a: u32 };
    const B = struct { b: u64 };
    const C = struct { c: u32 };

    var rng = std.Random.DefaultPrng.init(1234);
    var rand = rng.random();
    const N: usize = 200;
    var entities = try std.ArrayList(Entity).initCapacity(std.testing.allocator, N);
    defer entities.deinit(std.testing.allocator);

    // Create initial entities with random component sets
    for (0..N) |_| {
        const v = rand.intRangeAtMost(i32, 0, 4);
        const ent = switch (v) {
            0 => ecs.create(.{A{ .a = 1 }}),
            1 => ecs.create(.{B{ .b = 2 }}),
            2 => ecs.create(.{ A{ .a = 1 }, B{ .b = 2 } }),
            else => ecs.create(.{C{ .c = 3 }}),
        };
        try entities.append(std.testing.allocator, ent);
    }

    const OPS: usize = 2000;
    var i: usize = 0;
    while (i < OPS) : (i += 1) {
        const idx = rand.uintLessThan(usize, entities.items.len);
        const ent = entities.items[idx];
        const op = rand.uintLessThan(usize, 4);
        switch (op) {
            0 => _ = ecs.addComponent(ent, A, A{ .a = 5 }) catch {},
            1 => _ = ecs.addComponent(ent, B, B{ .b = 6 }) catch {},
            2 => _ = ecs.addComponent(ent, C, C{ .c = 7 }) catch {},
            3 => {
                // Randomly remove components
                _ = ecs.removeComponent(ent, A) catch {};
                _ = ecs.removeComponent(ent, B) catch {};
                _ = ecs.removeComponent(ent, C) catch {};
            },
            else => {},
        }

        // Occasionally validate invariants
        if ((i % 50) == 0) {
            var storage_guard = ecs.world.archetypes.readGuard();
            defer storage_guard.deinit();
            var it = storage_guard.get().archetypes.valueIterator();
            while (it.next()) |a_ptr| {
                const a = a_ptr.*;
                const ent_count = a.entities.items.len;
                var j: usize = 0;
                while (j < a.component_sizes.len) : (j += 1) {
                    const comp_size = a.component_sizes[j];
                    const arr_len = a.component_arrays[j].items.len;
                    try std.testing.expect(arr_len == ent_count * comp_size);
                }
            }
        }
    }
}
