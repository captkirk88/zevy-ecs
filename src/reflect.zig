const std = @import("std");

pub const FieldInfo = struct {
    name: []const u8,
    offset: usize,
    type: TypeInfo,

    pub fn from(comptime T: type, comptime field_name: []const u8) ?FieldInfo {
        const type_info = @typeInfo(T);
        const fields = blk: {
            if (type_info == .@"struct") break :blk type_info.@"struct".fields;
            if (type_info == .@"enum") break :blk type_info.@"enum".fields;
            if (type_info == .@"union") break :blk type_info.@"union".fields;
            return null;
        };
        for (fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return comptime FieldInfo{
                    .offset = @offsetOf(T, field.name),
                    .type = TypeInfo.from(field.type),
                };
            }
        }
        return null;
    }
};

pub const FuncInfo = struct {
    hash: u64,
    name: []const u8,
    params: []const ReflectInfo,
    return_type: ?ReflectInfo,

    /// Create FuncInfo from a function type
    fn from(comptime FuncType: type) ?FuncInfo {
        return comptime toFuncInfo(FuncType, &[_]ReflectInfo{});
    }

    /// Create FuncInfo for a method of a struct given the struct's TypeInfo and method name
    fn fromMethod(comptime type_info: *const TypeInfo, comptime func_name: []const u8) ?FuncInfo {
        const ti = @typeInfo(type_info.type);
        if (ti != .@"struct") {
            return null;
        }
        inline for (getDecls(ti)) |decl| {
            if (std.mem.eql(u8, decl.name, func_name)) {
                const fn_type_info = @typeInfo(@TypeOf(@field(type_info.type, decl.name)));
                if (fn_type_info != .@"fn") {
                    @compileError(std.fmt.comptimePrint(
                        "Declared member '{s}'' is not a function of type '{s}'",
                        .{ func_name, @typeName(type_info.type) },
                    ));
                }

                var param_infos: [fn_type_info.@"fn".params.len]ReflectInfo = undefined;
                var pi_i: usize = 0;
                inline for (fn_type_info.@"fn".params) |param| {
                    const p_t = param.type orelse void;
                    const p_ti = comptime TypeInfo.from(p_t);
                    param_infos[pi_i] = ReflectInfo{ .type = p_ti };
                    pi_i += 1;
                }

                const return_ref = if (fn_type_info.@"fn".return_type) |ret_type| ReflectInfo{ .type = comptime TypeInfo.from(ret_type) } else null;

                return FuncInfo{
                    .hash = std.hash.Wyhash.hash(0, std.fmt.comptimePrint(
                        "{s}{s}",
                        .{ @typeName(type_info.type), func_name },
                    )),
                    .name = decl.name,
                    .params = param_infos[0..pi_i],
                    .return_type = return_ref,
                };
            }
        }
        return null;
    }

    pub fn getParam(self: *const FuncInfo, index: usize) ?TypeInfo {
        if (index >= self.params.len) return null;
        return self.params[index];
    }

    pub fn paramsCount(self: *const FuncInfo) usize {
        return self.params.len;
    }

    /// Get a string representation of the function signature
    ///
    /// Must be called at comptime or runtime
    pub inline fn toString(self: *const FuncInfo) []const u8 {
        return comptime self.getStringRepresentation();
    }

    fn getStringRepresentation(self: *const FuncInfo) []const u8 {
        var params_str: []const u8 = "";
        var first: bool = true;
        inline for (self.params) |param| {
            switch (param) {
                .type => |ti| {
                    if (first) params_str = ti.name else params_str = std.fmt.comptimePrint("{s}, {s}", .{ params_str, ti.name });
                },
                .func => |fi| {
                    if (first) params_str = fi.name else params_str = std.fmt.comptimePrint("{s}, {s}", .{ params_str, fi.name });
                },
            }
            first = false;
        }
        const return_str = if (self.return_type) |ret| switch (ret) {
            .type => |ti| ti.name,
            .func => |fi| fi.name,
        } else "void";

        return std.fmt.comptimePrint("fn {s}({s}) -> {s}", .{ self.name, params_str, return_str });
    }

    pub fn eql(self: *const FuncInfo, other: *const FuncInfo) bool {
        if (!std.mem.eql(u8, self.name, other.name)) return false;
        if (self.params.len != other.params.len) return false;
        inline for (self.params, 0..) |param, i| {
            if (!param.eql(other.params[i])) return false;
        }
        if (self.return_type != other.return_type) return false;
        if (self.return_type) |ret| {
            if (!ret.eql(other.return_type.?)) return false;
        }
        return true;
    }

    // Helper for FuncInfo.from with cycle detection
    fn toFuncInfo(comptime FuncType: type, comptime visited: []const ReflectInfo) ?FuncInfo {
        inline for (visited) |info| {
            switch (info) {
                .func => |fi| {
                    if (std.mem.eql(u8, fi.name, @typeName(FuncType))) return fi;
                },
                else => {},
            }
        }

        var type_info = @typeInfo(FuncType);
        const hash = std.hash.Wyhash.hash(0, @typeName(FuncType));
        // create a stub ReflectInfo for this func so recursive references can find it
        const stub_reflect = ReflectInfo{ .func = FuncInfo{
            .hash = hash,
            .name = @typeName(FuncType),
            .params = &[_]ReflectInfo{},
            .return_type = null,
        } };
        const next_visited = visited ++ [_]ReflectInfo{stub_reflect};
        if (type_info == .optional) {
            type_info = @typeInfo(type_info.optional.child);
        }
        if (type_info != .@"fn") {
            @compileError(std.fmt.comptimePrint(
                "FuncInfo can only be created from function types: {s}",
                .{@typeName(FuncType)},
            ));
        }
        var param_infos: [type_info.@"fn".params.len]ReflectInfo = undefined;
        inline for (type_info.@"fn".params, 0..) |param, i| {
            const ti = @typeInfo(@TypeOf(param.type));
            const param_type = if (ti == .optional) param.type.? else param.type;
            if (comptime toReflectInfo(param_type, next_visited)) |info| {
                param_infos[i] = info;
            } else {
                @compileError(std.fmt.comptimePrint(
                    "FuncInfo parameter type not supported for reflection: {s}",
                    .{@typeName(param_type)},
                ));
            }
        }
        const return_type_info = if (type_info.@"fn".return_type) |ret_type| comptime toReflectInfo(ret_type, next_visited) else null;
        return FuncInfo{
            .hash = hash,
            .name = @typeName(FuncType),
            .params = param_infos[0..type_info.@"fn".params.len],
            .return_type = return_type_info,
        };
    }
};

