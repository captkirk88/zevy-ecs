const std = @import("std");
const ecs_mod = @import("ecs.zig");
const world = @import("world.zig");
const events = @import("events.zig");
const registry = @import("systems.registry.zig");
const scheduler_mod = @import("scheduler.zig");
const reflect = @import("reflect.zig");

pub const SystemType = enum {
    /// A system represented as a function
    func,
    /// A system represented as a typed SystemHandle
    handle,
    /// A system represented as an UntypedSystemHandle
    untyped,
    /// Not a valid system type
    invalid,
};

/// Determines the SystemType from a type.
pub fn getSystemTypeFromType(comptime T: type) SystemType {
    const type_info = @typeInfo(T);

    // Check if it's a function
    if (type_info == .@"fn") {
        return .func;
    }

    // Check if it's a pointer to a function
    if (type_info == .pointer) {
        const ptr_info = type_info.pointer;
        if (@typeInfo(ptr_info.child) == .@"fn") {
            return .func;
        }
    }

    // Check if it's an UntypedSystemHandle
    if (T == UntypedSystemHandle) {
        return .untyped;
    }

    // Check if it's a typed SystemHandle by looking for the handle field and return_type decl
    if (type_info == .@"struct") {
        if (@hasField(T, "handle") and @hasDecl(T, "return_type")) {
            return .handle;
        }
    }

    return .invalid;
}

/// A handle to a cached system.
/// Stores the hash and the return type at compile time.
pub fn SystemHandle(comptime ReturnType: type) type {
    return struct {
        handle: u64,

        pub const return_type = ReturnType;

        pub fn eraseType(self: @This()) UntypedSystemHandle {
            return UntypedSystemHandle{ .handle = self.handle };
        }
    };
}

/// Type-erased system handle for storage in containers.
pub const UntypedSystemHandle = struct {
    handle: u64,

    pub fn formatNumber(self: UntypedSystemHandle, writer: anytype, _: std.fmt.Number) !void {
        try writer.print("{d}", .{self.handle});
    }

    pub fn format(self: UntypedSystemHandle, comptime fmt_str: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        if (fmt_str.len > 0 and fmt_str[0] == 'd') {
            // For {d}, just print the handle number
            try writer.print("{d}", .{self.handle});
        } else {
            // For other formats, print the full struct
            try writer.print("SystemHandle{{ .handle = {} }}", .{self.handle});
        }
    }
};

/// Represents a cached, type-erased system ready to run on an ECS instance.
pub fn System(comptime ReturnType: type) type {
    return struct {
        /// The function pointer to the specialized trampoline (type-erased, takes ECS pointer and static context)
        run: *const fn (*ecs_mod.Manager, ?*anyopaque) anyerror!ReturnType,
        /// Opaque pointer to static metadata/context for argument construction
        ctx: ?*anyopaque,

        pub const return_type = ReturnType;
    };
}

// /// Top-level trampoline for type-erased system invocation
// /// Compile-time generated trampoline for a specific system_fn and its parameter layout
// fn makeSystemTrampoline(
//     comptime system_fn: anytype,
//     comptime ReturnType: type,
//     comptime SystemParamsRegistry: type,
// ) *const fn (*ecs_mod.Manager, ?*anyopaque) anyerror!ReturnType {
//     return makeSystemTrampolineWithArgs(system_fn, ReturnType, SystemParamsRegistry, @TypeOf(.{}));
// }

/// Converts a system function into a System struct for caching and later execution.
pub fn ToSystem(system_fn: anytype, comptime SystemParamsRegistry: type) System(ToSystemReturnType(system_fn)) {
    return ToSystemWithArgs(system_fn, .{}, SystemParamsRegistry);
}

/// Context struct to hold both the function pointer and injected arguments
fn SystemWithArgsContext(comptime Args: type) type {
    return struct {
        const Self = @This();
        fn_ptr: *const anyopaque,
        args: Args,
    };
}

