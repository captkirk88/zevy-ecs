const std = @import("std");
const ecs = @import("ecs.zig");
const reflect = @import("reflect.zig");
const systems = @import("systems.zig");
const params = @import("systems.params.zig");

/// Default system parameter registry including Query, Res, Local, EventReader, EventWriter, State, and NextState
pub const DefaultParamRegistry = SystemParamRegistry(&[_]type{
    params.StateSystemParam,
    params.NextStateSystemParam,
    params.EventReaderSystemParam,
    params.EventWriterSystemParam,
    params.ResourceSystemParam,
    params.SingleSystemParam,
    params.QuerySystemParam,
    params.LocalSystemParam,
    params.RelationsSystemParam,
    params.OnAddedSystemParam,
    params.OnRemovedSystemParam,
});

/// SystemParam registry for runtime-extensible parameter type analysis and instantiation
pub fn SystemParamRegistry(comptime RegisteredParams: []const type) type {
    inline for (RegisteredParams) |T| {
        comptime {
            if (!reflect.verifyFuncArgs(T, "analyze", &[_]type{type})) {
                @compileError("Each param must be a struct with 'analyze' functions: " ++ @typeName(T));
            }
            if (!reflect.verifyFuncArgs(T, "apply", &[_]type{ *ecs.Manager, type })) {
                @compileError("Each param must be a struct with 'apply' functions: " ++ @typeName(T));
            }
        }
    }
    return struct {
        pub const registered_params = RegisteredParams;

        pub fn len() usize {
            return registered_params.len;
        }

        pub fn contains(comptime ParamType: type) bool {
            inline for (registered_params) |SystemParam| {
                const result = SystemParam.analyze(ParamType);
                if (result) return true;
            }
            return false;
        }

        pub fn get(index: usize) type {
            return registered_params[index];
        }

        pub fn params() []const type {
            return registered_params;
        }

        fn analyze(comptime ParamType: type) ?type {
            inline for (registered_params) |SystemParam| {
                if (!reflect.verifyFuncArgs(SystemParam, "analyze", &[_]type{type})) {
                    @compileError("Each param must be a struct with 'analyze' functions: " ++ @typeName(SystemParam));
                }
                const result = SystemParam.analyze(ParamType);
                if (result) return result;
                //}
            }
            return null;
        }

        pub fn apply(ecs_instance: *ecs.Manager, comptime ParamType: type) ParamType {
            inline for (registered_params) |SystemParam| {
                const analyzed = SystemParam.analyze(ParamType);
                if (analyzed) |param| {
                    return SystemParam.apply(ecs_instance, param);
                }
            }
            @compileError(std.fmt.comptimePrint("No registered SystemParam can handle type: {s}", .{@typeName(ParamType)}));
        }

        pub fn deinit(ecs_instance: *ecs.Manager, ptr: *anyopaque, comptime ParamType: type) void {
            inline for (registered_params) |SystemParam| {
                const analyzed = SystemParam.analyze(ParamType);
                if (analyzed) |param| {
                    if (reflect.hasFuncWithArgs(SystemParam, "deinit", &[_]type{ *ecs.Manager, *anyopaque, type })) {
                        SystemParam.deinit(ecs_instance, ptr, param);
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
        pub fn analyze(comptime T: type) ?type {
            if (@typeInfo(T) == .int) return T;
            return null;
        }
        pub fn apply(_: *ecs.Manager, comptime T: type) T {
            return 1;
        }
    };
    const CustomRegistry = SystemParamRegistry(&[_]type{CustomParam});
    const merge = MergedSystemParamRegistry(.{ DefaultParamRegistry, CustomRegistry });
    try std.testing.expect(merge.len() == 12); // State, NextState, EventReader, EventWriter, Resource, Query, Local, Relations, OnAdded, OnRemoved, Single, CustomParam

    // Test that we can apply a custom param (returns value)
    const custom_val = merge.apply(&ecs_instance, i32);
    try std.testing.expect(custom_val == 1);

    // Test that we can apply a default registry param
    const value: f32 = 42.0;
    _ = try ecs_instance.addResource(f32, value);
    const res = merge.apply(&ecs_instance, params.Res(f32));
    try std.testing.expect(res.ptr.* == 42.0);
}

test "CustomSystemParam basic" {
    const allocator = std.testing.allocator;
    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const CustomParam = struct {
        pub fn analyze(comptime T: type) ?type {
            if (@typeInfo(T) == .int) return T;
            return null;
        }
        pub fn apply(_: *ecs.Manager, comptime T: type) T {
            return 123;
        }
    };
    const registry = SystemParamRegistry(&[_]type{CustomParam});
    const custom_val = registry.apply(&ecs_instance, i32);
    try std.testing.expect(custom_val == 123);
}

test "CustomSystemParam with Query, Res, Local fields" {
    const query = @import("query.zig");
    const allocator = std.testing.allocator;

    var ecs_instance = try ecs.Manager.init(allocator);
    defer ecs_instance.deinit();
    const res_val: i32 = 7;
    _ = try ecs_instance.addResource(i32, res_val);

    const TestComponentA = struct { a: i32 };
    const TestComponentB = struct { b: u32 };
    const QueryInclude = struct { a: TestComponentA, b: TestComponentB };
    const QueryExclude = struct {};
    const ComplexType = struct {
        query: query.Query(QueryInclude, QueryExclude),
        res: params.Res(i32),
        local: *params.Local(u64),
    };
    const CustomComplexParam = struct {
        pub fn analyze(comptime T: type) ?type {
            const ti = @typeInfo(T);
            if (ti == .@"struct" and @hasField(T, "query") and @hasField(T, "res") and @hasField(T, "local")) {
                return T;
            }
            return null;
        }
        pub fn apply(e: *ecs.Manager, comptime _: type) ComplexType {
            const query_val = params.QuerySystemParam.apply(e, query.Query(QueryInclude, QueryExclude));
            const res_value = params.ResourceSystemParam.apply(e, i32);
            const local_ptr = params.LocalSystemParam.apply(e, u64);
            return ComplexType{
                .query = query_val,
                .res = res_value,
                .local = local_ptr,
            };
        }
    };

    const registry = SystemParamRegistry(&[_]type{CustomComplexParam});
    const complex = registry.apply(&ecs_instance, ComplexType);
    try std.testing.expect(@intFromPtr(complex.query.storage) != 0);
    try std.testing.expect(complex.res.ptr.* == 7);
    try std.testing.expect(@intFromPtr(complex.local) != 0);
}
