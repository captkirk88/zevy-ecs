const std = @import("std");
const ecs = @import("ecs.zig");
const relations_mod = @import("relations.zig");
const reflect = @import("reflect.zig");
const errors = @import("errors.zig");

/// Header written before each command's data in the flat byte buffer.
/// The buffer layout for each entry is:
///   [alignment padding] [CommandHeader] [data alignment padding] [data bytes]
/// All headers are @alignOf(CommandHeader)-aligned; entry_size guarantees
/// the next header starts at an aligned offset.
const CommandHeader = struct {
    execute: *const fn (*anyopaque, *ecs.Manager) anyerror!void,
    batch_execute: ?*const fn ([]const *const anyopaque, *ecs.Manager) anyerror!void,
    /// Bytes from start of this header to start of the command's data.
    data_offset: u32,
    /// Bytes from start of this header to start of the next entry.
    entry_size: u32,
};

/// Append a typed command to `buf` with zero per-command heap allocation.
/// Data is stored inline; the buffer grows amortized like an ArrayList.
fn pushCmdToBuf(
    buf: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    comptime DataType: type,
    data: DataType,
    execute: *const fn (*anyopaque, *ecs.Manager) anyerror!void,
    batch_execute: ?*const fn ([]const *const anyopaque, *ecs.Manager) anyerror!void,
) error{OutOfMemory}!void {
    const header_align = @alignOf(CommandHeader);
    const data_align = @alignOf(DataType);
    // If DataType has higher alignment than the header, start the entry at
    // that alignment so (header_start + data_offset) lands correctly.
    const entry_align = @max(header_align, data_align);

    const header_offset = std.mem.alignForward(usize, buf.items.len, entry_align);
    // For zero-sized types point data at the header itself (always in-bounds).
    const data_offset_rel: usize = if (@sizeOf(DataType) == 0)
        0
    else
        std.mem.alignForward(usize, @sizeOf(CommandHeader), data_align);
    const entry_end = @max(
        header_offset + @sizeOf(CommandHeader), // always need room for the header itself
        header_offset + data_offset_rel + @sizeOf(DataType),
    );
    const next_header = std.mem.alignForward(usize, entry_end, header_align);

    try buf.ensureTotalCapacity(allocator, next_header);
    buf.items.len = next_header;

    const header: *CommandHeader = @ptrCast(@alignCast(buf.items[header_offset..].ptr));
    header.* = .{
        .execute = execute,
        .batch_execute = batch_execute,
        .data_offset = @intCast(data_offset_rel),
        .entry_size = @intCast(next_header - header_offset),
    };

    if (@sizeOf(DataType) > 0) {
        const data_ptr: *DataType = @ptrCast(@alignCast(buf.items[header_offset + data_offset_rel ..].ptr));
        data_ptr.* = data;
    }
}

const BatchGroup = struct {
    batch_execute: *const fn ([]const *const anyopaque, *ecs.Manager) anyerror!void,
    data_ptrs: std.ArrayListUnmanaged(*const anyopaque),
};

