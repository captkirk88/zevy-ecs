const std = @import("std");
const ecs = @import("ecs.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");
const reflect = @import("zevy_reflect");

const errors = @import("errors.zig");

/// Default system parameter registry including Query, Res, ResMut, Local, EventReader, EventWriter, State, and NextState
pub const DefaultParamRegistry = SystemParamRegistry(&[_]type{
    params.StateSystemParam,
    params.NextStateSystemParam,
    params.EventReaderSystemParam,
    params.EventWriterSystemParam,
    params.ResourceSystemParam,
    params.ResourceMutSystemParam,
    params.SingleSystemParam,
    params.QuerySystemParam,
    params.LocalSystemParam,
    params.RelationsSystemParam,
    params.OnAddedSystemParam,
    params.OnRemovedSystemParam,
    params.CommandsSystemParam,
});

const SystemParamTemplate = reflect.Template(struct {
    pub const Name: []const u8 = "SystemParam";

    pub fn matches(comptime T: type) bool {
        _ = T;
        unreachable;
    }

    pub fn apply(e: *ecs.Manager, comptime T: type) anyerror!T {
        _ = e;
        unreachable;
    }

    pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
        _ = e;
        _ = ptr;
        _ = T;
        unreachable;
    }
});

/// SystemParam registry for runtime-extensible parameter type analysis and instantiation
pub fn SystemParamRegistry(comptime RegisteredParams: []const type) type {
    inline for (RegisteredParams) |T| {
        SystemParamTemplate.validate(T);
    }
    return struct {
        pub const registered_params = RegisteredParams;

        pub inline fn len() usize {
            return registered_params.len;
        }

        pub inline fn contains(comptime ParamType: type) bool {
            inline for (registered_params) |SystemParam| {
                if (comptime SystemParam.matches(ParamType)) return true;
            }
            return false;
        }

        /// Get the registered SystemParam type at the given index.
        pub inline fn get(index: usize) type {
            if (index >= registered_params.len) {
                if (@import("builtin").mode == .Debug) {
                    std.debug.panic("SystemParamRegistry: index out of bounds: {d} (len = {d})", .{ index, registered_params.len });
                } else {
                    @compileError("SystemParamRegistry: index out of bounds");
                }
            }

            return registered_params[index];
        }

        /// Get the registered SystemParam type that matches the given ParamType at compile time.
        pub inline fn getFor(comptime ParamType: type) type {
            inline for (registered_params) |SystemParam| {
                if (comptime SystemParam.matches(ParamType)) return SystemParam;
            }
            if (@import("builtin").mode == .Debug) {
                std.debug.panic("SystemParamRegistry: Unknown SystemParam type: {s}", .{@typeName(ParamType)});
            } else {
                @compileError(std.fmt.comptimePrint("SystemParamRegistry: Unknown SystemParam type: {s}", .{@typeName(ParamType)}));
            }
        }

        pub inline fn params() []const type {
            return registered_params;
        }

        pub inline fn apply(ecs_instance: *ecs.Manager, comptime ParamType: type) anyerror!ParamType {
            inline for (registered_params) |SystemParam| {
                if (comptime SystemParam.matches(ParamType)) {
                    return try SystemParam.apply(ecs_instance, ParamType);
                }
            }
            if (@import("builtin").mode == .Debug) {
                std.debug.panic("SystemParamRegistry: Unknown SystemParam type: {s}", .{@typeName(ParamType)});
            } else {
                return errors.SystemParamError.UnknownSystemParam;
            }
        }

        pub fn deinit(ecs_instance: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
            inline for (registered_params) |SystemParam| {
                if (comptime SystemParam.matches(ParamType)) {
                    if (reflect.hasFuncWithArgs(SystemParam, "deinit", &[_]type{ *ecs.Manager, *anyopaque, type })) {
                        SystemParam.deinit(ecs_instance, ptr, ParamType);
                    }
                    return;
                }
            }
        }
    };
}

/// Merge two or more SystemParamRegistry, deduplicating types at comptime
///
/// Example:
/// ```zig
/// const NewSystemParamRegistry = SystemParamRegistry(&[_]type{ GameRulesParam, DefaultRegistry });
/// const MergedRegistry = MergedSystemParamRegistry(.{ DefaultParamRegistry, NewSystemParamRegistry });
/// ```
pub fn MergedSystemParamRegistry(comptime registries: anytype) type {
    comptime var merged_types: []const type = &[_]type{};
    inline for (registries) |reg| {
        // Check if this is a type that represents a registry
        switch (@typeInfo(@TypeOf(reg))) {
            .type => {
                // reg is a type, check if it has registered_params field
                if (@typeInfo(reg) == .@"struct" and @hasDecl(reg, "registered_params")) {
                    inline for (reg.registered_params) |T| {
                        flattenParamTypes(T, &merged_types);
                    }
                } else {
                    // It's just a regular SystemParam type
                    flattenParamTypes(reg, &merged_types);
                }
            },
            else => {
                // Handle individual SystemParam types passed as values
                flattenParamTypes(@TypeOf(reg), &merged_types);
            },
        }
    }
    return SystemParamRegistry(merged_types);
}

