const std = @import("std");
const ecs = @import("ecs.zig");
const relations_mod = @import("relations.zig");
const reflect = @import("reflect.zig");
const errors = @import("errors.zig");

/// Command represents a deferred operation to be executed later.
const Command = struct {
    execute: *const fn (data: *anyopaque, manager: *ecs.Manager) anyerror!void,
    deinit: *const fn (data: *anyopaque, manager: *ecs.Manager) anyerror!void,
    data: *anyopaque,
};

/// PendingEntity represents an entity that will be created when flush() is called.
/// The actual Entity is populated after creation.
pub const PendingEntity = struct {
    entity: ?ecs.Entity = null,

    /// Get the actual entity. Panics if flush() has not been called yet.
    pub fn get(self: *const PendingEntity) ecs.Entity {
        return self.entity orelse @panic("get() called before flush() - entity has not been created yet");
    }
};

/// Commands provides a way to queue deferred operations on the ECS.
/// Operations are executed when flush() is called, typically after system execution.
pub const Commands = struct {
    /// Same allocator passed into ecs Manager.
    allocator: std.mem.Allocator,
    manager: *ecs.Manager,
    commands: std.ArrayList(Command),

    pub fn init(allocator: std.mem.Allocator, manager: *ecs.Manager) error{OutOfMemory}!Commands {
        return .{
            .allocator = allocator,
            .manager = manager,
            .commands = try std.ArrayList(Command).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Commands) void {
        for (self.commands.items) |cmd| {
            cmd.deinit(cmd.data, self.manager) catch |err| @panic(@errorName(err));
        }
        self.commands.deinit(self.allocator);
    }

    /// Create a deferred entity and return EntityCommands for chaining operations.
    /// The entity is NOT created immediately - call EntityCommands.flush() to create it.
    /// Returns EntityCommands with a PendingEntity that will be populated on flush.
    ///
    /// *DO NOT FORGET TO FLUSH!*
    pub fn create(self: *Commands) !EntityCommands {
        return try EntityCommands.init(self);
    }

    /// Get EntityCommands for an existing entity.
    pub fn entity(self: *Commands, e: ecs.Entity) !EntityCommands {
        return try EntityCommands.initWithEntity(self, e);
    }

    /// Queue adding a component to an existing entity.
    pub fn addComponent(self: *Commands, ent: ecs.Entity, comptime T: type, value: T) error{OutOfMemory}!void {
        const Closure = struct {
            ent: ecs.Entity,
            value: T,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                try manager.addComponent(closure.ent, T, closure.value);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .ent = ent, .value = value };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Get a component from an existing entity.
    ///
    /// **This executes immediately, call `flush()` before calling this.**
    pub fn getComponent(self: *Commands, ent: ecs.Entity, comptime T: type) error{EntityNotAlive}!?*T {
        return self.manager.getComponent(ent, T);
    }

    /// Queue removing a component from an existing entity.
    pub fn removeComponent(self: *Commands, ent: ecs.Entity, comptime T: type) error{OutOfMemory}!void {
        const Closure = struct {
            ent: ecs.Entity,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                try manager.removeComponent(closure.ent, T);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .ent = ent };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Queue destroying an existing entity.
    pub fn destroyEntity(self: *Commands, ent: ecs.Entity) error{OutOfMemory}!void {
        const Closure = struct {
            ent: ecs.Entity,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                try manager.destroy(closure.ent);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .ent = ent };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Queue adding a resource.
    pub fn addResource(self: *Commands, comptime T: type, value: T) error{OutOfMemory}!void {
        const Closure = struct {
            value: T,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                _ = try manager.addResource(T, closure.value);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .value = value };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Queue removing a resource.
    pub fn removeResource(self: *Commands, comptime T: type) error{OutOfMemory}!void {
        const Closure = struct {
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                _ = data;
                manager.removeResource(T);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{};
        try self.commands.append(self.allocator, .{
            .execute = Closure.execute,
            .deinit = Closure.deinit_cmd,
            .data = @ptrCast(@alignCast(closure)),
        });
    }

    /// Queue adding a relation between two entities.
    pub fn addRelation(self: *Commands, entity1: ecs.Entity, entity2: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Closure = struct {
            entity1: ecs.Entity,
            entity2: ecs.Entity,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                const rel_mgr = manager.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                try rel_mgr.add(manager, closure.entity1, closure.entity2, RelationType);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .entity1 = entity1, .entity2 = entity2 };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Queue removing a relation between two entities.
    pub fn removeRelation(self: *Commands, entity1: ecs.Entity, entity2: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Closure = struct {
            entity1: ecs.Entity,
            entity2: ecs.Entity,
            fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                const rel_mgr = manager.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                try rel_mgr.remove(manager, closure.entity1, closure.entity2, RelationType);
            }
            fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                manager.allocator.destroy(closure);
            }
        };
        const closure = try self.allocator.create(Closure);
        closure.* = .{ .entity1 = entity1, .entity2 = entity2 };
        try self.commands.append(self.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
    }

    /// Execute all queued commands on the manager.
    pub fn flush(self: *Commands, manager: *ecs.Manager) anyerror!void {
        for (self.commands.items) |cmd| {
            try cmd.execute(cmd.data, manager);
        }
        // Clear and free data
        for (self.commands.items) |cmd| {
            try cmd.deinit(cmd.data, manager);
        }
        self.commands.clearRetainingCapacity();
    }
};

/// EntityCommands provides entity-specific deferred operations.
/// For pending entities (created via Commands.create()), operations are queued
/// and the entity is created when flush() is called.
/// For existing entities (via Commands.entity()), operations go to the parent Commands queue.
pub const EntityCommands = struct {
    commands: *Commands,
    pending: ?*PendingEntity,
    existing_entity: ?ecs.Entity,
    /// Queue of operations specific to this entity (for pending entities)
    entity_commands: std.ArrayList(Command),

    /// Initialize EntityCommands for a pending (deferred) entity.
    pub fn init(commands: *Commands) error{OutOfMemory}!EntityCommands {
        const pending = try commands.allocator.create(PendingEntity);
        pending.* = .{};
        return .{
            .commands = commands,
            .pending = pending,
            .existing_entity = null,
            .entity_commands = try std.ArrayList(Command).initCapacity(commands.allocator, 0),
        };
    }

    /// Initialize EntityCommands for an existing entity.
    pub fn initWithEntity(commands: *Commands, ent: ecs.Entity) error{OutOfMemory}!EntityCommands {
        return .{
            .commands = commands,
            .pending = null,
            .existing_entity = ent,
            .entity_commands = try std.ArrayList(Command).initCapacity(commands.allocator, 0),
        };
    }

    /// Queue adding a component to this entity. Returns self for chaining.
    pub fn add(self: *EntityCommands, comptime T: type, value: T) error{OutOfMemory}!*EntityCommands {
        if (self.existing_entity) |ent| {
            // For existing entities, delegate to Commands
            try self.commands.addComponent(ent, T, value);
        } else {
            // For pending entities, queue in our local command list
            const pending_ptr = self.pending.?;
            const Closure = struct {
                pending: *PendingEntity,
                value: T,
                fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    const ent = closure.pending.get();
                    try manager.addComponent(ent, T, closure.value);
                }
                fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    manager.allocator.destroy(closure);
                }
            };
            const closure = try self.commands.allocator.create(Closure);
            closure.* = .{ .pending = pending_ptr, .value = value };
            try self.entity_commands.append(self.commands.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
        }
        return self;
    }

    /// Queue removing a component from this entity. Returns self for chaining.
    pub fn remove(self: *EntityCommands, comptime T: type) anyerror!*EntityCommands {
        if (self.existing_entity) |ent| {
            // For existing entities, delegate to Commands
            try self.commands.removeComponent(ent, T);
        } else {
            // For pending entities, queue in our local command list
            const pending_ptr = self.pending.?;
            const Closure = struct {
                pending: *PendingEntity,
                fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    const ent = closure.pending.get();
                    try manager.removeComponent(ent, T);
                }
                fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    manager.allocator.destroy(closure);
                }
            };
            const closure = try self.commands.allocator.create(Closure);
            closure.* = .{ .pending = pending_ptr };
            try self.entity_commands.append(self.commands.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
        }
        return self;
    }

    /// Queue destroying this entity. Returns self for chaining.
    pub fn destroy(self: *EntityCommands) error{OutOfMemory}!*EntityCommands {
        if (self.existing_entity) |ent| {
            // For existing entities, delegate to Commands
            try self.commands.destroyEntity(ent);
        } else {
            // For pending entities, queue in our local command list
            const pending_ptr = self.pending.?;
            const Closure = struct {
                pending: *PendingEntity,
                fn execute(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    const ent = closure.pending.get();
                    try manager.destroy(ent);
                }
                fn deinit_cmd(data: *anyopaque, manager: *ecs.Manager) anyerror!void {
                    const closure = @as(*@This(), @ptrCast(@alignCast(data)));
                    manager.allocator.destroy(closure);
                }
            };
            const closure = try self.commands.allocator.create(Closure);
            closure.* = .{ .pending = pending_ptr };
            try self.entity_commands.append(self.commands.allocator, .{ .execute = Closure.execute, .deinit = Closure.deinit_cmd, .data = closure });
        }
        return self;
    }

    /// Get the entity. For pending entities, panics if flush() has not been called.
    /// For existing entities, returns the entity directly.
    pub fn getEntity(self: *const EntityCommands) ecs.Entity {
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

    /// Flush this EntityCommands: create the entity (if pending) and execute all queued operations.
    /// For pending entities, this creates the entity and populates the PendingEntity.
    /// For existing entities, this flushes the parent Commands queue.
    pub fn flush(self: *EntityCommands) anyerror!void {
        if (self.pending) |pending| {
            // Create the entity now
            pending.entity = self.commands.manager.createEmpty();
            // Execute all queued commands for this entity
            for (self.entity_commands.items) |cmd| {
                try cmd.execute(cmd.data, self.commands.manager);
            }
            // Clean up command closures
            for (self.entity_commands.items) |cmd| {
                try cmd.deinit(cmd.data, self.commands.manager);
            }
            self.entity_commands.clearRetainingCapacity();
        } else {
            // For existing entities, flush the parent Commands
            try self.commands.flush(self.commands.manager);
        }
    }

    pub fn deinit(self: *EntityCommands) void {
        self.flush() catch |err| @panic(@errorName(err));
        for (self.entity_commands.items) |cmd| {
            cmd.deinit(cmd.data, self.commands.manager) catch |err| @panic(@errorName(err));
        }
        self.entity_commands.deinit(self.commands.allocator);
        if (self.pending) |pending| {
            self.commands.allocator.destroy(pending);
        }
    }
};