pub const TypeInfo = struct {
    hash: u64,
    size: usize,
    type: type,
    name: []const u8,
    fields: []const FieldInfo,
    decls: []const ReflectInfo,
    funcs: []const FuncInfo,

    fn from(comptime T: type) TypeInfo {
        return comptime toTypeInfo(T, &[_]ReflectInfo{});
    }

    /// Helper for TypeInfo.from with cycle detection
    fn toTypeInfo(comptime T: type, comptime visited: []const ReflectInfo) TypeInfo {
        inline for (visited) |info| {
            switch (info) {
                .type => |ti| {
                    if (ti.hash == comptime std.hash.Wyhash.hash(0, @typeName(T))) return ti;
                },
                else => {},
            }
        }
        // create stub reflect for T and append to visited so recursive refs can find it
        const stub_reflect = ReflectInfo{ .type = TypeInfo{ .hash = std.hash.Wyhash.hash(0, @typeName(T)), .size = @sizeOf(T), .type = T, .name = @typeName(T), .fields = &[_]FieldInfo{}, .decls = &[_]ReflectInfo{}, .funcs = &[_]FuncInfo{} } };
        const next_visited = visited ++ [_]ReflectInfo{stub_reflect};
        const decls = TypeInfo.buildDecls(T, next_visited);
        var funcs: [16]FuncInfo = undefined; // reasonable limit
        var func_count: usize = 0;
        inline for (decls) |decl| {
            switch (decl) {
                .func => |fi| {
                    funcs[func_count] = fi;
                    func_count += 1;
                },
                else => {},
            }
        }
        const funcs_slice = funcs[0..func_count];
        var new_decls: [decls.len - func_count]ReflectInfo = undefined;
        var decl_count: usize = 0;
        inline for (decls) |decl| {
            switch (decl) {
                .type => |ti| {
                    new_decls[decl_count] = ReflectInfo{ .type = ti };
                    decl_count += 1;
                },
                else => {},
            }
        }
        return comptime TypeInfo{
            .hash = std.hash.Wyhash.hash(0, @typeName(T)),
            .size = @sizeOf(T),
            .type = T,
            .name = @typeName(T),
            .fields = TypeInfo.buildFields(T, next_visited),
            .decls = &new_decls,
            .funcs = funcs_slice,
        };
    }

    pub fn getField(self: *const TypeInfo, field_name: []const u8) ?FieldInfo {
        inline for (self.fields) |field| {
            if (std.mem.eql(u8, field.type.name, field_name)) {
                return field;
            }
        }
        return null;
    }

    pub fn getDecl(self: *const TypeInfo, decl_name: []const u8) ?TypeInfo {
        inline for (self.decls) |decl| {
            if (std.mem.eql(u8, decl.name, decl_name)) {
                return decl;
            }
        }
        return null;
    }

    pub fn getFunc(self: *const TypeInfo, func_name: []const u8) ?FuncInfo {
        inline for (self.funcs) |func| {
            if (std.mem.eql(u8, func.name, func_name)) {
                return func;
            }
        }
        return null;
    }

    pub inline fn toString(self: *const TypeInfo) []const u8 {
        return comptime self.getStringRepresentation();
    }

    fn getStringRepresentation(self: *const TypeInfo) []const u8 {
        return std.fmt.comptimePrint("TypeInfo{{ name {s}, size: {d}, hash: {x}, type: {s}}}", .{
            self.name,
            self.size,
            self.hash,
            @typeName(self.type),
        });
    }

    pub fn eql(self: *const TypeInfo, other: *const TypeInfo) bool {
        return self.hash == other.hash and self.size == other.size and std.mem.eql(u8, self.name, other.name);
    }

    fn buildFields(comptime T: type, comptime visited: []const ReflectInfo) []const FieldInfo {
        const type_info = @typeInfo(T);
        if (type_info != .@"struct") {
            return &[_]FieldInfo{};
        }
        const fields = blk: {
            if (type_info == .@"struct") break :blk type_info.@"struct".fields;
            if (type_info == .@"enum") break :blk type_info.@"enum".fields;
            if (type_info == .@"union") break :blk type_info.@"union".fields;
            @compileError("Type is not a struct, enum, or union");
        };
        var field_infos: [fields.len]FieldInfo = undefined;
        for (fields, 0..fields.len) |field, i| {
            field_infos[i] = FieldInfo{
                .name = field.name,
                .offset = @offsetOf(T, field.name),
                .type = TypeInfo.toTypeInfo(field.type, visited),
            };
        }
        return @constCast(field_infos[0..fields.len]);
    }

    fn buildDecls(comptime T: type, comptime visited: []const ReflectInfo) []const ReflectInfo {
        const type_info = @typeInfo(T);
        const decls = getDecls(type_info);
        if (decls.len == 0) {
            return &[_]ReflectInfo{};
        }
        var decl_type_infos: [decls.len]ReflectInfo = undefined;
        var i: usize = 0;
        inline for (decls) |decl| {
            const DeclType: type = @TypeOf(@field(T, decl.name));
            const decl_type_info = @typeInfo(DeclType);
            const maybe_info = toReflectInfo(DeclType, visited);
            if (maybe_info) |mi| {
                // If it's a function, ensure the stored name is the declaration identifier (e.g., method name)
                switch (mi) {
                    .func => |fi| {
                        var new_fi = fi;
                        new_fi.name = decl.name;
                        decl_type_infos[i] = ReflectInfo{ .func = new_fi };
                    },
                    .type => |ti| {
                        var new_ti = ti;
                        new_ti.name = decl.name;
                        decl_type_infos[i] = ReflectInfo{ .type = new_ti };
                    },
                }
            } else {
                // Insert stub ReflectInfo for cycles or unsupported types
                if (decl_type_info == .@"fn") {
                    // Build a FuncInfo from the function type and label it with the decl name
                    var func_info = FuncInfo.toFuncInfo(DeclType, visited) orelse FuncInfo{
                        .name = decl.name,
                        .params = &[_]ReflectInfo{},
                        .return_type = null,
                    };
                    func_info.name = decl.name;
                    decl_type_infos[i] = ReflectInfo{ .func = func_info };
                } else {
                    const decl_refl_info = toReflectInfo(DeclType, visited);
                    if (decl_refl_info) |dri| decl_type_infos[i] = dri else continue;
                }
            }
            i += 1;
        }
        return @constCast(decl_type_infos[0..i]);
    }
};