/// Recursively flatten types into merged_types array, avoiding duplicates
pub fn flattenParamTypes(comptime T: type, merged_types: *[]const type) void {
    if (@typeInfo(T) == .@"struct" and @hasField(T, "registered_params")) {
        inline for (T.registered_params) |TT| {
            flattenParamTypes(TT, merged_types);
        }
    } else {
        var found = false;
        inline for (merged_types.*) |MT| {
            if (T == MT) {
                found = true;
                break;
            }
        }
        if (!found) merged_types.* = merged_types.* ++ &[_]type{T};
    }
}

test "merged SystemParamRegistry" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const CustomParam = struct {
        pub fn matches(comptime T: type) bool {
            return @typeInfo(T) == .int;
        }
        pub fn apply(_: *ecs.Manager, comptime T: type) anyerror!T {
            return 1;
        }
        pub fn deinit(_: *ecs.Manager, _: *anyopaque, _: type) void {}
    };
    const CustomRegistry = SystemParamRegistry(&[_]type{CustomParam});
    const merge = MergedSystemParamRegistry(.{ DefaultParamRegistry, CustomRegistry });
    try std.testing.expect(merge.len() == 14); // State, NextState, EventReader, EventWriter, Res, ResMut, Query, Local, Relations, OnAdded, OnRemoved, Single, Commands, CustomParam

    // Test that we can apply a custom param (returns value)
    const custom_val = try merge.apply(&ecs_instance, i32);
    try std.testing.expect(custom_val == 1);

    // Test that we can apply a default registry param
    const value: f32 = 42.0;
    try ecs_instance.addResourceRetained(f32, value);
    var res = try merge.apply(&ecs_instance, params.Res(f32));
    defer params.ResourceSystemParam.deinit(&ecs_instance, @ptrCast(res), params.Res(f32));
    try std.testing.expect(res.get().* == 42.0);
}

test "CustomSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const CustomParam = struct {
        pub fn matches(comptime T: type) bool {
            return @typeInfo(T) == .int;
        }
        pub fn apply(_: *ecs.Manager, comptime T: type) anyerror!T {
            return 123;
        }
        pub fn deinit(_: *ecs.Manager, _: *anyopaque, _: type) void {}
    };
    const registry = SystemParamRegistry(&[_]type{CustomParam});
    const custom_val = try registry.apply(&ecs_instance, i32);
    try std.testing.expect(custom_val == 123);
}

test "CustomSystemParam with Query, Res, Local fields" {
    const query = @import("query.zig");
    const allocator = std.testing.allocator;

    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const res_val: i32 = 7;
    try ecs_instance.addResourceRetained(i32, res_val);

    const TestComponentA = struct { a: i32 };
    const TestComponentB = struct { b: u32 };
    const ComplexType = struct {
        /// Unfortunately with the way zig handles anonymous structs we need to define this separately
        pub const IncludeTypes = struct { a: TestComponentA, b: TestComponentB };
        query: query.Query(IncludeTypes),
        res: params.Res(i32),
        local: *params.Local(u64),
    };
    const CustomComplexParam = struct {
        pub fn matches(comptime T: type) bool {
            const Base = switch (@typeInfo(T)) {
                .pointer => |pointer_info| pointer_info.child,
                else => T,
            };
            const ti = @typeInfo(Base);
            return ti == .@"struct" and @hasField(Base, "query") and @hasField(Base, "res") and @hasField(Base, "local");
        }
        pub fn apply(e: *ecs.Manager, comptime T: type) anyerror!T {
            const query_val = e.query(ComplexType.IncludeTypes);
            const res_value = try params.ResourceSystemParam.apply(e, params.Res(i32));
            const local_ptr = try params.LocalSystemParam.apply(e, *params.Local(u64));
            return T{
                .query = query_val,
                .res = res_value,
                .local = local_ptr,
            };
        }
        pub fn deinit(e: *ecs.Manager, ptr: *anyopaque, comptime T: type) void {
            const complex: *T = @ptrCast(@alignCast(ptr));
            complex.query.deinit();
            params.ResourceSystemParam.deinit(e, @ptrCast(complex.res), params.Res(i32));
        }
    };

    const registry = SystemParamRegistry(&[_]type{CustomComplexParam});
    var complex = try registry.apply(&ecs_instance, ComplexType);
    defer registry.deinit(&ecs_instance, @ptrCast(@alignCast(&complex)), ComplexType);
    try std.testing.expect(@intFromPtr(complex.query.storage) != 0);
    try std.testing.expect(complex.res.get().* == 7);
    try std.testing.expect(@intFromPtr(complex.local) != 0);
}
