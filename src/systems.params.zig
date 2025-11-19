const std = @import("std");
const ecs = @import("ecs.zig");
const events = @import("events.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");
const state = @import("state.zig");
const relations = @import("relations.zig");

/// Local: Provides per-system-function persistent storage, accessible only to the declaring system.
/// Value persists across system invocations (lifetime: ECS instance or until explicitly cleared).
pub fn Local(comptime T: type) type {
    return struct {
        _value: T = undefined,
        _set: bool = false,

        /// Set the local value (persists across invocations).
        pub fn set(self: *Self, val: T) void {
            self._value = val;
            self._set = true;
        }

        /// Get the local value.
        pub fn get(self: *Self) T {
            return self._value;
        }

        /// Get the local value, returns null if not set.
        pub fn value(self: *Self) ?T {
            if (self._set) return self._value;
            return null;
        }

        /// Reset the local value (clears persistent state).
        pub fn clear(self: *Self) void {
            self._set = false;
        }

        /// Returns true if the value has been set.
        pub fn isSet(self: *Self) bool {
            return self._set;
        }

        const Self = @This();
    };
}

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

    pub fn apply(_: *ecs.Manager, comptime T: type) *Local(T) {
        // Local params need static storage that persists across system calls
        // Each unique type T gets its own static storage
        const static_storage = struct {
            var local: Local(T) = .{ ._value = undefined, ._set = false };
        };
        return &static_storage.local;
    }
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

/// EventReader provides read-only access to events of type T from the EventStore
pub fn EventReader(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EventType = T;
        pub const is_event_reader = true;
        event_store: *events.EventStore(T),
        iterator: ?events.EventStore(T).Iterator = null,

        /// Read the next event from the store
        pub fn read(self: *const Self) ?*events.EventStore(T).Event {
            var mut_self: *Self = @constCast(self);
            // Initialize iterator if not already done
            if (mut_self.iterator == null) {
                mut_self.iterator = mut_self.event_store.iterator();
            }

            if (mut_self.iterator) |*it| {
                if (it.next()) |event| {
                    if (!event.handled) {
                        return event;
                    } else {
                        // Skip handled events
                        return self.read();
                    }
                }
            }

            return null;
        }

        /// Mark the last read event as handled
        pub fn markHandled(self: *Self) void {
            var mut_self: *Self = @constCast(self);
            if (mut_self.iterator) |*it| {
                it.markHandled();
            }
        }

        /// Reset the read position to the beginning
        pub fn reset(self: *Self) void {
            var mut_self: *Self = @constCast(self);
            mut_self.iterator = mut_self.event_store.iterator();
        }

        /// Create an iterator for reading events (legacy method)
        pub fn iter(self: *Self) events.EventStore(T).Iterator {
            return self.event_store.iterator();
        }

        /// Get the number of events currently in the store
        pub fn len(self: *const Self) usize {
            return self.event_store.count();
        }

        /// Check if the store is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.event_store.isEmpty();
        }

        /// Get all events as a slice (caller must free)
        pub fn getAll(self: *Self, allocator: std.mem.Allocator) ![]events.EventStore(T).Event {
            return self.event_store.getAllEvents(allocator);
        }
    };
}

/// EventReader(T) SystemParam analyzer and applier
pub const EventReaderSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and @hasDecl(T, "EventType") and @hasDecl(T, "is_event_reader")) {
            return T.EventType;
        }
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) EventReader(T) {
        const event_store = e.getResource(events.EventStore(T)) orelse {
            const store_ptr = events.EventStore(T).init(e.allocator, 16);
            const event_store_res = e.addResource(events.EventStore(T), store_ptr) catch |err| @panic(@errorName(err));
            return EventReader(T){ .event_store = event_store_res };
        };
        return EventReader(T){ .event_store = event_store };
    }
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

/// EventWriter provides write access to add events of type T to the EventStore
pub fn EventWriter(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EventType = T;
        pub const is_event_writer = true;
        event_store: *events.EventStore(T),

        /// Add an event to the store
        pub fn write(self: Self, event: T) void {
            self.event_store.push(event);
        }

        /// Get the number of events currently in the store
        pub fn len(self: Self) usize {
            return self.event_store.count();
        }

        /// Check if the store is empty
        /// Returns true if there are no events in the store
        pub fn isEmpty(self: Self) bool {
            return self.event_store.isEmpty();
        }
    };
}