pub const ReflectInfo = union(enum) {
    type: TypeInfo,
    func: FuncInfo,

    /// Create ReflectInfo from any type with cycle detection
    pub fn from(comptime T: type) ?ReflectInfo {
        return toReflectInfo(T, &[_]ReflectInfo{});
    }

    fn fromInt(comptime type_info: std.builtin.Type) type {
        if (type_info == .bool) return bool;
        if (type_info == .int) {
            switch (type_info.int.signedness) {
                .signed => {
                    switch (type_info.int.bits) {
                        1 => return i1,
                        2 => return i2,
                        4 => return i4,
                        8 => return i8,
                        16 => return i16,
                        32 => return i32,
                        64 => return i64,
                        128 => return i128,
                        else => @compileError("Unsupported int bit size"),
                    }
                },
                .unsigned => {
                    switch (type_info.int.bits) {
                        1 => return u1,
                        2 => return u2,
                        4 => return u4,
                        8 => return u8,
                        16 => return u16,
                        32 => return u32,
                        64 => return u64,
                        128 => return u128,
                        else => @compileError("Unsupported int bit size"),
                    }
                },
            }
        }
        if (type_info == .comptime_int) {
            return comptime_int;
        }
        if (type_info == .float) {
            switch (type_info.float.bits) {
                16 => return f16,
                32 => return f32,
                64 => return f64,
                128 => return f128,
                else => @compileError("Unsupported float bit size"),
            }
        }
        if (type_info == .comptime_float) {
            return comptime_float;
        }
        @compileError("Type is not an bool, int, or float");
    }
};

