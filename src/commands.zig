const std = @import("std");
const ecs = @import("ecs.zig");
const relations_mod = @import("relations.zig");
const reflect = @import("reflect.zig");
const errors = @import("errors.zig");
const command_buffer = @import("command_buffer.zig");

const CommandBuffer = command_buffer.CommandBuffer;

inline fn commandsInner(commands: Commands) *CommandsInner._Inner {
    return @ptrCast(@alignCast(commands));
}

/// PendingEntity represents an entity that will be created when flush() is called.
/// The actual Entity is populated after creation.
pub const PendingEntity = struct {
    entity: ?ecs.Entity = null,

    /// Get the actual entity. Panics if flush() has not been called yet.
    pub fn get(self: *const PendingEntity) ecs.Entity {
        return self.entity orelse @panic("get() called before flush() - entity has not been created yet");
    }
};

pub const CommandsInner = opaque {
    const Self = @This();

    pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
        pub fn get() []const u8 {
            return "Commands";
        }
    }.get else void;

    pub const _Inner = struct {
        _allocator: std.mem.Allocator,
        _manager: *ecs.Manager,
        buffer: CommandBuffer,
    };

    pub fn init(base_allocator: std.mem.Allocator, ecsManager: *ecs.Manager) error{OutOfMemory}!Commands {
        const inner = try base_allocator.create(_Inner);
        inner.* = .{
            ._allocator = base_allocator,
            ._manager = ecsManager,
            .buffer = .init(),
        };
        return @ptrCast(inner);
    }

    pub fn deinit(self: Commands) void {
        commandsInner(self).buffer.deinit(commandsInner(self)._allocator);
    }

    pub fn destroy(self: Commands) void {
        const inner = commandsInner(self);
        const _allocator = inner._allocator;
        inner.buffer.deinit(_allocator);
        _allocator.destroy(inner);
    }

    pub fn manager(self: Commands) *ecs.Manager {
        return commandsInner(self)._manager;
    }

    pub fn allocator(self: Commands) std.mem.Allocator {
        return commandsInner(self)._allocator;
    }

    /// Create a deferred entity and return EntityCommands for chaining operations.
    /// The entity is NOT created immediately — call EntityCommands.flush() to create it.
    ///
    /// *Note*: The returned EntityCommands must have flush() called to actually create the entity, unless, you only intend to queue operations that do not require the entity to exist yet (e.g., adding components to an entity that will be created later).
    pub fn create(self: Commands) !EntityCommands {
        return try EntityCommands.init(self);
    }

    /// Get EntityCommands for an existing entity.
    pub fn entity(self: Commands, e: ecs.Entity) !EntityCommands {
        return try EntityCommands.initWithEntity(self, e);
    }

    /// Queue adding a component to an existing entity.
    pub fn addComponent(self: Commands, ent: ecs.Entity, comptime T: type, value: T) error{OutOfMemory}!void {
        const Data = struct { ent: ecs.Entity, value: T };
        const CommandFns = struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                try mgr.addComponent(d.ent, T, d.value);
            }
            fn batchExecute(data_ptrs: []const *const anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                var ents = try mgr.allocator.alloc(ecs.Entity, data_ptrs.len);
                defer mgr.allocator.free(ents);
                var values = try mgr.allocator.alloc(T, data_ptrs.len);
                defer mgr.allocator.free(values);

                for (data_ptrs, 0..) |data_ptr, i| {
                    const d: *const Data = @ptrCast(@alignCast(data_ptr));
                    ents[i] = d.ent;
                    values[i] = d.value;
                }

                try mgr.addComponentBatch(ents, T, values);
            }
        };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .ent = ent, .value = value }, &CommandFns.execute, &CommandFns.batchExecute);
    }

    /// Queue removing a component from an existing entity.
    pub fn removeComponent(self: Commands, ent: ecs.Entity, comptime T: type) error{OutOfMemory}!void {
        const Data = struct { ent: ecs.Entity };
        const CommandFns = struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                try mgr.removeComponent(d.ent, T);
            }
            fn batchExecute(data_ptrs: []const *const anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                var ents = try mgr.allocator.alloc(ecs.Entity, data_ptrs.len);
                defer mgr.allocator.free(ents);

                for (data_ptrs, 0..) |data_ptr, i| {
                    const d: *const Data = @ptrCast(@alignCast(data_ptr));
                    ents[i] = d.ent;
                }

                try mgr.removeComponentBatch(ents, T);
            }
        };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .ent = ent }, &CommandFns.execute, &CommandFns.batchExecute);
    }

    /// Queue destroying an existing entity.
    pub fn destroyEntity(self: Commands, ent: ecs.Entity) error{OutOfMemory}!void {
        const Data = struct { ent: ecs.Entity };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .ent = ent }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                try mgr.destroy(d.ent);
            }
        }.execute, null);
    }

    /// Queue adding a resource.
    pub fn addResource(self: Commands, comptime T: type, value: T) error{OutOfMemory}!void {
        const Data = struct { value: T };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .value = value }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                _ = try mgr.addResource(T, d.value);
            }
        }.execute, null);
    }

    /// Queue removing a resource.
    pub fn removeResource(self: Commands, comptime T: type) error{OutOfMemory}!void {
        const Data = struct {};
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{}, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                _ = ptr;
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                mgr.removeResource(T);
            }
        }.execute, null);
    }

    /// Queue adding a relation between two entities.
    pub fn addRelation(self: Commands, child: ecs.Entity, parent: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Data = struct { child: ecs.Entity, parent: ecs.Entity };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .child = child, .parent = parent }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                const ref = mgr.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                defer ref.deinit();
                var rel_guard = ref.lockWrite();
                defer rel_guard.deinit();
                try rel_guard.get().add(mgr, d.child, d.parent, RelationType);
            }
        }.execute, null);
    }

    /// Queue removing a relation between two entities.
    pub fn removeRelation(self: Commands, entity1: ecs.Entity, entity2: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Data = struct { entity1: ecs.Entity, entity2: ecs.Entity };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .entity1 = entity1, .entity2 = entity2 }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                const ref = mgr.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                defer ref.deinit();
                var rel_guard = ref.lockWrite();
                defer rel_guard.deinit();
                try rel_guard.get().remove(mgr, d.entity1, d.entity2, RelationType);
            }
        }.execute, null);
    }

    /// Enqueue all queued commands onto the manager's deferred command queue.
    pub fn queue(self: Commands) error{OutOfMemory}!void {
        try commandsInner(self)._manager.enqueueCommandBuffer(commandsInner(self).buffer.moveTo());
    }

    /// Execute all queued commands and clear the buffer (retaining capacity for reuse).
    pub fn flush(self: Commands, ecsManager: *ecs.Manager) anyerror!void {
        try commandsInner(self).buffer.flush(ecsManager.allocator, ecsManager);
    }
};

