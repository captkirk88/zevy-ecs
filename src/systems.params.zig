const std = @import("std");
const ecs = @import("ecs.zig");
const zevy_mem = @import("zevy_mem");

const events = @import("events.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");
const state = @import("state.zig");
const relations_mod = @import("relations.zig");
const errors = @import("errors.zig");
const serialize = @import("serialize.zig");
const reflect = @import("reflect.zig");
const zevy_reflect = @import("zevy_reflect");
const commands_mod = @import("commands.zig");
const Commands = commands_mod.Commands;
const CommandsInner = commands_mod.CommandsInner;
const EntityCommands = commands_mod.EntityCommands;

fn BaseType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |pointer_info| BaseType(pointer_info.child),
        else => T,
    };
}

fn typeHasDecls(comptime T: type, comptime decl_names: []const []const u8) bool {
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => {},
        else => return false,
    }
    inline for (decl_names) |decl_name| {
        if (!@hasDecl(T, decl_name)) return false;
    }
    return true;
}

fn typeHasFields(comptime T: type, comptime field_names: []const []const u8) bool {
    inline for (field_names) |field_name| {
        if (!zevy_reflect.hasField(T, field_name)) return false;
    }
    return true;
}

fn SystemParam(comptime Matcher: type, comptime Impl: type) type {
    return struct {
        pub fn matches(comptime ParamType: type) bool {
            return Matcher.matches(ParamType, BaseType(ParamType));
        }

        pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
            return try Impl.apply(e, ParamType);
        }

        pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
            Impl.deinit(e, ptr, ParamType);
        }
    };
}

fn DeclMatcher(comptime require_pointer: bool, comptime decl_names: []const []const u8) type {
    return struct {
        pub fn matches(comptime ParamType: type, comptime Base: type) bool {
            return (@typeInfo(ParamType) == .pointer) == require_pointer and typeHasDecls(Base, decl_names);
        }
    };
}

fn DeclAndFieldMatcher(
    comptime require_pointer: bool,
    comptime decl_names: []const []const u8,
    comptime field_names: []const []const u8,
) type {
    return struct {
        pub fn matches(comptime ParamType: type, comptime Base: type) bool {
            return (@typeInfo(ParamType) == .pointer) == require_pointer and typeHasDecls(Base, decl_names) and typeHasFields(Base, field_names);
        }
    };
}

fn ExactBaseMatcher(comptime require_pointer: bool, comptime ExpectedBase: type) type {
    return struct {
        pub fn matches(comptime ParamType: type, comptime Base: type) bool {
            return (@typeInfo(ParamType) == .pointer) == require_pointer and Base == ExpectedBase;
        }
    };
}