fn toReflectInfo(comptime T: type, comptime visited: []const ReflectInfo) ?ReflectInfo {
    // If already visited, return the visited ReflectInfo
    inline for (visited) |info| {
        switch (info) {
            .type => |ti| {
                if (ti.hash == comptime std.hash.Wyhash.hash(0, @typeName(T))) return info;
            },
            .func => |fi| {
                if (fi.hash == comptime std.hash.Wyhash.hash(0, @typeName(T))) return info;
            },
        }
    }
    const type_info = @typeInfo(T);

    // pointer/optional/array/error_union and primitive wrappers just delegate
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return toReflectInfo(Child, visited);
    } else if (type_info == .optional) {
        const Child = type_info.optional.child;
        return toReflectInfo(Child, visited);
    } else if (type_info == .array or type_info == .vector) {
        const Child = blk: {
            if (type_info == .array) break :blk type_info.array.child;
            if (type_info == .vector) break :blk type_info.vector.child;
        };
        return toReflectInfo(Child, visited);
    } else if (type_info == .error_union) {
        const Child = type_info.error_union.error_set;
        return toReflectInfo(Child, visited);
    } else if (type_info == .bool or type_info == .int or type_info == .float) {
        const Child = blk: {
            if (type_info == .bool) break :blk bool;
            if (type_info == .int) break :blk ReflectInfo.fromInt(type_info);
            if (type_info == .float) break :blk ReflectInfo.fromInt(type_info);
        };
        return ReflectInfo{ .type = TypeInfo.toTypeInfo(Child, visited) };
    }

    // For functions, structs, enums, unions: create a stub ReflectInfo, append to visited,
    // then build the full info using that visited slice (so recursive refs resolve to the stub)
    if (type_info == .@"fn") {
        const fi = FuncInfo.toFuncInfo(T, visited) orelse return null;
        return ReflectInfo{ .func = fi };
    } else if (type_info == .@"struct" or type_info == .@"enum" or type_info == .@"union") {
        const ti = TypeInfo.toTypeInfo(T, visited);
        return ReflectInfo{ .type = ti };
    }

    return null;
}

pub fn getTypeInfo(comptime T: type) TypeInfo {
    return comptime TypeInfo.from(T);
}

pub fn getInfo(comptime T: type) ?ReflectInfo {
    return comptime ReflectInfo.from(T);
}

/// Check if a struct has a nested struct, enum, or union with the given name
///
/// Supports dot notation for nested structs (e.g., "Outer.Inner")
pub fn hasStruct(comptime T: type, struct_name: []const u8) bool {
    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return hasStruct(Child, struct_name);
    } else if (type_info == .@"struct" or type_info == .@"enum" or type_info == .@"union") {
        var search_name = struct_name;
        // Check if struct_name contains "."
        if (std.mem.indexOfScalar(u8, struct_name, '.')) |dot_index| {
            const first_part = struct_name[0..dot_index];
            search_name = struct_name[dot_index + 1 ..];
            // Find the decl with name first_part
            inline for (comptime getDecls(type_info)) |decl| {
                if (std.mem.eql(u8, decl.name, first_part)) {
                    const DeclType = @field(T, decl.name);
                    const decl_type_info = @typeInfo(DeclType);
                    if (decl_type_info == .@"struct" or decl_type_info == .@"enum" or decl_type_info == .@"union") {
                        return hasStruct(DeclType, search_name);
                    }
                }
            }
            return false;
        } else {
            // No dot, check direct
            inline for (comptime getDecls(type_info)) |decl| {
                if (std.mem.eql(u8, decl.name, struct_name)) {
                    const DeclType = @field(T, decl.name);
                    const decl_type_info = @typeInfo(DeclType);
                    if (decl_type_info == .@"struct" or decl_type_info == .@"enum" or decl_type_info == .@"union") {
                        return true;
                    }
                }
            }
            return false;
        }
    }
    return false;
}

