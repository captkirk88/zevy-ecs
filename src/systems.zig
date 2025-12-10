const std = @import("std");
const builtin = @import("builtin");
const ecs_mod = @import("ecs.zig");
const world = @import("world.zig");
const events = @import("events.zig");
const registry = @import("systems.registry.zig");
const params = @import("systems.params.zig");
const scheduler_mod = @import("scheduler.zig");
const Commands = @import("commands.zig").Commands;
const reflect = @import("zevy_reflect");

const is_debug = builtin.mode == .Debug;

pub const ParamDebugInfo = struct {
    name: []const u8,
};

/// Debug information for a system (only available in debug builds)
pub const SystemDebugInfo = struct {
    signature: []const u8,
    params: []const ParamDebugInfo,
};

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
        debug_info: if (is_debug) SystemDebugInfo else void,

        pub const return_type = ReturnType;

        pub fn eraseType(self: @This()) UntypedSystemHandle {
            return if (is_debug)
                UntypedSystemHandle{ .handle = self.handle, .debug_info = self.debug_info }
            else
                UntypedSystemHandle{ .handle = self.handle, .debug_info = {} };
        }

        pub fn format(
            self: @This(),
            writer: anytype,
        ) !void {
            if (is_debug) {
                try writer.print("SystemHandle({s}){{ .handle = {}, .sig = \"{s}\", .params = {} }}", .{ @typeName(ReturnType), self.handle, self.debug_info.signature, self.debug_info.params.len });
            } else {
                try writer.print("SystemHandle({s}){{ .handle = {} }}", .{ @typeName(ReturnType), self.handle });
            }
        }
    };
}