/// EventWriter(T) SystemParam analyzer and applier
pub const EventWriterSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and @hasDecl(T, "EventType") and @hasDecl(T, "is_event_writer")) {
            return T.EventType;
        }
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) EventWriter(T) {
        const event_store = e.getResource(events.EventStore(T)) orelse {
            const store_ptr = events.EventStore(T).init(e.allocator, 16);
            const stored_event_store = e.addResource(events.EventStore(T), store_ptr) catch |err| @panic(@errorName(err));
            return EventWriter(T){ .event_store = stored_event_store };
        };
        return EventWriter(T){ .event_store = event_store };
    }
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

/// State provides a query for checking if a specific state enum value is active
/// Use as a system parameter: state: State(GameState)
/// Where GameState is an enum type
pub fn State(comptime StateEnum: type) type {
    // Verify StateEnum is actually an enum at compile time
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("State requires an enum type, got: " ++ @typeName(StateEnum));
    }

    return struct {
        const Self = @This();
        pub const StateEnum_ = StateEnum;
        pub const _is_state_param = true;

        // Import state module
        const state_mod = @import("state.zig");
        state_mgr: *state_mod.StateManager(StateEnum),

        /// Check if a specific state value is currently active
        pub fn isActive(self: *const Self, state_enum: StateEnum) bool {
            return self.state_mgr.isInState(state_enum);
        }

        /// Get the currently active state value
        pub fn get(self: *const Self) ?StateEnum {
            return self.state_mgr.getActiveState();
        }
    };
}

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

    pub fn apply(e: *ecs.Manager, comptime StateEnum: type) State(StateEnum) {
        const StateManagerType = state.StateManager(StateEnum);

        // Get or create the StateManager resource for this specific enum type
        if (e.getResource(StateManagerType)) |state_mgr| {
            return State(StateEnum){ .state_mgr = state_mgr };
        }

        std.debug.panic("StateManager({s}) resource not found. Register the state type with scheduler.registerState before using State parameter", .{@typeName(StateEnum)});
    }
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime StateEnum: type) void {
        _ = e;
        _ = ptr;
        _ = StateEnum;
    }
};

/// NextState allows immediate state transitions for a specific enum type
pub fn NextState(comptime StateEnum: type) type {
    // Verify StateEnum is actually an enum at compile time
    const type_info = @typeInfo(StateEnum);
    if (type_info != .@"enum") {
        @compileError("NextState requires an enum type, got: " ++ @typeName(StateEnum));
    }

    return struct {
        const Self = @This();
        pub const StateEnum_ = StateEnum;
        pub const _is_next_state_param = true;

        // Import state module
        const state_mod = @import("state.zig");
        state_mgr: *state_mod.StateManager(StateEnum),

        /// Transition to a specific state value immediately
        pub fn set(self: *Self, state_enum: StateEnum) void {
            self.state_mgr.transitionTo(state_enum) catch |err| {
                std.debug.panic("Failed to transition to state: {}", .{err});
            };
        }
    };
}

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

    pub fn apply(e: *ecs.Manager, comptime StateEnum: type) *NextState(StateEnum) {
        const StateManagerType = state.StateManager(StateEnum);

        // Get or create the StateManager resource for this specific enum type
        const state_mgr = e.getResource(StateManagerType) orelse {
            std.debug.panic("StateManager({s}) resource not found. Register the state type with scheduler and add StateManager to ECS resources before using NextState parameter", .{@typeName(StateEnum)});
        };

        // Get or create NextState instance for this enum type
        const NextStateType = NextState(StateEnum);
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
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime StateEnum: type) void {
        _ = e;
        _ = ptr;
        _ = StateEnum;
    }
};