fn getDecls(comptime type_info: std.builtin.Type) []const std.builtin.Type.Declaration {
    @setEvalBranchQuota(10_000);
    if (type_info == .pointer) return getDecls(@typeInfo(type_info.pointer.child));
    if (type_info == .@"struct") return type_info.@"struct".decls;
    if (type_info == .@"enum") return type_info.@"enum".decls;
    if (type_info == .@"union") return type_info.@"union".decls;
    if (type_info == .@"opaque") return type_info.@"opaque".decls;
    return &[_]std.builtin.Type.Declaration{};
}

pub fn hasFunc(comptime T: type, comptime func_name: []const u8) bool {
    return hasFuncWithArgs(T, func_name, null);
}

pub fn hasFuncWithArgs(comptime T: type, comptime func_name: []const u8, comptime arg_types: ?[]const type) bool {
    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return hasFuncWithArgs(Child, func_name, arg_types);
    } else if (type_info == .@"struct") {
        if (!@hasDecl(T, func_name)) return false;

        const fn_type = @typeInfo(@TypeOf(@field(T, func_name)));

        if (fn_type != .@"fn") return false;

        if (arg_types) |at| {
            // Check if first parameter is self (has type T)
            const has_self_param = fn_type.@"fn".params.len > 0 and fn_type.@"fn".params[0].type == T;

            // If it has self, skip it when checking arg_types; otherwise check all params
            const start_idx = if (has_self_param) 1 else 0;
            const expected_len = at.len + start_idx;

            if (fn_type.@"fn".params.len != expected_len) return false;

            inline for (0..at.len) |i| {
                if (fn_type.@"fn".params[start_idx + i].type != at[i]) {
                    return false;
                }
            }
            return true;
        } else {
            return true;
        }
    }
    return false;
}

/// Check if a struct has a field with the given name
///
/// The return is comptime-known
pub fn hasField(comptime T: type, field_name: []const u8) bool {
    const type_info = @typeInfo(T);
    const fields = blk: {
        if (type_info == .@"struct") break :blk type_info.@"struct".fields;
        if (type_info == .@"enum") break :blk type_info.@"enum".fields;
        if (type_info == .@"union") break :blk type_info.@"union".fields;
        if (type_info == .pointer) {
            const Child = type_info.pointer.child;
            return hasField(Child, field_name);
        }
        if (type_info == .optional) {
            const Child = type_info.optional.child;
            return hasField(Child, field_name);
        }
        return false;
    };
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return true;
        }
    }
    return false;
}

pub fn getField(comptime T: type, field_name: []const u8) ?type {
    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return getField(Child, field_name);
    }
    const fields = blk: {
        if (type_info == .@"struct") break :blk type_info.@"struct".fields;
        if (type_info == .@"enum") break :blk type_info.@"enum".fields;
        if (type_info == .@"union") break :blk type_info.@"union".fields;
        return false;
    };
    inline for (fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) {
            return @field(T, field.name);
        }
    }
    return null;
}

pub fn getFields(comptime T: type) []const []const u8 {
    return std.meta.fieldNames(T);
}

/// Check if a type is the Entity type
pub fn isEntity(comptime T: type) bool {
    // Entity is defined as a struct with id: u32 and generation: u32
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return false;

    const fields = type_info.@"struct".fields;
    if (fields.len != 2) return false;

    var has_id = false;
    var has_generation = false;

    for (fields) |field| {
        if (std.mem.eql(u8, field.name, "id") and field.type == u32) {
            has_id = true;
        } else if (std.mem.eql(u8, field.name, "generation") and field.type == u32) {
            has_generation = true;
        }
    }

    return has_id and has_generation;
}

/// Check if a struct has any Entity fields
pub fn hasEntityFields(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return false;

    inline for (type_info.@"struct".fields) |field| {
        if (isEntity(field.type)) {
            return true;
        }
    }

    return false;
}

/// Get indices of all Entity fields in a struct
pub fn getEntityFieldIndices(comptime T: type) []const usize {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return &[_]usize{};

    var indices: [16]usize = undefined; // Reasonable limit for entity fields
    var count: usize = 0;

    inline for (type_info.@"struct".fields, 0..) |field, i| {
        if (isEntity(field.type)) {
            indices[count] = i;
            count += 1;
        }
    }

    return @constCast(&indices[0..count]);
}

/// Field wrapper that tracks when it's modified
fn FieldChange(comptime T: type, comptime field_index: usize) type {
    return struct {
        _parent_bits: *u64,
        _value: T,

        const Self = @This();

        pub fn set(self: *Self, value: T) void {
            self._value = value;
            self._parent_bits.* |= (@as(u64, 1) << @intCast(field_index));
        }

        pub fn get(self: *const Self) T {
            return self._value;
        }

        pub fn getPtr(self: *Self) *T {
            self._parent_bits.* |= (@as(u64, 1) << @intCast(field_index));
            return &self._value;
        }
    };
}

