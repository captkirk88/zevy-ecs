const std = @import("std");
const ecs = @import("ecs.zig");
const relations_mod = @import("relations.zig");
const scheduler = @import("scheduler.zig");
const systems = @import("systems.zig");
const reflect = @import("reflect.zig");
const registry = @import("systems.registry.zig");
const errors = @import("errors.zig");
const command_buffer = @import("command_buffer.zig");

const CommandBuffer = command_buffer.CommandBuffer;

inline fn commandsInner(commands: Commands) *CommandsInner._Inner {
    return @ptrCast(@alignCast(commands));
}

pub const QueuedCommand = struct {
    buffer: command_buffer.CommandBuffer,
    manager_ptr: *anyopaque,
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

    pub fn io(self: Commands) std.Io {
        return commandsInner(self)._manager.io();
    }

    /// Create a deferred entity and return EntityCommands for chaining operations.
    /// The entity is NOT created immediately — call EntityCommands.flush() to create it.
    pub fn create(self: Commands) EntityCommands {
        return EntityCommands.init(self);
    }

    /// Get EntityCommands for an existing entity.
    pub fn entity(self: Commands, e: ecs.Entity) EntityCommands {
        return EntityCommands.initWithEntity(self, e);
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
                var ents = try mgr.allocator().alloc(ecs.Entity, data_ptrs.len);
                defer mgr.allocator().free(ents);
                var values = try mgr.allocator().alloc(T, data_ptrs.len);
                defer mgr.allocator().free(values);

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
                var ents = try mgr.allocator().alloc(ecs.Entity, data_ptrs.len);
                defer mgr.allocator().free(ents);

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
                try mgr.addResourceRetained(T, d.value);
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

    fn resolveSystemHandle(comptime SystemType: type, system_fn: anytype, mgr: *ecs.Manager) systems.UntypedSystemHandle {
        const system_type = comptime systems.getSystemTypeFromType(SystemType);
        if (comptime system_type == .func) {
            return mgr.cacheSystem(mgr.createSystemFromType(SystemType, system_fn)).eraseType();
        } else if (comptime system_type == .handle) {
            return system_fn.eraseType();
        } else if (comptime system_type == .untyped) {
            return system_fn;
        } else if (comptime system_type == .system) {
            return mgr.cacheSystem(system_fn).eraseType();
        } else {
            return std.debug.panic("Invalid system type: {s}", .{@typeName(SystemType)});
        }
    }

    pub fn addSystem(self: Commands, stage: scheduler.StageId, system_fn: anytype) error{OutOfMemory}!void {
        const SystemType = @TypeOf(system_fn);
        // Resolve to an UntypedSystemHandle at enqueue time so the queued data
        // is runtime-representable and does not require storing comptime-only
        // function values inside the command buffer.
        const mgr = commandsInner(self)._manager;
        const untyped_handle = resolveSystemHandle(SystemType, system_fn, mgr);

        const Data = struct { stage: scheduler.StageId, handle: systems.UntypedSystemHandle };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .stage = stage, .handle = untyped_handle }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr_exec: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                const sched = mgr_exec.scheduler();
                sched.addSystem(mgr_exec, d.stage, d.handle);
            }
        }.execute, null);
    }

    pub fn removeSystem(self: Commands, stage: scheduler.StageId, system_fn: anytype) error{OutOfMemory}!void {
        const SystemType = @TypeOf(system_fn);
        const mgr = commandsInner(self)._manager;
        const untyped_handle = resolveSystemHandle(SystemType, system_fn, mgr);

        const Data = struct { stage: scheduler.StageId, handle: systems.UntypedSystemHandle };
        try commandsInner(self).buffer.appendCommand(commandsInner(self)._allocator, Data, .{ .stage = stage, .handle = untyped_handle }, &struct {
            fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const mgr_exec: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                mgr_exec.scheduler().removeSystem(mgr_exec, d.stage, d.handle);
            }
        }.execute, null);
    }

    /// Enqueue the local command buffer onto the manager's deferred queue.
    ///
    /// This moves ownership of the `Commands`' internal `CommandBuffer` into the
    /// `Manager`'s deferred queue (`ManagerImpl.queued_commands`) under a mutex.
    /// The scheduler (or explicit calls to `Manager.flushQueuedCommands`) will
    /// later flush queued buffers on the manager's context. Use `queue` when
    /// called from systems that must defer mutations until after all stage work
    /// completes (the Scheduler toggles `defer_command_flush` around stage runs).
    ///
    /// Characteristics:
    /// - Thread-safe: appends under the manager's command-queue mutex.
    /// - Deferred: does not execute commands immediately.
    /// - Preserves ordering and the originating `Manager` context for flush time.
    pub fn queue(self: Commands) error{OutOfMemory}!void {
        const mgr_wrapper = commandsInner(self)._manager;
        const impl = mgr_wrapper.inner();
        try impl.enqueueCommandBuffer(@ptrCast(@alignCast(mgr_wrapper)), commandsInner(self).buffer.take());
    }

    /// Execute all queued commands in this `Commands` buffer immediately.
    ///
    /// This applies operations synchronously to the supplied `*ecs.Manager` and
    /// does not interact with the manager's deferred queue. Use `flush` when
    /// immediate effects are required (for example, `EntityCommands.flush`),
    /// and use `queue` when mutations must be deferred until after concurrent
    /// stage work completes.
    pub fn flush(self: Commands, ecsManager: *ecs.Manager) anyerror!void {
        try commandsInner(self).buffer.flush(ecsManager.allocator(), ecsManager);
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
    pub fn init(cmds: Commands) EntityCommands {
        const pending = commandsInner(cmds)._allocator.create(PendingEntity) catch |err| @panic(@errorName(err));
        pending.* = .{};
        return .{
            .commands = cmds,
            .pending = pending,
            .existing_entity = null,
            .ebuf = .init(),
        };
    }

    /// Initialize EntityCommands for an existing entity.
    pub fn initWithEntity(cmds: Commands, ent: ecs.Entity) EntityCommands {
        return .{
            .commands = cmds,
            .pending = null,
            .existing_entity = ent,
            .ebuf = .init(),
        };
    }

    /// Queue adding a component to this entity. Returns self for chaining.
    pub fn add(self: *EntityCommands, comptime T: type, value: T) *EntityCommands {
        if (self.existing_entity) |ent| {
            self.commands.addComponent(ent, T, value) catch |err| @panic(@errorName(err));
        } else if (self.pending) |pending_ptr| {
            const Data = struct { pending: *PendingEntity, value: T };
            self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr, .value = value }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.addComponent(d.pending.entity.?, T, d.value);
                }
            }.execute, null) catch |err| @panic(@errorName(err));
        }
        return self;
    }

    /// Queue removing a component from this entity.
    pub fn remove(self: *EntityCommands, comptime T: type) void {
        if (self.existing_entity) |ent| {
            self.commands.removeComponent(ent, T) catch |err| @panic(@errorName(err));
        } else if (self.pending) |pending_ptr| {
            const Data = struct { pending: *PendingEntity };
            self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.removeComponent(d.pending.entity.?, T);
                }
            }.execute, null) catch |err| @panic(@errorName(err));
        }
    }

    /// Queue destroying this entity. For pending entities, this simply drops the pending entity without creating it. For existing entities, this queues a destroy command on the parent Commands.
    pub fn destroy(self: *EntityCommands) void {
        if (self.existing_entity) |ent| {
            self.commands.destroyEntity(ent) catch |err| @panic(@errorName(err));
        } else if (self.pending) |pending_ptr| {
            const Data = struct { pending: *PendingEntity };
            self.ebuf.appendCommand(commandsInner(self.commands)._allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr_ptr: *anyopaque) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    const mgr: *ecs.Manager = @ptrCast(@alignCast(mgr_ptr));
                    try mgr.destroy(d.pending.entity.?);
                }
            }.execute, null) catch |err| @panic(@errorName(err));
        }
    }

    /// Get the entity. For pending entities, panics if flush() has not been called.
    /// For existing entities, returns the entity directly.
    pub fn entity(self: *const EntityCommands) ecs.Entity {
        if (self.existing_entity) |ent| {
            return ent;
        } else if (self.pending) |pending_ptr| {
            return pending_ptr.get();
        } else {
            @panic("EntityCommands must have either pending (commands.create()) or existing entity");
        }
    }

    /// Get the PendingEntity reference (only valid for pending entities).
    /// Returns null for existing entities.
    pub fn getPending(self: *const EntityCommands) ?*PendingEntity {
        return self.pending;
    }

    pub fn getExisting(self: *const EntityCommands) ?ecs.Entity {
        return self.existing_entity;
    }

    /// Get a component from this entity.
    ///
    /// For pending entities, this requires the entity to have been flushed first.
    pub fn get(self: *const EntityCommands, comptime T: type) error{EntityNotAlive}!?*T {
        if (self.existing_entity) |ent| {
            return self.commands.manager().getComponent(ent, T);
        } else if (self.pending) |pending_ptr| {
            const ent = pending_ptr.get();
            return self.commands.manager().getComponent(ent, T);
        } else {
            @panic("EntityCommands must have either pending (commands.create()) or existing entity");
        }
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
        const inner = commandsInner(self.commands);
        if (self.pending) |p| inner._allocator.destroy(p);
        self.ebuf.deinit(inner._allocator);
    }
};