/// Local: Provides per-system-function persistent storage, accessible only to the declaring system.
/// Value persists across system invocations (lifetime: ECS instance or until explicitly cleared).
pub fn Local(comptime T: type) type {
    return struct {
        _value: T = undefined,
        _set: bool = false,

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "Local(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

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

const LocalSystemParamMatcher = struct {
    pub fn matches(comptime ParamType: type, comptime Base: type) bool {
        const type_info = @typeInfo(Base);
        return @typeInfo(ParamType) == .pointer and
            type_info == .@"struct" and
            typeHasFields(Base, &.{ "_value", "_set" }) and
            type_info.@"struct".fields.len == 2;
    }
};

const LocalSystemParamImpl = struct {
    pub fn apply(_: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const LocalType = BaseType(ParamType);
        const ValueType = @typeInfo(LocalType).@"struct".fields[0].type;
        const static_storage = struct {
            var local: Local(ValueType) = .{ ._value = undefined, ._set = false };
        };
        return &static_storage.local;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = e;
        _ = ptr;
        _ = ParamType;
    }
};

pub const LocalSystemParam = SystemParam(LocalSystemParamMatcher, LocalSystemParamImpl);

/// EventReader provides read-only access to events of type T from the EventStore
pub fn EventReader(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EventType = T;
        pub const is_event_reader = true;
        _ref: ecs.Ref(events.EventStore(T)),
        _guard: zevy_mem.lock.RwLock(events.EventStore(T)).WriteGuard,
        event_store: *events.EventStore(T),
        iterator: ?events.EventStore(T).Iterator = null,

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "EventReader(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

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

        /// Reset the read position to the beginning.
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

/// EventReader(T) SystemParam matcher and applier
const EventReaderSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const EventType = BaseType(ParamType).EventType;
        var ref = e.getResource(events.EventStore(EventType)) orelse blk: {
            const store = try events.EventStore(EventType).init(e.allocator, 16);
            _ = try e.addResource(events.EventStore(EventType), store);
            break :blk e.getResource(events.EventStore(EventType)) orelse return error.ResourceNotFound;
        };
        const guard = ref.lockWrite();
        return ParamType{ ._ref = ref, ._guard = guard, .event_store = guard.get() };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = e;
        const reader: *ParamType = @ptrCast(@alignCast(ptr));
        reader._guard.deinit();
        reader._ref.deinit();
    }
};

pub const EventReaderSystemParam = SystemParam(DeclMatcher(false, &.{ "EventType", "is_event_reader" }), EventReaderSystemParamImpl);

/// EventWriter provides write access to add events of type T to the EventStore
pub fn EventWriter(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EventType = T;
        pub const is_event_writer = true;
        _ref: ecs.Ref(events.EventStore(T)),
        _guard: zevy_mem.lock.RwLock(events.EventStore(T)).WriteGuard,
        event_store: *events.EventStore(T),

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "EventWriter(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

        /// Add an event to the store
        pub fn write(self: Self, event: T) void {
            self.event_store.push(event) catch |err| @panic(@errorName(err));
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

/// EventWriter(T) SystemParam matcher and applier
const EventWriterSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const EventType = BaseType(ParamType).EventType;
        var ref = e.getResource(events.EventStore(EventType)) orelse blk: {
            const store = try events.EventStore(EventType).init(e.allocator, 16);
            _ = try e.addResource(events.EventStore(EventType), store);
            break :blk e.getResource(events.EventStore(EventType)) orelse return error.ResourceNotFound;
        };
        const guard = ref.lockWrite();
        return ParamType{ ._ref = ref, ._guard = guard, .event_store = guard.get() };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = e;
        const writer: *ParamType = @ptrCast(@alignCast(ptr));
        writer._guard.deinit();
        writer._ref.deinit();
    }
};

pub const EventWriterSystemParam = SystemParam(DeclMatcher(false, &.{ "EventType", "is_event_writer" }), EventWriterSystemParamImpl);

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

        state_mgr: state.StateManager(StateEnum),

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

/// States(StateType) SystemParam matcher and applier
/// Provides access to state management for checking and transitioning states
/// System parameter handler for State(StateEnum) - checks if a specific state is active
const StateSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const StateEnum = BaseType(ParamType).StateEnum_;
        const StateManagerType = state.StateManager(StateEnum);

        // Get or create the StateManager resource for this specific enum type
        if (e.getResource(StateManagerType)) |ref| {
            defer ref.deinit();
            var guard = ref.lockRead();
            defer guard.deinit();
            const state_mgr = guard.get().*;
            return ParamType{ .state_mgr = state_mgr };
        }

        return error.StateManagerNotFound;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = e;
        _ = ptr;
        _ = ParamType;
    }
};

pub const StateSystemParam = SystemParam(DeclAndFieldMatcher(false, &.{ "StateEnum_", "_is_state_param" }, &.{"state_mgr"}), StateSystemParamImpl);

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

        state_mgr: state.StateManager(StateEnum),

        /// Transition to a specific state value immediately
        pub fn set(self: *Self, state_enum: StateEnum) error{StateNotRegistered}!void {
            return try self.state_mgr.transitionTo(state_enum);
        }
    };
}

/// System parameter handler for NextState(StateEnum) - allows immediate state transitions
const NextStateSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const StateEnum = BaseType(ParamType).StateEnum_;
        const StateManagerType = state.StateManager(StateEnum);
        const ref = e.getResource(StateManagerType) orelse return error.StateManagerNotFound;
        defer ref.deinit();
        var guard = ref.lockRead();
        const state_mgr = guard.get().*;
        guard.deinit();
        const next_state_ptr = try e.allocator.create(BaseType(ParamType));
        next_state_ptr.* = BaseType(ParamType){ .state_mgr = state_mgr };
        return next_state_ptr;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const next_state: ParamType = @ptrCast(@alignCast(ptr));
        e.allocator.destroy(next_state);
    }
};

pub const NextStateSystemParam = SystemParam(DeclAndFieldMatcher(true, &.{ "StateEnum_", "_is_next_state_param" }, &.{"state_mgr"}), NextStateSystemParamImpl);