/// Change tracking container for any struct type T
///
/// Tracks which fields have been modified using a bitset (no allocator needed).
/// Fields with names starting with `_` are ignored for change tracking.
///
/// Call commit() to mark that changes have occurred, reset() to clear flags
pub fn Change(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("Change() requires a struct type");
    }

    return struct {
        _data: T,
        _changed_bits: u64 = 0,

        const Self = @This();

        pub fn init(data: T) Self {
            return .{
                ._data = data,
            };
        }

        /// Get mutable access to the data
        pub fn get(self: *Self) *T {
            if (self.wasModified()) {
                @panic("Previous unmarked changes");
            }
            return &self._data;
        }

        /// Get const access to the data
        pub fn getConst(self: *const Self) *const T {
            if (self.wasModified()) {
                @panic("Previous unmarked changes");
            }
            return &self._data;
        }

        /// Mark that changes have occurred
        /// Call this after modifying data to indicate it has changed.
        pub fn mark(self: *Self) void {
            inline for (type_info.@"struct".fields, 0..) |field, i| {
                if (field.name.len > 0 and field.name[0] != '_') {
                    self._changed_bits |= (@as(u64, 1) << @intCast(i));
                }
            }
        }

        /// Check if changes have been committed since last reset
        pub fn isChanged(self: *const Self) bool {
            return self._changed_bits != 0;
        }

        /// Reset all change flags
        /// Call this when you're done processing the changes
        pub fn reset(self: *Self) void {
            self._changed_bits = 0;
        }

        /// Get direct access to data (same as get(), provided for clarity)
        pub fn getUnsafe(self: *Self) *T {
            return &self._data;
        }

        fn wasModified(self: *const Self) bool {
            var illegal_bits: u64 = 0;
            inline for (type_info.@"struct".fields, 0..) |field, i| {
                if (field.name.len > 0 and field.name[0] == '_') {
                    illegal_bits |= (@as(u64, 1) << @intCast(i));
                }
            }
            return (self._changed_bits & illegal_bits) != 0;
        }
    };
}

// ===== TESTS =====

test "hasFunc - struct with function" {
    const TestStruct = struct {
        value: i32,

        pub fn testMethod(self: @This()) i32 {
            return self.value;
        }
    };

    try std.testing.expect(comptime hasFunc(TestStruct, "testMethod"));
    try std.testing.expect(comptime !hasFunc(TestStruct, "nonExistentMethod"));
}

test "hasFunc - pointer to struct" {
    const TestStruct = struct {
        value: i32,

        pub fn testMethod(self: @This()) i32 {
            return self.value;
        }
    };

    try std.testing.expect(comptime hasFunc(*TestStruct, "testMethod"));
    try std.testing.expect(comptime !hasFunc(*TestStruct, "nonExistentMethod"));
}

test "hasFuncWithArgs - struct with function" {
    const TestStruct = struct {
        value: i32,

        pub fn add(self: @This(), other: i32) i32 {
            return self.value + other;
        }

        pub fn noArgs(self: @This()) i32 {
            return self.value;
        }
    };

    try std.testing.expect(comptime hasFuncWithArgs(TestStruct, "add", &[_]type{i32}));
    try std.testing.expect(comptime hasFuncWithArgs(TestStruct, "noArgs", &[_]type{}));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "add", &[_]type{})); // Wrong arg count
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "nonExistent", &[_]type{})); // Function doesn't exist
}

test "hasFuncWithArgs - funcs with self only (no additional args)" {
    const TestStruct = struct {
        value: i32,

        pub fn getValue(self: @This()) i32 {
            return self.value;
        }
    };

    // arg_types does NOT include self, so empty array means only self param
    try std.testing.expect(comptime hasFuncWithArgs(TestStruct, "getValue", &[_]type{}));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "getValue", &[_]type{i32}));
}

test "hasFuncWithArgs - funcs with self and one additional arg" {
    const TestStruct = struct {
        value: i32,

        pub fn add(self: @This(), other: i32) i32 {
            return self.value + other;
        }
    };

    // arg_types does NOT include self, only the additional args
    try std.testing.expect(comptime hasFuncWithArgs(TestStruct, "add", &[_]type{i32}));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "add", &[_]type{}));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "add", &[_]type{ i32, i32 }));
}

test "hasFuncWithArgs - funcs with self and multiple args" {
    const TestStruct = struct {
        value: i32,

        pub fn combine(self: @This(), a: i32, b: f32) i32 {
            return self.value + a + @as(i32, @intFromFloat(b));
        }
    };

    // arg_types does NOT include self
    try std.testing.expect(comptime hasFuncWithArgs(TestStruct, "combine", &[_]type{ i32, f32 }));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "combine", &[_]type{i32}));
    try std.testing.expect(comptime !hasFuncWithArgs(TestStruct, "combine", &[_]type{ i32, f32, i32 }));
}