pub fn Res(comptime T: type) type {
    return struct {
        ptr: *T,
    };
}

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

    pub fn apply(e: *ecs.Manager, comptime T: type) Res(T) {
        const resource_ptr = e.getResource(T);
        if (resource_ptr) |res| {
            // Return the wrapper by value - no pointer stability issues!
            return Res(T){ .ptr = @constCast(res) };
        } else {
            std.debug.panic("Resource of type '{s}' not found", .{@typeName(T)});
        }
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ResourceType: type) void {
        // Resource system params do not allocate temporary memory; nothing to free.
        // Keep a no-op deinit so the registry can call it uniformly if present.
        _ = e;
        _ = ptr;
        _ = ResourceType;
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
    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

/// Single(...) returns exactly one matching item from a Query
/// Use as a system parameter like:
/// fn foo(ecs: *Manager, single: Single(struct{pos: Position}, .{})) void { ... }
pub fn Single(comptime IncludeTypes: anytype, comptime ExcludeTypes: anytype) type {
    const Q = @import("query.zig").Query(IncludeTypes, ExcludeTypes);
    return struct {
        pub const IncludeTypesParam = IncludeTypes;
        pub const ExcludeTypesParam = ExcludeTypes;
        pub const Item = Q.IncludeTypesTupleType;

        item: Item,
    };
}

/// Single SystemParam analyzer and applier
pub const SingleSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        if (type_info == .@"struct" and @hasDecl(T, "IncludeTypesParam") and @hasDecl(T, "ExcludeTypesParam") and @hasDecl(T, "item")) {
            return T;
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) T {
        var q = e.query(T.IncludeTypesParam, T.ExcludeTypesParam);
        const first = q.next() orelse std.debug.panic("Single system param expected a single match but none found\n", .{});
        // Ensure there is exactly one match
        if (q.next() != null) std.debug.panic("Single system param expected exactly one match, found multiple\n", .{});
        return T{ .item = first };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

pub const Relations = @import("relations.zig").RelationManager;

/// Relations SystemParam analyzer and applier
/// Provides access to the RelationManager resource
pub const RelationsSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            if (Child == relations.RelationManager) {
                return Child;
            }
            return analyze(Child);
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime _: type) *Relations {
        if (e.hasResource(relations.RelationManager) == false) {
            const rel_mgr = relations.RelationManager.init(e.allocator);
            return e.addResource(relations.RelationManager, rel_mgr) catch |err| {
                std.debug.panic("Failed to create RelationManager resource: {s}", .{@errorName(err)});
            };
        }
        return e.getResource(relations.RelationManager) orelse unreachable;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
    }
};

/// OnAdded(T) system param: read-only view of components of type T
/// that were added since the last system run.
pub fn OnAdded(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_added = true;

        pub const Item = struct { entity: ecs.Entity, comp: ?*T };

        items: []const Item,

        pub fn iter(self: *const Self) []const Item {
            return self.items;
        }
    };
}

/// OnAdded(T) SystemParam analyzer and applier
/// Currently this is a thin wrapper that just provides a normal Query
/// for entities with component T. A higher-level scheduler is expected
/// to constrain which entities are actually considered "added".
pub const OnAddedSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        if (type_info == .@"struct" and @hasDecl(T, "ComponentType") and @hasDecl(T, "is_on_added")) {
            return T.ComponentType;
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime Component: type) OnAdded(Component) {
        const event_type_hash = std.hash.Wyhash.hash(0, @typeName(Component));
        var results = std.ArrayList(OnAdded(Component).Item){};
        defer results.deinit(e.allocator);

        var iter = e.component_added.iterator();
        while (iter.next()) |ev| {
            if (ev.data.type_hash != event_type_hash) continue;
            const comp = e.getComponent(ev.data.entity, Component) catch null;
            if (comp) |comp_ptr| {
                results.append(e.allocator, .{ .entity = ev.data.entity, .comp = comp_ptr }) catch @panic("OutOfMemory");
            } else {
                // Even if the component is no longer present, we still consider it as "added" for this frame.
                // Use a null pointer for the component to indicate it was removed before system execution.
                results.append(e.allocator, .{ .entity = ev.data.entity, .comp = null }) catch @panic("OutOfMemory");
            }
            ev.handled = true;
        }

        const slice = results.toOwnedSlice(e.allocator) catch @panic("OutOfMemory");
        return OnAdded(Component){ .items = slice };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime Component: type) void {
        const p: *OnAdded(Component) = @ptrCast(@alignCast(ptr));
        if (p.items.len != 0) {
            e.allocator.free(p.items);
        }
    }
};