pub fn ResInner(comptime T: type) type {
    return opaque {
        const Self = @This();

        /// Marker for resource system param matching.
        pub const is_res = true;
        /// The wrapped value type
        pub const ResType = T;

        pub const _Inner = struct {
            ref: ecs.Ref(T),
            guard: zevy_mem.lock.RwLock(T).ReadGuard,
        };

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "Res(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

        /// Get a const pointer to the resource value.
        /// Valid only while this `Res` is alive (i.e. within the system function).
        pub fn get(self: *const Self) *const T {
            const inner: *const _Inner = @ptrCast(@alignCast(self));
            return inner.guard.get();
        }
    };
}

/// Pointer-backed system parameter providing shared read access to a resource of type T.
/// Use `res.get()` to obtain a const pointer to the value.
/// The read lock is held for the entire duration of the system invocation and released automatically.
pub fn Res(comptime T: type) type {
    return *ResInner(T);
}

pub fn ResMutInner(comptime T: type) type {
    return opaque {
        const Self = @This();

        pub const is_res_mut = true;
        pub const ResMutType = T;

        pub const _Inner = struct {
            ref: ecs.Ref(T),
            guard: zevy_mem.lock.RwLock(T).WriteGuard,
        };

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "ResMut(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

        pub fn get(self: *Self) *T {
            const inner: *_Inner = @ptrCast(@alignCast(self));
            return inner.guard.get();
        }
    };
}

/// Pointer-backed system parameter providing exclusive write access to a resource of type T.
/// Use `res.get()` to obtain a mutable pointer to the value.
/// The write lock is held for the entire duration of the system invocation and released automatically.
pub fn ResMut(comptime T: type) type {
    return *ResMutInner(T);
}

/// Res(T) SystemParam matcher and applier
const ResourceSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const ResourceType = BaseType(ParamType).ResType;
        const ref = e.getResource(ResourceType) orelse return error.ResourceNotFound;
        const inner = try e.allocator.create(BaseType(ParamType)._Inner);
        inner.* = .{ .ref = ref, .guard = ref.lockRead() };
        return @ptrCast(inner);
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const inner: *BaseType(ParamType)._Inner = @ptrCast(@alignCast(ptr));
        inner.guard.deinit();
        inner.ref.deinit();
        e.allocator.destroy(inner);
    }
};

pub const ResourceSystemParam = SystemParam(DeclMatcher(true, &.{ "is_res", "ResType" }), ResourceSystemParamImpl);

/// ResMut(T) SystemParam matcher and applier
const ResourceMutSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const ResourceType = BaseType(ParamType).ResMutType;
        const ref = e.getResource(ResourceType) orelse return error.ResourceNotFound;
        const inner = try e.allocator.create(BaseType(ParamType)._Inner);
        inner.* = .{ .ref = ref, .guard = ref.lockWrite() };
        return @ptrCast(inner);
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const inner: *BaseType(ParamType)._Inner = @ptrCast(@alignCast(ptr));
        inner.guard.deinit();
        inner.ref.deinit();
        e.allocator.destroy(inner);
    }
};

pub const ResourceMutSystemParam = SystemParam(DeclMatcher(true, &.{ "is_res_mut", "ResMutType" }), ResourceMutSystemParamImpl);

/// Query(...) SystemParam matcher and applier
const QuerySystemParamMatcher = struct {
    pub fn matches(comptime ParamType: type, comptime Base: type) bool {
        const type_info = @typeInfo(Base);
        return @typeInfo(ParamType) != .pointer and type_info == .@"struct" and @hasDecl(Base, "IncludeTypesParam") and !@hasField(Base, "item");
    }
};

const QuerySystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        var query = e.query(ParamType.IncludeTypesParam);
        const released = try e.allocator.create(bool);
        query.shareDeinitState(released);
        return query;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const query_ptr: *ParamType = @ptrCast(@alignCast(ptr));
        query_ptr.deinit();
        if (query_ptr.shared_guard_released) |shared_state| {
            query_ptr.shared_guard_released = null;
            e.allocator.destroy(shared_state);
        }
    }
};

pub const QuerySystemParam = SystemParam(QuerySystemParamMatcher, QuerySystemParamImpl);