test "Commands.addSystem queues and executes scheduler systems" {
    const params = @import("systems.params.zig");
    var manager = try ecs.Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    var commands = try CommandsInner.init(std.testing.allocator, &manager);
    defer commands.deinit();

    const TestCounter = struct { count: u32 };
    try manager.addResourceRetained(TestCounter, .{ .count = 0 });

    const test_system = struct {
        pub fn run(res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    const handle = manager.cacheSystem(manager.createSystem(test_system));
    const update_stage = scheduler.Stage(scheduler.Stages.Update);
    try commands.addSystem(update_stage, handle);
    try commands.flush(&manager);

    var stage_info = manager.scheduler().getStageInfo(std.testing.allocator);
    defer stage_info.deinit(std.testing.allocator);
    var found_update = false;
    for (stage_info.items) |info| {
        if (info.stage.value == update_stage.value) {
            found_update = true;
            try std.testing.expect(info.system_count == 1);
            break;
        }
    }
    try std.testing.expect(found_update);
    try std.testing.expect(manager.systems().count() == 1);
}

test "Commands.removeSystem removes scheduler stage entry and cached system" {
    const params = @import("systems.params.zig");
    var manager = try ecs.Manager.init(std.testing.allocator, std.testing.io);
    defer manager.deinit();

    const commands = try CommandsInner.init(std.testing.allocator, &manager);
    defer commands.deinit();

    const TestCounter = struct { count: u32 };
    try manager.addResourceRetained(TestCounter, .{ .count = 0 });

    const test_system = struct {
        pub fn run(res: params.ResMut(TestCounter)) void {
            res.get().count += 1;
        }
    }.run;

    const handle = manager.cacheSystem(manager.createSystem(test_system));
    const update_stage = scheduler.Stage(scheduler.Stages.Update);
    try commands.addSystem(update_stage, handle);
    try commands.flush(&manager);

    try commands.removeSystem(update_stage, handle.eraseType());
    try commands.flush(&manager);

    var stage_info = manager.scheduler().getStageInfo(std.testing.allocator);
    defer stage_info.deinit(std.testing.allocator);
    for (stage_info.items) |info| {
        if (info.stage.value == update_stage.value) {
            try std.testing.expect(info.system_count == 0);
        }
    }
    try std.testing.expect(manager.systems().count() == 0);
}

test "Commands.queue enqueues buffer" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator, std.testing.io);
    defer manager.deinit();

    var commands = try CommandsInner.init(allocator, &manager);
    defer commands.deinit();

    // Append a simple command and enqueue it; the manager should own the buffer afterwards.
    try commands.addResource(i32, 42);
    try commands.queue();

    const impl = manager.inner();
    try std.testing.expectEqual(@as(usize, 1), impl.queued_commands.items.len);
    const queued = &impl.queued_commands.items[0];
    try std.testing.expect(!queued.buffer.isEmpty());

    // Cleanup will deinit the queued buffer via manager.deinit().
}