/// OnRemoved(T) system param: exposes entities from which component T
/// was removed since last system run. This is a lightweight wrapper
/// over an event stream produced by the scheduler.
pub fn OnRemoved(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_removed = true;

        removed: []const ecs.Entity,

        pub fn iter(self: *const Self) []const ecs.Entity {
            return self.removed;
        }
    };
}

/// OnRemoved(T) SystemParam analyzer and applier
/// Exposes entities from which T was removed. For now this uses an
/// EventStore of Entity generated elsewhere (e.g. by scheduler).
pub const OnRemovedSystemParam = struct {
    pub fn analyze(comptime T: type) ?type {
        const type_info = @typeInfo(T);
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return analyze(Child);
        }
        if (type_info == .@"struct" and @hasDecl(T, "ComponentType") and @hasDecl(T, "is_on_removed")) {
            return T.ComponentType;
        }
        return null;
    }

    pub fn apply(e: *ecs.Manager, comptime Component: type) OnRemoved(Component) {
        const event_type_hash = std.hash.Wyhash.hash(0, @typeName(Component));
        var results = std.ArrayList(ecs.Entity){};
        defer results.deinit(e.allocator);

        var iter = e.component_removed.iterator();
        while (iter.next()) |ev| {
            if (ev.data.type_hash != event_type_hash) continue;
            results.append(e.allocator, ev.data.entity) catch @panic("OutOfMemory");
            ev.handled = true;
        }

        const slice = results.toOwnedSlice(e.allocator) catch @panic("OutOfMemory");
        return OnRemoved(Component){ .removed = slice };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime Component: type) void {
        const p: *OnRemoved(Component) = @ptrCast(@alignCast(ptr));
        if (p.removed.len != 0) {
            e.allocator.free(p.removed);
        }
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

test "OnAddedSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const Position = struct { x: f32, y: f32 };

    // Create empty entity then add a component to trigger component_added event
    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, Position{ .x = 3.0, .y = 4.0 });

    var on_added = OnAddedSystemParam.apply(&manager, Position);
    try std.testing.expect(on_added.items.len >= 1);
    try std.testing.expect(on_added.items[0].entity.eql(entity));
    try std.testing.expect(on_added.items[0].comp != null);

    // cleanup / free allocated slice
    OnAddedSystemParam.deinit(&manager, @ptrCast(@alignCast(&on_added)), Position);
}

test "OnRemovedSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const Position = struct { x: f32, y: f32 };

    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, Position{ .x = 7.0, .y = 8.0 });
    try manager.removeComponent(entity, Position);

    var on_removed = OnRemovedSystemParam.apply(&manager, Position);
    try std.testing.expect(on_removed.removed.len >= 1);
    try std.testing.expect(on_removed.removed[0].eql(entity));

    OnRemovedSystemParam.deinit(&manager, @ptrCast(@alignCast(&on_removed)), Position);
}

test "RelationsSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const Child = @import("relations.zig").Child;

    const a = manager.create(.{});
    const b = manager.create(.{});

    const rel = RelationsSystemParam.apply(&manager, *relations.RelationManager);

    // Add relation a -> b using Child
    try rel.add(&manager, a, b, Child);

    // Index should be created and queryable
    const children = rel.getChildren(b, Child);
    try std.testing.expect(children.len == 1);
    try std.testing.expect(children[0].eql(a));

    try std.testing.expect(try rel.has(&manager, a, b, Child));

    const parent = try rel.getParent(&manager, a, Child);
    try std.testing.expect(parent.?.eql(b));
}

test "SingleSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    // Create an entity with Position component
    const Position = struct { x: f32, y: f32 };
    _ = manager.create(.{Position{ .x = 1.0, .y = 2.0 }});

    const single = SingleSystemParam.apply(&manager, Single(struct { pos: Position }, .{}));

    try std.testing.expectEqual(single.item.pos.*.x, 1.0);
    try std.testing.expectEqual(single.item.pos.*.y, 2.0);
}