/// Single(...) returns exactly one matching item from a Query
/// Use as a system parameter like:
/// fn foo(ecs: *Manager, single: Single(struct{pos: Position})) void { ... }
pub fn Single(comptime IncludeTypes: anytype) type {
    const Q = @import("query.zig").Query(IncludeTypes);
    return struct {
        pub const IncludeTypesParam = IncludeTypes;
        pub const Item = Q.IncludeTypesTupleType;

        item: Item,

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                // Reuse Query's debugInfo logic
                const query_str = Q.debugInfo();
                // Replace "Query" with "Single"
                return "Single" ++ query_str[5..];
            }
        }.get else void;
    };
}

/// Single SystemParam matcher and applier
const SingleSystemParamMatcher = struct {
    pub fn matches(comptime ParamType: type, comptime Base: type) bool {
        const type_info = @typeInfo(Base);
        return @typeInfo(ParamType) != .pointer and type_info == .@"struct" and @hasDecl(Base, "IncludeTypesParam") and @hasField(Base, "item");
    }
};

const SingleSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        var q = e.query(ParamType.IncludeTypesParam);
        defer q.deinit();
        const first = q.next() orelse return error.SingleFoundNoMatches;
        // Ensure there is exactly one match
        if (q.next() != null) {
            return error.SingleFoundMultipleMatches;
        }
        return ParamType{ .item = first };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = e;
        _ = ptr;
        _ = ParamType;
    }
};

pub const SingleSystemParam = SystemParam(SingleSystemParamMatcher, SingleSystemParamImpl);

/// Write-guarded handle to the RelationManager resource.
/// Use `rel.get()` to access the `RelationManager`.
/// Released automatically by the system runner.
pub const RelationsInner = opaque {
    const Self = @This();

    pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
        pub fn get() []const u8 {
            return "Relations";
        }
    }.get else void;

    pub const _Inner = struct {
        ref: ecs.Ref(relations_mod.RelationManager),
        guard: zevy_mem.lock.RwLock(relations_mod.RelationManager).WriteGuard,
    };

    fn inner(self: *Self) *_Inner {
        const impl: *_Inner = @ptrCast(@alignCast(self));
        return impl;
    }

    pub fn hasIndex(self: *Self, comptime Kind: type) bool {
        return self.inner().guard.get().hasIndex(Kind);
    }

    pub fn add(self: *Self, manager: *ecs.Manager, child: ecs.Entity, parent: ecs.Entity, comptime Kind: type) error{ ParentMismatch, EntityNotAlive, OutOfMemory }!void {
        return try self.inner().guard.get().add(manager, child, parent, Kind);
    }

    pub fn addWithData(self: *Self, manager: *ecs.Manager, child: ecs.Entity, parent: ecs.Entity, comptime Kind: type, data: Kind) error{ ParentMismatch, EntityNotAlive, OutOfMemory }!void {
        return try self.inner().guard.get().addWithData(manager, child, parent, Kind, data);
    }

    pub fn remove(self: *Self, manager: *ecs.Manager, child: ecs.Entity, parent: ecs.Entity, comptime Kind: type) error{ ParentMismatch, EntityNotAlive, OutOfMemory }!void {
        return try self.inner().guard.get().remove(manager, child, parent, Kind);
    }

    pub fn getChildren(self: *Self, parent: ecs.Entity, comptime Kind: type) []const ecs.Entity {
        return self.inner().guard.get().getChildren(parent, Kind);
    }

    pub fn getParents(self: *Self, child: ecs.Entity, comptime Kind: type) []const ecs.Entity {
        return self.inner().guard.get().getParents(child, Kind);
    }

    pub fn getParent(self: *Self, manager: *ecs.Manager, child: ecs.Entity, comptime Kind: type) error{EntityNotAlive}!?ecs.Entity {
        return try self.inner().guard.get().getParent(manager, child, Kind);
    }

    pub fn getChild(self: *Self, manager: *ecs.Manager, parent: ecs.Entity, comptime Kind: type) ?ecs.Entity {
        return self.inner().guard.get().getChild(manager, parent, Kind);
    }

    pub fn has(self: *Self, manager: *ecs.Manager, child: ecs.Entity, parent: ecs.Entity, comptime Kind: type) !bool {
        return try self.inner().guard.get().has(manager, child, parent, Kind);
    }

    pub fn removeEntity(self: *Self, entity: ecs.Entity) void {
        self.inner().guard.get().removeEntity(entity);
    }

    pub fn indexCount(self: *Self) usize {
        return self.inner().guard.get().indexCount();
    }
};

