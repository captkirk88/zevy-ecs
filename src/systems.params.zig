const std = @import("std");
const ecs = @import("ecs.zig");
const events = @import("events.zig");
const systems = @import("systems.zig");
const state = @import("state.zig");

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
            const stored_event_store = e.addResource(events.EventStore(T), store_ptr) catch |err| @panic(@errorName(err));
            return systems.EventWriter(T){ .event_store = stored_event_store };
        };
        return systems.EventWriter(T){ .event_store = event_store };
    }
};

/// States(StateType) SystemParam analyzer and applier
/// Provides access to state management for checking and transitioning states
/// System parameter handler for State(StateEnum) - checks if a specific state is active
pub const StateSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and
            @hasDecl(T, "StateEnum_") and
            @hasDecl(T, "_is_state_param") and
            @hasField(T, "state_mgr"))
        {
            return T.StateEnum_;
        }
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime StateEnum: type) systems.State(StateEnum) {
        const StateManagerType = state.StateManager(StateEnum);

        // Get or create the StateManager resource for this specific enum type
        if (e.getResource(StateManagerType)) |state_mgr| {
            return systems.State(StateEnum){ .state_mgr = state_mgr };
        }

        std.debug.panic("StateManager({s}) resource not found. Register the state type with scheduler.registerState before using State parameter", .{@typeName(StateEnum)});
    }
};

/// System parameter handler for NextState(StateEnum) - allows immediate state transitions
pub const NextStateSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        // Check for pointer to NextState
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            const child_info = @typeInfo(Child);
            if (child_info == .@"struct" and
                @hasDecl(Child, "StateEnum_") and
                @hasDecl(Child, "_is_next_state_param") and
                @hasField(Child, "state_mgr"))
            {
                return Child.StateEnum_;
            }
        }
        // Also check for non-pointer (though we'll return a pointer)
        if (type_info == .@"struct" and
            @hasDecl(T, "StateEnum_") and
            @hasDecl(T, "_is_next_state_param") and
            @hasField(T, "state_mgr"))
        {
            return T.StateEnum_;
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime StateEnum: type) *systems.NextState(StateEnum) {
        const StateManagerType = state.StateManager(StateEnum);

        // Get or create the StateManager resource for this specific enum type
        const state_mgr = e.getResource(StateManagerType) orelse {
            std.debug.panic("StateManager({s}) resource not found. Register the state type with scheduler and add StateManager to ECS resources before using NextState parameter", .{@typeName(StateEnum)});
        };

        // Get or create NextState instance for this enum type
        const NextStateType = systems.NextState(StateEnum);
        if (e.getResource(NextStateType)) |next_state| {
            return next_state;
        }

        const next_state_value = NextStateType{
            .state_mgr = state_mgr,
        };
        const next_state_ptr = e.addResource(NextStateType, next_state_value) catch |err| {
            std.debug.panic("Failed to create NextState({s}) resource: {}", .{ @typeName(StateEnum), err });
        };

        return next_state_ptr;
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

    pub fn unalloc(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        const res_type = comptime ResourceSystemParam.analyze(T);
        if (res_type == null) {
            std.debug.panic("Cannot unalloc non-resource type '{s}'", .{@typeName(T)});
        }
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