/// Specialized trampoline for systems with injected arguments
/// Specialized trampoline for systems with injected arguments
fn makeSystemTrampolineWithArgs(comptime system_fn: anytype, comptime ReturnType: type, comptime ParamRegistry: type, comptime Args: type) *const fn (*ecs_mod.Manager, ?*anyopaque) anyerror!ReturnType {
    const system_type = @TypeOf(system_fn);
    if (!comptime reflect.verifyFuncArgs(ParamRegistry, "apply", &[_]type{ *ecs_mod.Manager, type })) {
        @compileError("ParamRegistry must have an 'apply' function with signature: fn (*ecs_mod.Manager, type) type");
    }
    const log = std.log.scoped(.zevy_ecs);
    log.debug("Creating trampoline for system: {s}", .{@typeName(system_type)});
    return &struct {
        pub fn trampoline(ecs: *ecs_mod.Manager, ctx: ?*anyopaque) anyerror!ReturnType {
            if (ctx == null) return error.SystemContextNull;

            const ContextType = SystemWithArgsContext(Args);
            const context: *ContextType = @ptrCast(@alignCast(ctx));

            const FnType = @TypeOf(system_fn);
            const fn_ptr_typed: *const FnType = @ptrCast(@alignCast(context.fn_ptr));

            const info = comptime @typeInfo(system_type);
            if (info != .@"fn") @compileError("System function must have Fn type info: " ++ @typeName(system_type));

            const fn_info = info.@"fn";
            const param_count = fn_info.params.len;
            if (param_count == 0 or fn_info.params[0].type != *ecs_mod.Manager) {
                @compileError("System function must have *Manager as first parameter: " ++ @typeName(system_type));
            }

            // Get the number of injected args
            const args_info = @typeInfo(Args);
            const injected_arg_count = if (args_info == .@"struct") args_info.@"struct".fields.len else 0;

            // Ensure the function expects the injected args after ECS
            if (param_count < 1 + injected_arg_count) {
                @compileError("System function does not have enough parameters for injected arguments: " ++ @typeName(system_type));
            }

            // Build tuple type for registry-resolved params (skip ECS and injected args)
            comptime var param_types: []const type = &[_]type{};
            inline for (fn_info.params[1 + injected_arg_count ..]) |param| {
                const ParamType = param.type.?;
                // All system params are now passed by value, not by pointer
                param_types = param_types ++ &[_]type{ParamType};
            }
            const ResolvedArgsTuple = std.meta.Tuple(param_types);

            // Build resolved args by calling apply for each param
            const resolved_args: ResolvedArgsTuple = blk: {
                var args: ResolvedArgsTuple = undefined;
                inline for (fn_info.params[1 + injected_arg_count ..], 0..) |param, i| {
                    const ParamType = param.type.?;
                    args[i] = ParamRegistry.apply(ecs, ParamType);
                }
                break :blk args;
            };

            const return_type = comptime fn_info.return_type orelse void;
            const return_type_info = comptime @typeInfo(return_type);
            const is_error_union = comptime return_type_info == .error_union;

            // Build args tuple with mutable resolved args
            const all_args_tuple = .{ecs} ++ context.args ++ resolved_args;
            // Deallocate any system param resources after the system finishes.
            // We need to call deinit for each resolved argument type if it provides a deinit implementation.
                inline for (fn_info.params[1 + injected_arg_count ..], 0..) |param, i| {
                const ParamType = param.type.?;
                const resolved_ptr: *anyopaque = @ptrCast(@constCast(@alignCast(&resolved_args[i])));
                defer ParamRegistry.deinit(ecs, resolved_ptr, ParamType);
            }
            if (is_error_union) {
                return try @call(.auto, fn_ptr_typed, all_args_tuple);
            } else {
                return @call(.auto, fn_ptr_typed, all_args_tuple);
            }
        }
    }.trampoline;
}

inline fn expandArgs(
    comptime Types: []const type,
    ecs: *ecs_mod.Manager,
    raw: []const *anyopaque,
) std.meta.Tuple(Types) {
    if (Types.len == 0) return .{};
    if (raw.len + 1 != Types.len) @panic("expandArgs: mismatched raw argument count");
    return expandArgsImpl(Types, ecs, raw, 0);
}

inline fn expandArgsImpl(
    comptime Types: []const type,
    ecs: *ecs_mod.Manager,
    raw: []const *anyopaque,
    comptime idx: usize,
) std.meta.Tuple(Types[idx..]) {
    if (idx == Types.len) return .{};

    const T = Types[idx];
    const head = if (idx == 0)
        ecs
    else
        loadArg(T, raw[idx - 1]);

    const tail = expandArgsImpl(Types, ecs, raw, idx + 1);
    return .{head} ++ tail;
}