pub const Relations = *RelationsInner;

/// Relations SystemParam matcher and applier
/// Provides access to the RelationManager resource
/// Use as `rel: params.Relations` in system functions.
const RelationsSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        if (e.hasResource(relations_mod.RelationManager) == false) {
            const rel_mgr = relations_mod.RelationManager.init(e.allocator);
            _ = try e.addResource(relations_mod.RelationManager, rel_mgr);
        }
        const ref = e.getResource(relations_mod.RelationManager) orelse return error.RelationsManagerNotFound;
        const guard = ref.lockWrite();
        const rel_ptr = try e.allocator.create(BaseType(ParamType)._Inner);
        rel_ptr.* = .{ .ref = ref, .guard = guard };
        return @ptrCast(rel_ptr);
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = ParamType;
        const rel_ptr: *RelationsInner._Inner = @ptrCast(@alignCast(ptr));
        rel_ptr.guard.deinit();
        rel_ptr.ref.deinit();
        e.allocator.destroy(rel_ptr);
    }
};

pub const RelationsSystemParam = SystemParam(ExactBaseMatcher(true, RelationsInner), RelationsSystemParamImpl);

/// OnAdded(T) system param: read-only view of components of type T
/// that were added since the last system run.
pub fn OnAdded(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_added = true;

        pub const Item = struct { entity: ecs.Entity, comp: *T };

        items: []const Item,

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "OnAdded(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

        pub fn iter(self: *const Self) []const Item {
            return self.items;
        }
    };
}

/// OnAdded(T) SystemParam matcher and applier
/// Currently this is a thin wrapper that just provides a normal Query
/// for entities with component T. A higher-level scheduler is expected
/// to constrain which entities are actually considered "added".
const OnAddedSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const Component = BaseType(ParamType).ComponentType;
        const event_type_hash = zevy_reflect.typeHash(Component);
        var results = try std.ArrayList(OnAdded(Component).Item).initCapacity(e.allocator, 16);
        defer results.deinit(e.allocator);

        var iter = e.component_added.iterator();
        while (iter.next()) |ev| {
            if (ev.data.type_hash != event_type_hash) continue;
            if (try e.getComponent(ev.data.entity, Component)) |comp_ptr| {
                try results.append(e.allocator, .{
                    .entity = ev.data.entity,
                    .comp = comp_ptr,
                });
            }
            ev.handled = true;
        }

        const slice = try results.toOwnedSlice(e.allocator);
        return ParamType{ .items = slice };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const Component = BaseType(ParamType).ComponentType;
        // Cast the opaque pointer back to OnAdded and free its allocated items
        const on_added: *OnAdded(Component) = @ptrCast(@alignCast(ptr));
        e.allocator.free(on_added.items);
    }
};

pub const OnAddedSystemParam = SystemParam(DeclMatcher(false, &.{ "ComponentType", "is_on_added" }), OnAddedSystemParamImpl);

/// OnRemoved(T) system param: exposes entities from which component T
/// was removed since last system run. This is a lightweight wrapper
/// over an event stream produced by the scheduler.
pub fn OnRemoved(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_removed = true;

        removed: []const ecs.Entity,

        pub const debugInfo = if (@import("builtin").mode == .Debug) struct {
            pub fn get() []const u8 {
                return "OnRemoved(" ++ @typeName(T) ++ ")";
            }
        }.get else void;

        pub fn iter(self: *const Self) []const ecs.Entity {
            return self.removed;
        }
    };
}

/// OnRemoved(T) SystemParam matcher and applier
/// Exposes entities from which T was removed. For now this uses an
/// EventStore of Entity generated elsewhere (e.g. by scheduler).
const OnRemovedSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        const Component = BaseType(ParamType).ComponentType;
        const event_type_hash = zevy_reflect.typeHash(Component);
        var results = try std.ArrayList(ecs.Entity).initCapacity(e.allocator, 16);
        defer results.deinit(e.allocator);

        var iter = e.component_removed.iterator();
        while (iter.next()) |ev| {
            if (ev.data.type_hash != event_type_hash) continue;
            try results.append(e.allocator, ev.data.entity);
            ev.handled = true;
        }

        const slice = try results.toOwnedSlice(e.allocator);
        return ParamType{ .removed = slice };
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        const Component = BaseType(ParamType).ComponentType;
        // Cast the opaque pointer back to OnRemoved and free its allocated items
        const on_removed: *OnRemoved(Component) = @ptrCast(@alignCast(ptr));
        e.allocator.free(on_removed.removed);
    }
};

