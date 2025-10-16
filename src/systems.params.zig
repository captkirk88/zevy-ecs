const std = @import("std");
const ecs = @import("ecs.zig");
const events = @import("events.zig");
const systems = @import("systems.zig");

pub const LocalSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and
            @hasField(T, "_value") and
            @hasField(T, "_set") and
            type_info.@"struct".fields.len == 2)
        {
            return type_info.@"struct".fields[0].type;
        } else if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(_: *ecs.Manager, comptime T: type) *systems.Local(T) {
        // Local params need static storage that persists across system calls
        // Each unique type T gets its own static storage
        const static_storage = struct {
            var local: systems.Local(T) = .{ ._value = undefined, ._set = false };
        };
        return &static_storage.local;
    }
};

/// EventReader(T) SystemParam analyzer and applier
pub const EventReaderSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and @hasDecl(T, "EventType") and @hasField(T, "event_store") and @hasField(T, "iterator")) {
            return T.EventType;
        }
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) systems.EventReader(T) {
        const event_store = e.getResource(events.EventStore(T)) orelse {
            const store_ptr = events.EventStore(T).init(e.allocator, 16);
            const event_store_res = e.addResource(events.EventStore(T), store_ptr) catch |err| @panic(@errorName(err));
            return systems.EventReader(T){ .event_store = event_store_res };
        };
        return systems.EventReader(T){ .event_store = event_store };
    }
};

/// EventWriter(T) SystemParam analyzer and applier
pub const EventWriterSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and @hasDecl(T, "EventType") and @hasField(T, "event_store") and !@hasField(T, "iterator")) {
            return T.EventType;
        }
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) systems.EventWriter(T) {
        const event_store = e.getResource(events.EventStore(T)) orelse {
            const store_ptr = events.EventStore(T).init(e.allocator, 16);
            _ = e.addResource(events.EventStore(T), store_ptr) catch |err| @panic(@errorName(err));
            // Get the resource again after adding it
            const stored_event_store = e.getResource(events.EventStore(T)) orelse @panic("Failed to get event store after adding");
            return systems.EventWriter(T){ .event_store = stored_event_store };
        };
        return systems.EventWriter(T){ .event_store = event_store };
    }
};

/// Res(T) SystemParam analyzer and applier
pub const ResourceSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and
            type_info.@"struct".fields.len == 1 and
            type_info.@"struct".fields[0].name.len == 3 and
            std.mem.eql(u8, type_info.@"struct".fields[0].name[0..3], "ptr"))
        {
            // For Res(T), the field is ptr: *T, so we want to return T, not *T
            const ptr_type_info = @typeInfo(type_info.@"struct".fields[0].type);
            if (ptr_type_info == .pointer) {
                return ptr_type_info.pointer.child;
            }
        } else if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) systems.Res(T) {
        const resource_ptr = e.getResource(T);
        if (resource_ptr) |res| {
            // Return the wrapper by value - no pointer stability issues!
            return systems.Res(T){ .ptr = @constCast(res) };
        } else {
            std.debug.panic("Resource of type '{s}' not found", .{@typeName(T)});
        }
    }

    pub fn unalloc(e: *ecs.ECS, ptr: *anyopaque, comptime T: type) void {
        const res_type = ResourceSystemParam.analyze(T);
        if (res_type == null) @compileError("Cannot unalloc non-resource type");
        e.allocator.destroy(@as(*systems.Res(res_type.?), ptr));
    }
};

/// Query(...) SystemParam analyzer and applier
pub const QuerySystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        } else if (type_info == .@"struct" and @hasDecl(T, "IncludeTypesParam") and @hasDecl(T, "ExcludeTypesParam")) {
            return T;
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) T {
        return e.query(T.IncludeTypesParam, T.ExcludeTypesParam);
    }
};

test "ResourceSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const value: i32 = 42;
    _ = try ecs_instance.addResource(i32, value);
    const res = ResourceSystemParam.apply(&ecs_instance, i32);
    try std.testing.expect(res.ptr.* == 42);
}

test "LocalSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const local_ptr = LocalSystemParam.apply(&ecs_instance, i32);
    local_ptr._value = 99;
    try std.testing.expect(local_ptr._value == 99);
}

test "EventReaderSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const reader = EventReaderSystemParam.apply(&ecs_instance, u32);
    try std.testing.expect(@intFromPtr(reader.event_store) != 0);
}

test "EventWriterSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const writer = EventWriterSystemParam.apply(&ecs_instance, u32);
    try std.testing.expect(@intFromPtr(writer.event_store) != 0);
}
