const std = @import("std");
const ecs = @import("ecs.zig");

pub const CommandHeader = struct {
    execute: *const fn (*anyopaque, *anyopaque) anyerror!void,
    batch_execute: ?*const fn ([]const *const anyopaque, *anyopaque) anyerror!void,
    data_offset: u32,
    entry_size: u32,
};

const BatchGroup = struct {
    batch_execute: *const fn ([]const *const anyopaque, *anyopaque) anyerror!void,
    data_ptrs: std.ArrayList(*const anyopaque),
};

pub const CommandBuffer = struct {
    bytes: std.ArrayList(u8),

    pub fn init() CommandBuffer {
        return .{ .bytes = .empty };
    }

    pub fn deinit(self: *CommandBuffer, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
    }

    pub fn isEmpty(self: *const CommandBuffer) bool {
        return self.bytes.items.len == 0;
    }

    pub fn clearRetainingCapacity(self: *CommandBuffer) void {
        self.bytes.clearRetainingCapacity();
    }

    pub fn moveTo(self: *CommandBuffer) CommandBuffer {
        const moved = self.*;
        self.* = .init();
        return moved;
    }

    pub fn appendCommand(
        self: *CommandBuffer,
        allocator: std.mem.Allocator,
        comptime DataType: type,
        data: DataType,
        execute: *const fn (*anyopaque, *anyopaque) anyerror!void,
        batch_execute: ?*const fn ([]const *const anyopaque, *anyopaque) anyerror!void,
    ) error{OutOfMemory}!void {
        const header_align = @alignOf(CommandHeader);
        const data_align = @alignOf(DataType);
        const entry_align = @max(header_align, data_align);

        const header_offset = std.mem.alignForward(usize, self.bytes.items.len, entry_align);
        const data_offset_rel: usize = if (@sizeOf(DataType) == 0)
            0
        else
            std.mem.alignForward(usize, @sizeOf(CommandHeader), data_align);
        const entry_end = @max(
            header_offset + @sizeOf(CommandHeader),
            header_offset + data_offset_rel + @sizeOf(DataType),
        );
        const next_header = std.mem.alignForward(usize, entry_end, header_align);

        const old_len = self.bytes.items.len;
        try self.bytes.resize(allocator, next_header);
        @memset(self.bytes.items[old_len..next_header], 0);

        const header: *CommandHeader = @ptrCast(@alignCast(self.bytes.items[header_offset..].ptr));
        header.* = .{
            .execute = execute,
            .batch_execute = batch_execute,
            .data_offset = @intCast(data_offset_rel),
            .entry_size = @intCast(next_header - header_offset),
        };

        if (@sizeOf(DataType) > 0) {
            const data_ptr: *DataType = @ptrCast(@alignCast(self.bytes.items[header_offset + data_offset_rel ..].ptr));
            data_ptr.* = data;
        }
    }

    pub fn flush(self: *CommandBuffer, allocator: std.mem.Allocator, manager: *ecs.Manager) anyerror!void {
        var offset: usize = 0;
        while (offset < self.bytes.items.len) {
            const header: *const CommandHeader = @ptrCast(@alignCast(self.bytes.items[offset..].ptr));
            if (header.batch_execute) |_| {
                var groups = std.ArrayList(BatchGroup).empty;
                defer {
                    for (groups.items) |*group| group.data_ptrs.deinit(allocator);
                    groups.deinit(allocator);
                }

                while (offset < self.bytes.items.len) {
                    const batch_header: *const CommandHeader = @ptrCast(@alignCast(self.bytes.items[offset..].ptr));
                    const batch_execute = batch_header.batch_execute orelse break;
                    const data_ptr: *const anyopaque = @ptrCast(self.bytes.items[offset + batch_header.data_offset ..].ptr);

                    var group_index: ?usize = null;
                    for (groups.items, 0..) |group, i| {
                        if (@intFromPtr(group.batch_execute) == @intFromPtr(batch_execute)) {
                            group_index = i;
                            break;
                        }
                    }

                    if (group_index == null) {
                        try groups.append(allocator, .{
                            .batch_execute = batch_execute,
                            .data_ptrs = .empty,
                        });
                        group_index = groups.items.len - 1;
                    }

                    try groups.items[group_index.?].data_ptrs.append(allocator, data_ptr);
                    offset += batch_header.entry_size;
                }

                for (groups.items) |group| {
                    try group.batch_execute(group.data_ptrs.items, @ptrCast(manager));
                }
                continue;
            }

            const data_ptr: *anyopaque = @ptrCast(self.bytes.items[offset + header.data_offset ..].ptr);
            try header.execute(data_ptr, manager);
            offset += header.entry_size;
        }
        self.clearRetainingCapacity();
    }
};