inline fn loadArg(comptime T: type, ptr: *anyopaque) T {
    const info = @typeInfo(T);
    return switch (info) {
        .pointer => @as(T, @ptrCast(@alignCast(ptr))),
        .optional => |opt| blk: {
            const Child = opt.child orelse return null;
            if (@typeInfo(Child) == .pointer) {
                break :blk @as(T, @ptrCast(@alignCast(ptr)));
            }
            const child_ptr = @as(*Child, @ptrCast(@alignCast(ptr)));
            break :blk @as(T, child_ptr.*);
        },
        else => {
            const typed_ptr = @as(*T, @ptrCast(@alignCast(ptr)));
            return typed_ptr.*;
        },
    };
}

/// Struct to hold all system parameters for trampoline argument passing
fn SystemParamArgs(comptime system_fn: anytype) type {
    const info = @typeInfo(@TypeOf(system_fn));
    if (info != .@"fn") @compileError("SystemParamArgs expects a function type");
    const fn_info = info.@"fn";
    const max_params = 16;
    comptime var param_types: [max_params]type = undefined;
    comptime var param_count: usize = 0;
    inline for (fn_info.params[1..], 0..) |param, i| {
        if (param_count >= max_params) @compileError("SystemParamArgs: too many parameters (max 16)");
        param_types[i] = param.type.?;
        param_count += 1;
    }
    return struct {
        args: [max_params]?*anyopaque,
        count: usize,

        pub fn get(self: *const @This(), idx: usize) ?*anyopaque {
            if (idx >= self.count) @panic("SystemParamArgs: index out of bounds");

            return self.args[idx];
        }
    };
}

/// Converts a system function with injected arguments into a System struct.
/// The injected arguments are provided as a tuple and will be passed to the system function
/// after the ECS parameter but before any registry-resolved parameters.
///
/// Example:
/// ```zig
/// fn mySystem(ecs: *ECS, value: i32, name: []const u8, query: Query(struct{pos: Position}, struct{})) void {
///     // value and name are injected args, query is resolved by registry
/// }
///
/// const system = ToSystemWithArgs(mySystem, .{42, "test"}, MyRegistry);
/// ```
pub fn ToSystemWithArgs(system_fn: anytype, args: anytype, comptime Registry: type) System(ToSystemReturnType(system_fn)) {
    const ReturnType = ToSystemReturnType(system_fn);
    const ArgsType = @TypeOf(args);
    const ContextType = SystemWithArgsContext(ArgsType);
    const size = @sizeOf(ContextType);

    // Include the function type in the struct to make static_context unique per function
    const static_context = struct {
        pub const system_fn_type = @TypeOf(system_fn);
        pub const AlignedBuffer = extern struct {
            _align: [0]u8 align(@alignOf(ContextType)),
            buffer: [size]u8,
        };
        // Initialize storage to zeros instead of undefined to avoid garbage in release mode
        var storage: AlignedBuffer = .{ ._align = .{}, .buffer = [_]u8{0} ** size };
        var context: ?*ContextType = null;
        var initialized: bool = false;
    };

    if (!static_context.initialized) {
        const buf_ptr = &static_context.storage.buffer;
        const ctx = @as(*ContextType, @ptrCast(@alignCast(buf_ptr)));
        ctx.* = ContextType{
            .fn_ptr = @ptrCast(@constCast(&system_fn)),
            .args = args,
        };
        static_context.context = ctx;
        static_context.initialized = true;
    }

    return System(ReturnType){
        .run = makeSystemTrampolineWithArgs(system_fn, ReturnType, Registry, ArgsType),
        .ctx = @ptrCast(static_context.context),
    };
}

pub fn ToSystemReturnType(comptime system_fn: anytype) type {
    const FnInfo = @typeInfo(@TypeOf(system_fn));

    // Get the function's actual return type
    const fn_return_type = FnInfo.@"fn".return_type orelse void;
    const fn_return_info = @typeInfo(fn_return_type);

    // If function returns an error union, unwrap to get the payload type
    if (fn_return_info == .error_union) {
        return fn_return_info.error_union.payload;
    }

    // Otherwise return the function's return type as-is
    return fn_return_type;
}