test "hasField" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
    };

    const TestStructWithInner = struct {
        id: u32,
        pub const Inner = struct {
            value: i32,
        };
    };

    const TestStructNoFields = struct {};

    try std.testing.expect(hasField(TestStruct, "id"));
    try std.testing.expect(hasField(*TestStruct, "name"));
    try std.testing.expect(!hasField(TestStruct, "nonExistentField"));
    try std.testing.expect(!hasStruct(TestStruct, "Inner"));

    try std.testing.expect(comptime hasField(TestStruct, "id"));
    try std.testing.expect(comptime hasField(*TestStruct, "name"));
    try std.testing.expect(comptime !hasField(TestStruct, "nonExistentField"));
    try std.testing.expect(comptime !hasStruct(TestStruct, "Inner"));

    try std.testing.expect(hasStruct(TestStructWithInner, "Inner"));
    try std.testing.expect(hasStruct(*TestStructWithInner, "Inner"));
    try std.testing.expect(!hasField(TestStructNoFields, "any"));
    try std.testing.expect(!hasStruct(TestStructNoFields, "Inner"));
}

test "hasStruct" {
    const TestStruct = struct {
        id: u32,
        pub const Inner = struct {
            value: i32,
        };
    };

    const TestStructWithNested = struct {
        id: u32,
        pub const Nested = struct {
            pub const InnerNested = struct {
                data: f32,
            };
        };
    };

    const TestStructNoStructs = struct {
        id: u32,
        name: []const u8,
    };

    const TestEnum = enum {
        A,
        B,
        pub const InnerEnum = enum {
            X,
            Y,
        };
    };

    try std.testing.expect(hasStruct(TestStruct, "Inner"));
    try std.testing.expect(hasStruct(*TestStruct, "Inner"));
    try std.testing.expect(!hasStruct(TestStruct, "NonExistent"));

    try std.testing.expect(hasStruct(TestStructWithNested, "Nested"));
    try std.testing.expect(hasStruct(*TestStructWithNested, "Nested"));
    try std.testing.expect(hasStruct(TestStructWithNested, "Nested.InnerNested"));
    try std.testing.expect(!hasStruct(TestStructWithNested, "NonExistent"));

    try std.testing.expect(!hasStruct(TestStructNoStructs, "Inner"));
    try std.testing.expect(!hasStruct(*TestStructNoStructs, "Inner"));

    try std.testing.expect(hasStruct(TestEnum, "InnerEnum"));
}

test "getFields - returns all field names" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
        active: bool,
    };

    const fields = comptime getFields(TestStruct);
    try std.testing.expectEqual(@as(usize, 3), fields.len);

    // Check that all expected fields are present (order may vary)
    var found_id = false;
    var found_name = false;
    var found_active = false;

    for (fields) |field_name| {
        if (std.mem.eql(u8, field_name, "id")) found_id = true;
        if (std.mem.eql(u8, field_name, "name")) found_name = true;
        if (std.mem.eql(u8, field_name, "active")) found_active = true;
    }

    try std.testing.expect(found_id);
    try std.testing.expect(found_name);
    try std.testing.expect(found_active);
}

test "Change - initialization and basic operations" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
        active: bool,
    };

    const test_data = TestStruct{
        .id = 42,
        .name = "test",
        .active = true,
    };

    var change_tracker = Change(TestStruct).init(test_data);

    // Test direct access
    const data = change_tracker.getConst();
    try std.testing.expectEqual(@as(u32, 42), data.id);
    try std.testing.expectEqualStrings("test", data.name);
    try std.testing.expect(data.active);

    // Initially no changes
    try std.testing.expect(!change_tracker.isChanged());
}

test "Change - commit and reset workflow" {
    const TestStruct = struct {
        score: u32,
        level: u8,
        name: []const u8,
    };

    var change_tracker = Change(TestStruct).init(.{
        .score = 100,
        .level = 1,
        .name = "player",
    });

    // Modify data directly
    const data = change_tracker.get();
    data.score = 200;
    data.level = 5;

    // No changes tracked yet
    try std.testing.expect(!change_tracker.isChanged());

    // Commit to mark changes
    change_tracker.mark();

    // Now changes are tracked
    try std.testing.expect(change_tracker.isChanged());

    // Process the changes...
    try std.testing.expectEqual(@as(u32, 200), change_tracker.getConst().score);

    // Reset when done
    change_tracker.reset();
    try std.testing.expect(!change_tracker.isChanged());
}