pub const OnRemovedSystemParam = SystemParam(DeclMatcher(false, &.{ "ComponentType", "is_on_removed" }), OnRemovedSystemParamImpl);

/// Commands SystemParam matcher and applier
const CommandsSystemParamImpl = struct {
    pub fn apply(e: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
        return try CommandsInner.init(e.allocator, e);
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
        _ = ParamType;
        const commands: Commands = @ptrCast(@alignCast(ptr));
        commands.queue() catch |err| @panic(@errorName(err));
        if (!e.defer_command_flush.load(.acquire)) {
            e.flushQueuedCommands() catch |err| @panic(@errorName(err));
        }
        commands.destroy();
    }
};

pub const CommandsSystemParam = SystemParam(ExactBaseMatcher(true, CommandsInner), CommandsSystemParamImpl);

test "ResourceSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const value: i32 = 42;
    _ = try ecs_instance.addResource(i32, value);
    const res = try ResourceSystemParam.apply(&ecs_instance, Res(i32));
    defer ResourceSystemParam.deinit(&ecs_instance, @ptrCast(res), Res(i32));
    try std.testing.expect(res.get().* == 42);
}

test "ResourceMutSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    _ = try ecs_instance.addResource(i32, 1);

    {
        const res = try ResourceMutSystemParam.apply(&ecs_instance, ResMut(i32));
        defer ResourceMutSystemParam.deinit(&ecs_instance, @ptrCast(res), ResMut(i32));
        res.get().* = 99;
    }

    const verify = ecs_instance.getResource(i32).?;
    defer verify.deinit();
    var guard = verify.lockRead();
    defer guard.deinit();
    try std.testing.expectEqual(@as(i32, 99), guard.get().*);
}

test "LocalSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const local_ptr = try LocalSystemParam.apply(&ecs_instance, *Local(i32));
    local_ptr._value = 99;
    try std.testing.expect(local_ptr._value == 99);
}

test "EventReaderSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    var reader = try EventReaderSystemParam.apply(&ecs_instance, EventReader(u32));
    defer EventReaderSystemParam.deinit(&ecs_instance, @ptrCast(@alignCast(&reader)), EventReader(u32));
    try std.testing.expect(@intFromPtr(reader.event_store) != 0);
}

test "EventWriterSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    var writer = try EventWriterSystemParam.apply(&ecs_instance, EventWriter(u32));
    defer EventWriterSystemParam.deinit(&ecs_instance, @ptrCast(@alignCast(&writer)), EventWriter(u32));
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

    var on_added = try OnAddedSystemParam.apply(&manager, OnAdded(Position));
    try std.testing.expect(on_added.items.len >= 1);
    try std.testing.expect(on_added.items[0].entity.eql(entity));

    // cleanup / free allocated slice
    OnAddedSystemParam.deinit(&manager, @ptrCast(@alignCast(&on_added)), OnAdded(Position));
}

test "OnRemovedSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const Position = struct { x: f32, y: f32 };

    const entity = manager.create(.{});
    try manager.addComponent(entity, Position, Position{ .x = 7.0, .y = 8.0 });
    try manager.removeComponent(entity, Position);

    var on_removed = try OnRemovedSystemParam.apply(&manager, OnRemoved(Position));
    try std.testing.expect(on_removed.removed.len >= 1);
    try std.testing.expect(on_removed.removed[0].eql(entity));

    OnRemovedSystemParam.deinit(&manager, @ptrCast(@alignCast(&on_removed)), OnRemoved(Position));
}

test "RelationsSystemParam basic" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const Child = @import("relations.zig").Child;

    const a = manager.create(.{});
    const b = manager.create(.{});

    const rel = try RelationsSystemParam.apply(&manager, Relations);
    defer RelationsSystemParam.deinit(&manager, @ptrCast(@alignCast(rel)), Relations);

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

    const single = try SingleSystemParam.apply(&manager, Single(struct { pos: Position }));

    try std.testing.expectEqual(single.item.pos.*.x, 1.0);
    try std.testing.expectEqual(single.item.pos.*.y, 2.0);
}