test "Commands.flush vs queue (immediate vs deferred)" {
    const allocator = std.testing.allocator;

    // Immediate flush: commands.flush applies effects right away.
    var m1 = try ecs.Manager.init(allocator, std.testing.io);
    defer m1.deinit();

    var c1 = try CommandsInner.init(allocator, &m1);
    defer c1.deinit();

    try c1.addResource(i32, 7);
    try c1.flush(&m1);

    const r1 = m1.getResource(i32).?;
    defer r1.deinit();
    var gr1 = r1.lockRead();
    defer gr1.deinit();
    try std.testing.expectEqual(@as(i32, 7), gr1.get().*);

    // Deferred queue: commands.queue moves buffer to manager.queued_commands
    // and effects are not visible until the manager flushes queued commands.
    var m2 = try ecs.Manager.init(allocator, std.testing.io);
    defer m2.deinit();

    var c2 = try CommandsInner.init(allocator, &m2);
    defer c2.deinit();

    try c2.addResource(i32, 9);
    try c2.queue();

    // Not applied yet
    try std.testing.expect(m2.getResource(i32) == null);

    // Now flush queued buffers on the manager (sequential path)
    try m2.inner().flushQueuedCommands(null);

    const r2 = m2.getResource(i32).?;
    defer r2.deinit();
    var gr2 = r2.lockRead();
    defer gr2.deinit();
    try std.testing.expectEqual(@as(i32, 9), gr2.get().*);
}