/// Execute every command in `buf`, batching component operations between generic barriers,
/// then clear it (retaining capacity).
fn flushBuf(buf: *std.ArrayList(u8), manager: *ecs.Manager) anyerror!void {
    var offset: usize = 0;
    while (offset < buf.items.len) {
        const header: *const CommandHeader = @ptrCast(@alignCast(buf.items[offset..].ptr));
        if (header.batch_execute) |_| {
            var groups = std.ArrayListUnmanaged(BatchGroup).empty;
            defer {
                for (groups.items) |*group| group.data_ptrs.deinit(manager.allocator);
                groups.deinit(manager.allocator);
            }

            while (offset < buf.items.len) {
                const batch_header: *const CommandHeader = @ptrCast(@alignCast(buf.items[offset..].ptr));
                const batch_execute = batch_header.batch_execute orelse break;
                const data_ptr: *const anyopaque = @ptrCast(buf.items[offset + batch_header.data_offset ..].ptr);

                var group_index: ?usize = null;
                for (groups.items, 0..) |group, i| {
                    if (@intFromPtr(group.batch_execute) == @intFromPtr(batch_execute)) {
                        group_index = i;
                        break;
                    }
                }

                if (group_index == null) {
                    try groups.append(manager.allocator, .{
                        .batch_execute = batch_execute,
                        .data_ptrs = .empty,
                    });
                    group_index = groups.items.len - 1;
                }

                try groups.items[group_index.?].data_ptrs.append(manager.allocator, data_ptr);
                offset += batch_header.entry_size;
            }

            for (groups.items) |group| {
                try group.batch_execute(group.data_ptrs.items, manager);
            }
            continue;
        }

        const data_ptr: *anyopaque = @ptrCast(buf.items[offset + header.data_offset ..].ptr);
        try header.execute(data_ptr, manager);
        offset += header.entry_size;
    }
    buf.clearRetainingCapacity();
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

/// Commands provides a way to queue deferred operations on the ECS.
/// All command data is stored inline in a flat byte buffer — zero per-command
/// allocations. The buffer grows amortized (O(log N) backing calls total) and
/// retains its capacity across flush() calls.
pub const Commands = struct {
    allocator: std.mem.Allocator,
    manager: *ecs.Manager,
    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, manager: *ecs.Manager) Commands {
        return .{
            .allocator = allocator,
            .manager = manager,
            .buf = .empty,
        };
    }

    pub fn deinit(self: *Commands) void {
        self.buf.deinit(self.allocator);
    }

    /// Create a deferred entity and return EntityCommands for chaining operations.
    /// The entity is NOT created immediately — call EntityCommands.flush() to create it.
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
        const Data = struct { ent: ecs.Entity, value: T };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .ent = ent, .value = value }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                try mgr.addComponent(d.ent, T, d.value);
            }
            fn batchExecute(data_ptrs: []const *const anyopaque, mgr: *ecs.Manager) anyerror!void {
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
        }.execute, null);
    }

    /// Get a component from an existing entity.
    ///
    /// **This executes immediately; call `flush()` before calling this.**
    pub fn getComponent(self: *Commands, ent: ecs.Entity, comptime T: type) error{EntityNotAlive}!?*T {
        return self.manager.getComponent(ent, T);
    }

    /// Queue removing a component from an existing entity.
    pub fn removeComponent(self: *Commands, ent: ecs.Entity, comptime T: type) error{OutOfMemory}!void {
        const Data = struct { ent: ecs.Entity };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .ent = ent }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                try mgr.removeComponent(d.ent, T);
            }
        }.execute, null);
    }

    /// Queue destroying an existing entity.
    pub fn destroyEntity(self: *Commands, ent: ecs.Entity) error{OutOfMemory}!void {
        const Data = struct { ent: ecs.Entity };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .ent = ent }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                try mgr.destroy(d.ent);
            }
        }.execute, null);
    }

    /// Queue adding a resource.
    pub fn addResource(self: *Commands, comptime T: type, value: T) error{OutOfMemory}!void {
        const Data = struct { value: T };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .value = value }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                _ = try mgr.addResource(T, d.value);
            }
        }.execute, null);
    }

    /// Queue removing a resource.
    pub fn removeResource(self: *Commands, comptime T: type) error{OutOfMemory}!void {
        const Data = struct {};
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{}, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                _ = ptr;
                mgr.removeResource(T);
            }
        }.execute, null);
    }

    /// Queue adding a relation between two entities.
    pub fn addRelation(self: *Commands, child: ecs.Entity, parent: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Data = struct { child: ecs.Entity, parent: ecs.Entity };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .child = child, .parent = parent }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const ref = mgr.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                defer ref.deinit();
                var rel_guard = ref.lock();
                defer rel_guard.deinit();
                try rel_guard.get().add(mgr, d.child, d.parent, RelationType);
            }
        }.execute, null);
    }

    /// Queue removing a relation between two entities.
    pub fn removeRelation(self: *Commands, entity1: ecs.Entity, entity2: ecs.Entity, comptime RelationType: type) error{OutOfMemory}!void {
        const Data = struct { entity1: ecs.Entity, entity2: ecs.Entity };
        try pushCmdToBuf(&self.buf, self.allocator, Data, .{ .entity1 = entity1, .entity2 = entity2 }, &struct {
            fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                const d: *Data = @ptrCast(@alignCast(ptr));
                const ref = mgr.getResource(relations_mod.RelationManager) orelse return error.RelationResourceNotFound;
                defer ref.deinit();
                var rel_guard = ref.lock();
                defer rel_guard.deinit();
                try rel_guard.get().remove(mgr, d.entity1, d.entity2, RelationType);
            }
        }.execute, null);
    }

    /// Execute all queued commands and clear the buffer (retaining capacity for reuse).
    pub fn flush(self: *Commands, manager: *ecs.Manager) anyerror!void {
        try flushBuf(&self.buf, manager);
    }
};