/// Type-erased system handle for storage in containers.
pub const UntypedSystemHandle = struct {
    handle: u64,
    debug_info: if (is_debug) SystemDebugInfo else void,

    pub fn formatNumber(
        self: UntypedSystemHandle,
        writer: anytype,
        options: std.fmt.Number,
    ) !void {
        _ = options;
        try writer.print("{d}", .{self.handle});
    }

    pub fn format(
        self: UntypedSystemHandle,
        writer: anytype,
    ) !void {
        if (is_debug) {
            try writer.print("SystemHandle{{ .handle = {}, .sig = \"{s}\", .params = {} }}", .{ self.handle, self.debug_info.signature, self.debug_info.params.len });
        } else {
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
        /// Debug information about the system (only populated in debug builds)
        debug_info: if (is_debug) SystemDebugInfo else void,

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
    if (!comptime reflect.hasFuncWithArgs(ParamRegistry, "apply", &[_]type{ *ecs_mod.Manager, type })) {
        @compileError("ParamRegistry must have an 'apply' function with signature: fn (*ecs_mod.Manager, type) type");
    }
    return &struct {
        pub fn trampoline(ecs: *ecs_mod.Manager, ctx: ?*anyopaque) anyerror!ReturnType {
            if (ctx == null) return error.SystemContextNull;

            const ContextType = SystemWithArgsContext(Args);
            const context: *ContextType = @ptrCast(@alignCast(ctx));

            const FnType = @TypeOf(system_fn);
            const fn_ptr_typed: *const FnType = @ptrCast(@alignCast(context.fn_ptr));

            const info = comptime @typeInfo(system_type);
            if (info != .@"fn") @compileError("System must be a function: " ++ @typeName(system_type));

            const fn_info = info.@"fn";
            const param_count = fn_info.params.len;

            // Get the number of injected args
            const args_info = @typeInfo(Args);
            const injected_arg_count = if (args_info == .@"struct") args_info.@"struct".fields.len else 0;

            // Ensure the function expects the injected args
            if (param_count < injected_arg_count) {
                @compileError("System function does not have enough parameters for injected arguments: " ++ @typeName(system_type));
            }

            // Build tuple type for registry-resolved params
            comptime var param_types: []const type = &[_]type{};
            inline for (fn_info.params[injected_arg_count..]) |param| {
                const ParamType = param.type.?;
                // All system params are now passed by value, not by pointer
                param_types = param_types ++ &[_]type{ParamType};
            }
            const ResolvedArgsTuple = std.meta.Tuple(param_types);

            // Build resolved args by calling apply for each param
            const resolved_args: ResolvedArgsTuple = blk: {
                var args: ResolvedArgsTuple = undefined;
                inline for (fn_info.params[injected_arg_count..], 0..) |param, i| {
                    const ParamType = param.type.?;
                    args[i] = try ParamRegistry.apply(ecs, ParamType);
                }
                break :blk args;
            };

            const return_type = comptime fn_info.return_type orelse void;
            const return_type_info = comptime @typeInfo(return_type);
            const is_error_union = comptime return_type_info == .error_union;

            // Build args tuple with injected args first, then resolved args
            // Injected args are provided by ToSystemWithArgs and come first in the function signature
            const all_args_tuple = context.args ++ resolved_args;

            // Deallocate any system param resources after the system finishes.
            // We need to call deinit for each resolved argument type if it provides a deinit implementation.
            // This must be done in a defer that wraps the actual system call to ensure cleanup happens AFTER execution.
            defer {
                inline for (fn_info.params[injected_arg_count..], 0..) |param, i| {
                    const ParamType = param.type.?;
                    // For pointer types (like *Commands), we need to pass the pointer value itself,
                    // not a pointer to the pointer. The resolved_args[i] already contains the pointer.
                    const resolved_ptr: *anyopaque = blk: {
                        const param_type_info = @typeInfo(ParamType);
                        if (param_type_info == .pointer) {
                            // ParamType is already a pointer (e.g., *Commands), so resolved_args[i] is the pointer value
                            // We cast the pointer value directly to *anyopaque
                            break :blk @ptrCast(resolved_args[i]);
                        } else {
                            // For non-pointer types, take address of the value
                            break :blk @ptrCast(@alignCast(@constCast(&resolved_args[i])));
                        }
                    };
                    ParamRegistry.deinit(ecs, resolved_ptr, ParamType);
                }
            }

            if (is_error_union) {
                return try @call(.auto, fn_ptr_typed, all_args_tuple);
            } else {
                return @call(.auto, fn_ptr_typed, all_args_tuple);
            }
        }
    }.trampoline;
}

inline fn describeSystem(comptime system_fn: anytype) []const u8 {
    const type_info = reflect.ReflectInfo.from(@TypeOf(system_fn)) orelse reflect.ReflectInfo.Unknown;

    return type_info.toString();
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

pub const MAX_SYSTEM_ARGS = 16;

/// Struct to hold all system parameters for trampoline argument passing
fn SystemParamArgs(comptime system_fn: anytype) type {
    const info = @typeInfo(@TypeOf(system_fn));
    if (info != .@"fn") @compileError("SystemParamArgs expects a function type");
    const fn_info = info.@"fn";
    const max_params = MAX_SYSTEM_ARGS;
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
            if (idx >= self.count) std.debug.panic("SystemParamArgs.get: index out of bounds: {d} >= {d}", .{ idx, self.count });

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

    const debug_info = if (is_debug) blk: {
        const fn_info = @typeInfo(@TypeOf(system_fn)).@"fn";
        const param_count = fn_info.params.len;

        const param_list = comptime blk_param: {
            var arr: [param_count]ParamDebugInfo = undefined;
            for (fn_info.params[0..], 0..) |param, i| {
                const param_type = param.type.?;
                // Check if the type has a debugInfo decl (which should be a const string) and use that, otherwise use @typeName
                const type_name: ParamDebugInfo = blk2: {
                    const type_info = @typeInfo(param_type);
                    // Only check for debugInfo on struct/union/enum types
                    const can_have_decl = type_info == .@"struct" or type_info == .@"union" or type_info == .@"enum";
                    if (can_have_decl and reflect.hasFunc(param_type, "debugInfo")) {
                        break :blk2 .{ .name = param_type.debugInfo() };
                    } else {
                        break :blk2 .{ .name = @typeName(param_type) };
                    }
                };
                arr[i] = type_name;
            }
            break :blk_param arr;
        };

        // Build clean function signature from param debug info instead of raw types
        const signature_str = comptime blk_sig: {
            var sig: []const u8 = "fn(";
            var first = true;
            for (param_list) |param_info| {
                if (!first) sig = sig ++ ", ";
                first = false;
                sig = sig ++ param_info.name;
            }
            sig = sig ++ ")";
            // Add return type
            const return_type = fn_info.return_type orelse void;
            if (return_type != void) {
                sig = sig ++ " " ++ @typeName(return_type);
            }
            break :blk_sig sig;
        };

        break :blk SystemDebugInfo{
            .signature = signature_str,
            .params = &param_list,
        };
    } else {};

    return System(ReturnType){
        .run = makeSystemTrampolineWithArgs(system_fn, ReturnType, Registry, ArgsType),
        .ctx = @ptrCast(static_context.context),
        .debug_info = debug_info,
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

/// Pipes the output of the first system function into the second system function.
/// The first function should return a value, the second should accept it as the first parameter after *ECS.
/// Returns a combined function that can be used with ToSystem.
///
/// Example:
/// ```zig
/// fn produceData(commands: *Commands, query: Query()) []const u8 {
///     // Logic to generate some data
///     return "Hello from first system";
/// }
///
/// fn processData(data: []const u8, commands: *Commands) void {
///     // Use the data from the first system
///     std.debug.print("Processed: {s}\n", .{data});
/// }
///
/// // Create a piped system that runs produceData and passes its output to processData
/// const pipedSystem = ToSystem(pipe(produceData, processData, DefaultRegistry), DefaultRegistry);
/// ```
pub fn pipe(comptime first: anytype, comptime second: anytype, comptime ParamRegistry: type) System(void) {
    // Get return type of first function to pass to second
    //const FirstReturnType = ToSystemReturnType(first);
    const f = struct {
        pub var first_system: ?System(ToSystemReturnType(first)) = null;

        pub fn combined(commands: *Commands) !void {
            if (first_system == null) {
                first_system = ToSystem(first, ParamRegistry);
            }
            // Run first system and get its output
            const first_result = try first_system.?.run(commands.manager, first_system.?.ctx);
            // Create second system with the first system's output as an injected argument
            const second_system = ToSystemWithArgs(second, .{first_result}, ParamRegistry);
            _ = try second_system.run(commands.manager, second_system.ctx);
        }
    }.combined;
    return ToSystem(f, ParamRegistry);
}

/// Returns a system that runs `system` only if `predicate` returns true.
/// Achieved by piping predicate and system, system only runs if predicate output is true.
///
/// Example:
/// ```zig
/// fn shouldRunSystem(query: Query(.{pos: Position, vel: Velocity},.{})) bool {
///     // Check some condition, e.g., if there are entities with a specific component
///     return query.hasNext();
/// }
///
/// fn updatePositions(commands: *Commands, query: Query(.{pos: Position, vel: Velocity}, .{})) void {
///     // System logic to update positions
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
pub fn runIf(comptime predicate: anytype, comptime system: anytype, comptime ParamRegistry: type) System(void) {
    if (ToSystemReturnType(predicate) != bool) {
        @compileError("Predicate must return boolean" ++ @typeName(predicate));
    }
    return pipe(
        predicate,
        struct {
            pub var system_handle: ?System(void) = null;

            pub fn run(cond: bool, commands: *Commands) !void {
                if (cond) {
                    if (system_handle == null) {
                        system_handle = ToSystem(system, ParamRegistry);
                    }
                    _ = try system_handle.?.run(commands.manager, system_handle.?.ctx);
                }
            }
        }.run,
        ParamRegistry,
    );
}