test "CommandsSystemParam advanced" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const commands = try CommandsSystemParam.apply(&manager, Commands);
    defer CommandsSystemParam.deinit(&manager, @ptrCast(@alignCast(commands)), Commands);

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { dx: f32, dy: f32 };
    const entity = manager.create(.{});

    // Manually add a component to test removal
    try manager.addComponent(entity, Position, Position{ .x = 1.0, .y = 2.0 });

    // Queue operations
    try commands.addComponent(entity, Velocity, Velocity{ .dx = 0.1, .dy = 0.2 }); // Add velocity
    try commands.removeComponent(entity, Position); // Remove position
    try commands.destroyEntity(entity); // Destroy entity

    // Test EntityCommands for existing entity
    const entity2 = manager.create(.{});
    var ent_cmds = try commands.entity(entity2);
    _ = try ent_cmds.add(Position, Position{ .x = 5.0, .y = 6.0 }); // Add position via EntityCommands

    // Resource operations
    const TestResource = struct { value: i32 };
    try commands.addResource(TestResource, TestResource{ .value = 42 }); // Add resource
    try commands.removeResource(TestResource); // Remove resource

    // Relation operations
    const Child = relations_mod.Child;
    const entity3 = manager.create(.{});
    try commands.addRelation(entity2, entity3, Child); // Add relation
    try commands.removeRelation(entity2, entity3, Child); // Remove relation

    // Flush the commands
    try commands.flush(&manager);

    // Check entity was destroyed (can't get components)
    const pos_after = manager.getComponent(entity, Position);
    try std.testing.expectError(error.EntityNotAlive, pos_after);
    const vel_after = manager.getComponent(entity, Velocity);
    try std.testing.expectError(error.EntityNotAlive, vel_after);

    // Check entity2 has position added via EntityCommands
    var ent2_view = try commands.entity(entity2);
    const pos2_opt = try ent2_view.get(Position);
    try std.testing.expect(pos2_opt != null);
    const pos2 = pos2_opt.?;
    try std.testing.expect(pos2.*.x == 5.0);
    try std.testing.expect(pos2.*.y == 6.0);

    // Check resource was added then removed (not present)
    const res = manager.getResource(TestResource);
    try std.testing.expect(res == null);

    // Check relation was added then removed (not present)
    const rel_ref = manager.getResource(relations_mod.RelationManager).?;
    defer rel_ref.deinit();
    var rel_guard = rel_ref.lockWrite();
    defer rel_guard.deinit();
    try std.testing.expect(!(try rel_guard.get().has(&manager, entity2, entity3, Child)));
}

test "Commands deferred entity creation" {
    const allocator = std.testing.allocator;
    var manager = try ecs.Manager.init(allocator);
    defer manager.deinit();

    const commands = try CommandsSystemParam.apply(&manager, Commands);
    defer CommandsSystemParam.deinit(&manager, @ptrCast(@alignCast(commands)), Commands);

    const Position = struct { x: f32, y: f32 };
    const Velocity = struct { dx: f32, dy: f32 };

    // Create a deferred entity
    var ent_cmds = try commands.create();
    defer ent_cmds.deinit();

    // Get the pending entity reference
    const pending = ent_cmds.getPending().?;

    // Verify entity is not created yet
    try std.testing.expect(pending.entity == null);

    // Queue component additions
    _ = try ent_cmds.add(Position, Position{ .x = 10.0, .y = 20.0 });
    _ = try ent_cmds.add(Velocity, Velocity{ .dx = 1.0, .dy = 2.0 });

    // Entity still not created
    try std.testing.expect(pending.entity == null);

    // Flush to create entity and apply queued operations
    try ent_cmds.flush();

    // Now the entity should be created
    try std.testing.expect(pending.entity != null);

    // Get the actual entity
    const entity = pending.get();

    // Verify components were added
    const pos = try ent_cmds.get(Position);
    try std.testing.expect(pos != null);
    try std.testing.expect(pos.?.*.x == 10.0);
    try std.testing.expect(pos.?.*.y == 20.0);

    const vel = try ent_cmds.get(Velocity);
    try std.testing.expect(vel != null);
    try std.testing.expect(vel.?.*.dx == 1.0);
    try std.testing.expect(vel.?.*.dy == 2.0);

    try std.testing.expect(ent_cmds.entity().eql(entity));
}