pub fn Res(comptime T: type) type {
    return struct {
        ptr: *T,
    };
}

/// OnAdded(T) system param: read-only view of components of type T
/// that were added since the last system run.
pub fn OnAdded(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_added = true;

        pub const Item = struct { entity: ecs_mod.Entity, comp: ?*T };

        items: []const Item,

        pub fn iter(self: *const Self) []const Item {
            return self.items;
        }
    };
}

/// OnRemoved(T) system param: exposes entities from which component T
/// was removed since last system run. This is a lightweight wrapper
/// over an event stream produced by the scheduler.
pub fn OnRemoved(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ComponentType = T;
        pub const is_on_removed = true;

        removed: []const ecs_mod.Entity,

        pub fn iter(self: *const Self) []const ecs_mod.Entity {
            return self.removed;
        }
    };
}

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
        pub fn isActive(self: *const Self, state: StateEnum) bool {
            return self.state_mgr.isInState(state);
        }

        /// Get the currently active state value
        pub fn get(self: *const Self) ?StateEnum {
            return self.state_mgr.getActiveState();
        }
    };
}

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
        pub fn set(self: *Self, state: StateEnum) void {
            self.state_mgr.transitionTo(state) catch |err| {
                std.debug.panic("Failed to transition to state: {}", .{err});
            };
        }
    };
}

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

pub const Relations = @import("relations.zig").RelationManager;

/// Pipes the output of the first system function into the second system function.
/// The first function should return a value, the second should accept it as the first parameter after *ECS.
/// Returns a combined function that can be used with ToSystem.
///
/// Example:
/// ```zig
/// fn produceData(ecs: *ecs_mod.Manager, query: ecs_mod.Query()) []const u8 {
///     // Logic to generate some data
///     return "Hello from first system";
/// }
///
/// fn processData(ecs: *ecs_mod.Manager, data: []const u8) void {
///     // Use the data from the first system
///     std.debug.print("Processed: {s}\n", .{data});
/// }
///
/// // Create a piped system that runs produceData and passes its output to processData
/// const pipedSystem = ToSystem(pipe(produceData, processData, DefaultRegistry), DefaultRegistry);
/// ```
pub fn pipe(comptime first: anytype, comptime second: anytype, comptime ParamRegistry: type) System(void) {
    const f = struct {
        pub fn combined(ecs: *ecs_mod.Manager) !void {
            // Run first system and get its output
            const first_system = ToSystem(first, ParamRegistry);
            const first_result = try first_system.run(ecs, first_system.ctx);

            // Create second system with the first system's output as an injected argument
            const second_system = ToSystemWithArgs(second, .{first_result}, ParamRegistry);
            _ = try second_system.run(ecs, second_system.ctx);
        }
    }.combined;
    return ToSystem(f, ParamRegistry);
}

/// Returns a system that runs `system` only if `predicate` returns true.
/// Achieved by piping predicate and system, system only runs if predicate output is true.
///
/// Example:
/// ```zig
/// fn shouldRunSystem(ecs: *zevy_ecs.Manager, query: Query(.{pos: Position, vel: Velocity},.{})) bool {
///     // Check some condition, e.g., if there are entities with a specific component
///     return query.count() > 0;
/// }
///
/// fn updatePositions(ecs: *zevy_ecs.Manager) void {
///     // System logic to update positions
///     var query = ecs.query(.{pos: Position, vel: Velocity}, .{});
///     while (query.next()) |q| {
///         // Update position based on velocity
///         q.pos.*.x += q.vel.*.dx;
///         q.pos.*.y += q.vel.*.dy;
///     }
/// }
///
/// // Create a conditional system that only runs updatePositions if shouldRunSystem returns true
/// const conditionalSystem = run_if(shouldRunSystem, updatePositions, DefaultRegistry);
/// ```
pub fn runIf(comptime predicate: anytype, comptime system: anytype, ParamRegistry: type) System(void) {
    return pipe(
        predicate,
        struct {
            pub fn run(ecs: *ecs_mod.Manager, cond: bool) !void {
                if (cond) {
                    const sys = ecs.createSystem(system, ParamRegistry);
                    _ = try sys.run(ecs, sys.ctx);
                }
            }
        }.run,
        ParamRegistry,
    );
}