/// Commands provides a way to queue deferred operations on the ECS.
/// All command data is stored inline in a flat byte buffer — zero per-command
/// allocations. The buffer grows amortized (O(log N) backing calls total) and
/// retains its capacity across flush() calls.
pub const Commands = *CommandsInner;

/// EntityCommands provides entity-specific deferred operations.
/// For pending entities (created via Commands.create()), a PendingEntity is
/// heap-allocated (one allocation per entity, not per component) and all
/// component commands are stored inline in a local byte buffer.
/// For existing entities (via Commands.entity()), operations go to the parent Commands queue.
pub const EntityCommands = struct {
    commands: Commands,
    pending: ?*PendingEntity,
    existing_entity: ?ecs.Entity,
    /// Byte buffer for pending-entity component commands (flushed when entity is created).
    /// Unused and zero-size for existing entities.
    ebuf: CommandBuffer,

    /// Initialize EntityCommands for a pending (deferred) entity.
    pub fn init(cmds: Commands) error{OutOfMemory}!EntityCommands {
        const pending = try commandsInner(cmds)._allocator.create(PendingEntity);
        pending.* = .{};
        return .{
            .commands = cmds,
            .pending = pending,
            .existing_entity = null,
            .ebuf = .init(),
        };
    }

    /// Initialize EntityCommands for an existing entity.
    pub fn initWithEntity(cmds: Commands, ent: ecs.Entity) error{OutOfMemory}!EntityCommands {
        return .{
            .commands = cmds,
            .pending = null,
            .existing_entity = ent,
            .ebuf = .init(),
        };
    }

    /// Queue adding a component to this entity. Returns self for chaining.
    pub fn add(self: *EntityCommands, comptime T: type, value: T) error{OutOfMemory}!void {
        if (self.existing_entity) |ent| {
            try self.commands.addComponent(ent, T, value);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity, value: T };
            try self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr, .value = value }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.addComponent(d.pending.entity.?, T, d.value);
                }
            }.execute, null);
        }
    }

    /// Queue removing a component from this entity. Returns self for chaining.
    pub fn remove(self: *EntityCommands, comptime T: type) anyerror!void {
        if (self.existing_entity) |ent| {
            try self.commands.removeComponent(ent, T);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity };
            try self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.removeComponent(d.pending.entity.?, T);
                }
            }.execute, null);
        }
    }

    /// Queue destroying this entity. Returns self for chaining.
    pub fn destroy(self: *EntityCommands) error{OutOfMemory}!void {
        if (self.existing_entity) |ent| {
            try self.commands.destroyEntity(ent);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity };
            try self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.destroy(d.pending.entity.?);
                }
            }.execute, null);
        }
    }

    /// Get the entity. For pending entities, panics if flush() has not been called.
    /// For existing entities, returns the entity directly.
    pub fn entity(self: *const EntityCommands) ecs.Entity {
        if (self.existing_entity) |ent| {
            return ent;
        }
        return self.pending.?.get();
    }

    /// Get the PendingEntity reference (only valid for pending entities).
    /// Returns null for existing entities.
    pub fn getPending(self: *const EntityCommands) ?*PendingEntity {
        return self.pending;
    }

    pub fn hasPending(self: *const EntityCommands) bool {
        return self.pending != null;
    }

    pub fn hasExisting(self: *const EntityCommands) bool {
        return self.existing_entity != null;
    }

    /// Get a component from this entity.
    ///
    /// For pending entities, this requires the entity to have been flushed first.
    pub fn get(self: *const EntityCommands, comptime T: type) error{EntityNotAlive}!?*T {
        return self.commands.manager().getComponent(self.entity(), T);
    }

    /// Flush this EntityCommands: create the entity (if pending and not yet created)
    /// and execute all queued component operations.
    pub fn flush(self: *EntityCommands) anyerror!void {
        if (self.pending) |pending| {
            // Guard against double-flush: only create the entity once.
            if (pending.entity == null) {
                pending.entity = commandsInner(self.commands)._manager.createEmpty();
            }
            try self.ebuf.flush(commandsInner(self.commands)._allocator, commandsInner(self.commands)._manager);
        } else {
            try self.commands.flush(commandsInner(self.commands)._manager);
        }
    }

    pub fn deinit(self: *EntityCommands) void {
        self.flush() catch |err| @panic(@errorName(err));
        if (self.pending) |p| commandsInner(self.commands)._allocator.destroy(p);
        self.ebuf.deinit(commandsInner(self.commands)._allocator);
    }
};