test "Change - defer reset pattern" {
    const TestStruct = struct {
        x: i32,
        y: i32,
    };

    var change_tracker = Change(TestStruct).init(.{ .x = 10, .y = 20 });

    {
        defer change_tracker.reset();

        const data = change_tracker.get();
        data.x = 100;
        data.y = 200;

        change_tracker.mark();

        try std.testing.expect(change_tracker.isChanged());
        // Process changes here...
    }

    // After defer, changes are reset
    try std.testing.expect(!change_tracker.isChanged());
    // But data is preserved
    try std.testing.expectEqual(@as(i32, 100), change_tracker.getConst().x);
}

test "Change - natural field access" {
    const TestStruct = struct {
        score: u32,
        name: []const u8,
    };

    var change_tracker = Change(TestStruct).init(.{ .score = 0, .name = "hero" });

    // Natural field access
    const data = change_tracker.get();
    data.score = 30;
    data.name = "Hero";

    // Commit the changes
    change_tracker.mark();

    try std.testing.expect(change_tracker.isChanged());
    try std.testing.expectEqual(@as(u32, 30), data.score);

    // Reset
    change_tracker.reset();
    try std.testing.expect(!change_tracker.isChanged());
}

test "reflect - primitive type" {
    const info = getInfo(u32) orelse unreachable;
    switch (info) {
        .type => |ti| {
            try std.testing.expectEqualStrings(@typeName(u32), ti.name);
        },
        else => try std.testing.expect(false),
    }
}

test "reflect - struct fields" {
    const S = struct { a: u32, b: i32 };
    const info = getInfo(S) orelse unreachable;
    switch (info) {
        .type => |ti| {
            try std.testing.expectEqual(@as(usize, 2), ti.fields.len);
            try std.testing.expectEqualStrings(@typeName(u32), ti.fields[0].type.name);
            try std.testing.expectEqualStrings(@typeName(i32), ti.fields[1].type.name);
        },
        else => try std.testing.expect(false),
    }
}

// Recursive type reflection is covered indirectly by other tests; skip explicit recursive forward-decl here.

test "reflect - function type" {
    const FT = fn (i32) i32;
    const info = getInfo(FT) orelse unreachable;
    switch (info) {
        .func => |fi| {
            try std.testing.expectEqual(@as(usize, 1), fi.params.len);
            // param is a ReflectInfo; expect its type to be i32
            var saw = false;
            inline for (fi.params) |p| {
                switch (p) {
                    .type => |pti| {
                        try std.testing.expectEqualStrings(@typeName(i32), pti.name);
                        saw = true;
                    },
                    else => {},
                }
            }
            try std.testing.expect(saw);
        },
        else => try std.testing.expect(false),
    }
}

test "reflect - fromMethod and decls" {
    const S = struct {
        const Inner = struct { a: u32 };

        pub const I = Inner{ .a = 0 };
        pub fn add(x: i32) i32 {
            return x;
        }
        field: u8,
    };

    const ti = comptime TypeInfo.from(S);

    std.debug.print("TypeInfo: {s}\n", .{ti.name});
    std.debug.print("\tSize: {d}\n", .{ti.size});
    std.debug.print("\tHash: {x}\n", .{ti.hash});
    std.debug.print("\tFields:\n", .{});
    inline for (ti.fields) |field| {
        std.debug.print("\t- Name: {s} Offset: {d}, Type: {s}\n", .{ field.name, field.offset, field.type.name });
    }
    std.debug.print("\tDecls:\n", .{});
    inline for (ti.decls) |decl| {
        switch (decl) {
            .type => |dti| {
                std.debug.print("\t- {s}\n", .{dti.toString()});
            },
            else => {},
        }
    }
    std.debug.print("\tFuncs:\n", .{});
    inline for (ti.funcs) |func| {
        // debug: print raw stored name and its length so we can see what's present
        std.debug.print("\t- {s}\n", .{func.toString()});
    }

    // Ensure the method appears in the TypeInfo.funcs list
    try std.testing.expect(ti.getFunc("add") != null);

    const fi = FuncInfo.fromMethod(&ti, "add") orelse unreachable;
    try std.testing.expectEqualStrings("add", fi.name);
    try std.testing.expectEqual(@as(usize, 1), fi.params.len);

    var saw_param = false;
    inline for (fi.params) |p| {
        switch (p) {
            .type => |pti| {
                if (std.mem.eql(u8, pti.name, @typeName(i32))) saw_param = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_param);

    try std.testing.expect(fi.return_type != null);
    switch (fi.return_type.?) {
        .type => |rti| try std.testing.expectEqualStrings(@typeName(i32), rti.name),
        else => try std.testing.expect(false),
    }
}