/// EntityCommands provides entity-specific deferred operations.
/// For pending entities (created via Commands.create()), a PendingEntity is
/// heap-allocated (one allocation per entity, not per component) and all
/// component commands are stored inline in a local byte buffer.
/// For existing entities (via Commands.entity()), operations go to the parent Commands queue.
pub const EntityCommands = struct {
    commands: *Commands,
    pending: ?*PendingEntity,
    existing_entity: ?ecs.Entity,
    /// Byte buffer for pending-entity component commands (flushed when entity is created).
    /// Unused and zero-size for existing entities.
    ebuf: std.ArrayListUnmanaged(u8),

    /// Initialize EntityCommands for a pending (deferred) entity.
    pub fn init(cmds: *Commands) error{OutOfMemory}!EntityCommands {
        const pending = try cmds.allocator.create(PendingEntity);
        pending.* = .{};
        return .{
            .commands = cmds,
            .pending = pending,
            .existing_entity = null,
            .ebuf = .empty,
        };
    }

    /// Initialize EntityCommands for an existing entity.
    pub fn initWithEntity(cmds: *Commands, ent: ecs.Entity) error{OutOfMemory}!EntityCommands {
        return .{
            .commands = cmds,
            .pending = null,
            .existing_entity = ent,
            .ebuf = .empty,
        };
    }

    /// Queue adding a component to this entity. Returns self for chaining.
    pub fn add(self: *EntityCommands, comptime T: type, value: T) error{OutOfMemory}!*EntityCommands {
        if (self.existing_entity) |ent| {
            try self.commands.addComponent(ent, T, value);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity, value: T };
            try pushCmdToBuf(&self.ebuf, self.commands.allocator, Data, .{ .pending = pending_ptr, .value = value }, &struct {
                fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    try mgr.addComponent(d.pending.entity.?, T, d.value);
                }
            }.execute, null);
        }
        return self;
    }

    /// Queue removing a component from this entity. Returns self for chaining.
    pub fn remove(self: *EntityCommands, comptime T: type) anyerror!*EntityCommands {
        if (self.existing_entity) |ent| {
            try self.commands.removeComponent(ent, T);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity };
            try pushCmdToBuf(&self.ebuf, self.commands.allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    try mgr.removeComponent(d.pending.entity.?, T);
                }
            }.execute, null);
        }
        return self;
    }

    /// Queue destroying this entity. Returns self for chaining.
    pub fn destroy(self: *EntityCommands) error{OutOfMemory}!*EntityCommands {
        if (self.existing_entity) |ent| {
            try self.commands.destroyEntity(ent);
        } else {
            const pending_ptr = self.pending.?;
            const Data = struct { pending: *PendingEntity };
            try pushCmdToBuf(&self.ebuf, self.commands.allocator, Data, .{ .pending = pending_ptr }, &struct {
                fn execute(ptr: *anyopaque, mgr: *ecs.Manager) anyerror!void {
                    const d: *Data = @ptrCast(@alignCast(ptr));
                    try mgr.destroy(d.pending.entity.?);
                }
            }.execute, null);
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

    /// Flush this EntityCommands: create the entity (if pending and not yet created)
    /// and execute all queued component operations.
    pub fn flush(self: *EntityCommands) anyerror!void {
        if (self.pending) |pending| {
            // Guard against double-flush: only create the entity once.
            if (pending.entity == null) {
                pending.entity = self.commands.manager.createEmpty();
            }
            try flushBuf(&self.ebuf, self.commands.manager);
        } else {
            try self.commands.flush(self.commands.manager);
        }
    }

    pub fn deinit(self: *EntityCommands) void {
        self.flush() catch |err| @panic(@errorName(err));
        if (self.pending) |p| self.commands.allocator.destroy(p);
        self.ebuf.deinit(self.commands.allocator);
    }
};
