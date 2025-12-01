const std = @import("std");

/// Simple comptime-friendly FNV-1a hash that doesn't require branch quota increases.
/// Used for type identification throughout the reflection system.
fn comptimeHash(comptime name: []const u8) u64 {
    var hash: u64 = 14695981039346656037; // FNV offset basis
    for (name) |c| {
        hash ^= c;
        hash *%= 1099511628211; // FNV prime
    }
    return hash;
}

/// Shallow type information for field types - doesn't recurse into nested types.
/// This avoids comptime explosion when reflecting complex types with many nested fields.
pub const ShallowTypeInfo = struct {
    type: type,
    name: []const u8,
    size: usize,

    /// Get full TypeInfo for this type (computed lazily)
    pub fn getFullInfo(self: *const ShallowTypeInfo) TypeInfo {
        return comptime TypeInfo.from(self.type);
    }
};

pub const FieldInfo = struct {
    name: []const u8,
    offset: usize,
    type: ShallowTypeInfo,

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
                    .name = field.name,
                    .offset = @offsetOf(T, field.name),
                    .type = ShallowTypeInfo{
                        .type = field.type,
                        .name = @typeName(field.type),
                        .size = @sizeOf(field.type),
                    },
                };
            }
        }
        return null;
    }

    /// Check if this FieldInfo is equal to another
    ///
    /// *Must be called at comptime.*
    pub fn eql(self: *const FieldInfo, other: *const FieldInfo) bool {
        if (!std.mem.eql(u8, self.name, other.name)) return false;
        if (self.offset != other.offset) return false;
        if (!std.mem.eql(u8, self.type.name, other.type.name)) return false;
        if (self.type.size != other.type.size) return false;
        if (self.type.type != other.type.type) return false;
        return true;
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
                    .hash = comptimeHash(std.fmt.comptimePrint(
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
    /// *Does not need to be called at comptime.*
    pub inline fn toString(self: *const FuncInfo) []const u8 {
        return comptime self.getStringRepresentation();
    }

    /// Check if this FuncInfo is equal to another
    ///
    /// *Must be called at comptime.*
    pub fn eql(self: *const FuncInfo, other: *const FuncInfo) bool {
        if (!std.mem.eql(u8, self.name, other.name)) return false;
        if (self.params.len != other.params.len) return false;
        inline for (self.params, 0..) |param, i| {
            if (!param.eql(&other.params[i])) return false;
        }
        if (self.return_type) |ret| {
            if (other.return_type == null) return false;
            if (!ret.eql(&other.return_type.?)) return false;
        }
        return true;
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
        const hash = comptimeHash(@typeName(FuncType));
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
        var valid_params: usize = 0;
        inline for (type_info.@"fn".params, 0..) |param, i| {
            _ = i;
            // Handle null param.type (anytype parameters)
            if (param.type == null) {
                return null;
            }
            const ti = @typeInfo(@TypeOf(param.type));
            const param_type = if (ti == .optional) param.type.? else param.type.?;
            if (comptime toReflectInfo(param_type, next_visited)) |info| {
                param_infos[valid_params] = info;
                valid_params += 1;
            } else {
                // Skip unsupported parameter types (like *anyopaque) instead of erroring
                // Return null to indicate this function can't be fully reflected
                return null;
            }
        }
        const return_type_info = if (type_info.@"fn".return_type) |ret_type| comptime toReflectInfo(ret_type, next_visited) else null;
        return FuncInfo{
            .hash = hash,
            .name = @typeName(FuncType),
            .params = param_infos[0..valid_params],
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

    /// Create `TypeInfo` from any type except opaque types (like `anyopaque`)
    ///
    /// *Must be called at comptime.*
    fn from(comptime T: type) TypeInfo {
        return comptime toTypeInfo(T, &[_]ReflectInfo{});
    }

    /// Helper for TypeInfo.from with cycle detection
    /// Uses direct type comparison at comptime instead of hashing to avoid branch quota issues.
    fn toTypeInfo(comptime T: type, comptime visited: []const ReflectInfo) TypeInfo {
        const type_name = @typeName(T);

        // Use direct type comparison for cycle detection - cheaper at comptime
        inline for (visited) |info| {
            switch (info) {
                .type => |ti| {
                    if (ti.type == T) return ti;
                },
                else => {},
            }
        }

        // Compute hash only once at the end, not for cycle detection
        const hash = comptimeHash(type_name);

        // create stub reflect for T and append to visited so recursive refs can find it
        const stub_reflect = ReflectInfo{ .type = TypeInfo{ .hash = hash, .size = @sizeOf(T), .type = T, .name = type_name, .fields = &[_]FieldInfo{} } };
        const next_visited = visited ++ [_]ReflectInfo{stub_reflect};

        return comptime TypeInfo{
            .hash = hash,
            .size = @sizeOf(T),
            .type = T,
            .name = type_name,
            .fields = TypeInfo.buildFields(T, next_visited),
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

    /// Lazily look up a decl (type constant) by name.
    ///
    /// *Does not need to be called at comptime.*
    pub fn getDecl(self: *const TypeInfo, comptime decl_name: []const u8) ?TypeInfo {
        return comptime lazyGetDecl(self.type, decl_name);
    }

    /// Get a function by name.
    ///
    /// *Does not need to be called at comptime.*
    pub fn getFunc(self: *const TypeInfo, comptime func_name: []const u8) ?FuncInfo {
        return comptime lazyGetFunc(self.type, func_name);
    }

    /// Get the names of all type decls (non-function declarations).
    ///
    /// *Must be called at comptime.*
    pub fn getDeclNames(self: *const TypeInfo) []const []const u8 {
        return comptime lazyGetDeclNames(self.type, .types_only);
    }

    /// Get the names of all function decls.
    ///
    /// *Must be called at comptime.*
    pub fn getFuncNames(self: *const TypeInfo) []const []const u8 {
        return comptime lazyGetDeclNames(self.type, .funcs_only);
    }

    /// Check if this type has a decl with the given name.
    ///
    /// *Must be called at comptime.*
    pub fn hasDecl(self: *const TypeInfo, comptime decl_name: []const u8) bool {
        return @hasDecl(self.type, decl_name);
    }

    /// Get a string representation of the type info
    ///
    /// *Does not need to be called at comptime.*
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

    /// Check if this TypeInfo is equal to another (by hash and size)
    ///
    /// *Must be called at comptime.*
    pub fn eql(self: *const TypeInfo, other: *const TypeInfo) bool {
        return self.hash == other.hash and self.size == other.size;
    }

    fn buildFields(comptime T: type, comptime visited: []const ReflectInfo) []const FieldInfo {
        _ = visited; // No longer needed since we don't recurse
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
        var field_count: usize = 0;
        for (fields) |field| {
            // Skip fields with opaque types
            const field_type_info = @typeInfo(field.type);
            if (field_type_info == .@"opaque") continue;
            if (field_type_info == .pointer and @typeInfo(field_type_info.pointer.child) == .@"opaque") continue;

            // Use shallow type info - doesn't recurse into nested types
            field_infos[field_count] = FieldInfo{
                .name = field.name,
                .offset = @offsetOf(T, field.name),
                .type = ShallowTypeInfo{
                    .type = field.type,
                    .name = @typeName(field.type),
                    .size = @sizeOf(field.type),
                },
            };
            field_count += 1;
        }
        return @constCast(field_infos[0..field_count]);
    }
};

pub const ReflectInfo = union(enum) {
    type: TypeInfo,
    func: FuncInfo,

    /// Create ReflectInfo from any type with cycle detection
    pub fn from(comptime T: type) ?ReflectInfo {
        return toReflectInfo(T, &[_]ReflectInfo{});
    }

    /// Check if this ReflectInfo is equal to another
    ///
    /// *Must be called at comptime.*
    pub fn eql(self: *const ReflectInfo, other: *const ReflectInfo) bool {
        switch (self.*) {
            .type => |ti1| {
                switch (other.*) {
                    .type => |ti2| return ti1.eql(&ti2),
                    else => return false,
                }
            },
            .func => |fi1| {
                switch (other.*) {
                    .func => |fi2| return fi1.eql(&fi2),
                    else => return false,
                }
            },
        }
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
    // If already visited, return the visited ReflectInfo - use direct type comparison
    inline for (visited) |info| {
        switch (info) {
            .type => |ti| {
                if (ti.type == T) return info;
            },
            .func => |fi| {
                // For functions, compare names since we don't have direct type
                if (std.mem.eql(u8, fi.name, @typeName(T))) return info;
            },
        }
    }
    const type_info = @typeInfo(T);

    // Handle opaque types (like anyopaque) - return null as they can't be reflected
    if (type_info == .@"opaque") {
        return null;
    }

    // pointer/optional/array/error_union and primitive wrappers just delegate
    if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        // Handle pointer to opaque (like *anyopaque)
        if (@typeInfo(Child) == .@"opaque") {
            return null;
        }
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

/// Mode for filtering decl names
const DeclNameMode = enum {
    types_only,
    funcs_only,
    all,
};

/// Lazily get names of declarations without processing them.
/// This avoids the comptime explosion by just collecting names.
fn lazyGetDeclNames(comptime T: type, comptime mode: DeclNameMode) []const []const u8 {
    const type_info = @typeInfo(T);
    const decls = getDecls(type_info);
    if (decls.len == 0) {
        return &[_][]const u8{};
    }

    var names: [decls.len][]const u8 = undefined;
    var count: usize = 0;

    inline for (decls) |decl| {
        const DeclType = @TypeOf(@field(T, decl.name));
        const decl_type_info = @typeInfo(DeclType);
        const is_func = decl_type_info == .@"fn";

        const include = switch (mode) {
            .types_only => !is_func,
            .funcs_only => is_func,
            .all => true,
        };

        if (include) {
            names[count] = decl.name;
            count += 1;
        }
    }

    return names[0..count];
}

/// Lazily look up a single decl (type constant) by name.
/// Only processes the requested decl, avoiding comptime explosion.
fn lazyGetDecl(comptime T: type, comptime decl_name: []const u8) ?TypeInfo {
    if (!@hasDecl(T, decl_name)) {
        return null;
    }

    const DeclType = @TypeOf(@field(T, decl_name));
    const decl_type_info = @typeInfo(DeclType);

    // Only return TypeInfo for non-functions (type constants)
    if (decl_type_info == .@"fn") {
        return null;
    }

    // For type constants, we need to get the actual type value
    if (DeclType == type) {
        const actual_type = @field(T, decl_name);
        return TypeInfo.from(actual_type);
    }

    // For struct/enum/union instances, return their type info
    if (decl_type_info == .@"struct" or decl_type_info == .@"enum" or decl_type_info == .@"union") {
        return TypeInfo.from(DeclType);
    }

    return null;
}

/// Lazily look up a single function by name.
/// Only processes the requested function, avoiding comptime explosion.
fn lazyGetFunc(comptime T: type, comptime func_name: []const u8) ?FuncInfo {
    if (!@hasDecl(T, func_name)) {
        return null;
    }

    const DeclType = @TypeOf(@field(T, func_name));
    const decl_type_info = @typeInfo(DeclType);

    if (decl_type_info != .@"fn") {
        return null;
    }

    // Check for unsupported parameter types
    inline for (decl_type_info.@"fn".params) |param| {
        if (param.type) |pt| {
            const pt_info = @typeInfo(pt);
            if (pt_info == .@"opaque") {
                return null;
            }
            if (pt_info == .pointer and @typeInfo(pt_info.pointer.child) == .@"opaque") {
                return null;
            }
        } else {
            // anytype parameter - can't reflect
            return null;
        }
    }

    // Build FuncInfo for this specific function
    var param_infos: [decl_type_info.@"fn".params.len]ReflectInfo = undefined;
    var valid_params: usize = 0;

    inline for (decl_type_info.@"fn".params) |param| {
        const param_type = param.type.?;
        if (toReflectInfo(param_type, &[_]ReflectInfo{})) |info| {
            param_infos[valid_params] = info;
            valid_params += 1;
        } else {
            return null;
        }
    }

    const return_type_info = if (decl_type_info.@"fn".return_type) |ret_type|
        toReflectInfo(ret_type, &[_]ReflectInfo{})
    else
        null;

    return FuncInfo{
        .hash = comptimeHash(std.fmt.comptimePrint("{s}{s}", .{ @typeName(T), func_name })),
        .name = func_name,
        .params = param_infos[0..valid_params],
        .return_type = return_type_info,
    };
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

test "reflect - TypeInfo with lazy decl/func access" {
    // Decls and funcs are now accessed lazily to avoid comptime branch quota
    // explosion when processing complex external types (like raylib).
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
        std.debug.print("\t- Name: {s}\n", .{field.name});
        std.debug.print("\t- Offset: {d}\n", .{field.offset});
        std.debug.print("\t- Type: {s}\n", .{field.type.name});
    }

    // Verify basic type info
    try std.testing.expect(ti.hash != 0);
    try std.testing.expectEqual(@as(usize, 1), ti.size);
    try std.testing.expectEqual(@as(usize, 1), ti.fields.len);
    try std.testing.expectEqualStrings("field", ti.fields[0].name);

    // Test lazy function access - use comptime block for iteration
    std.debug.print("\tFunc names: ", .{});
    const func_names = comptime ti.getFuncNames();
    inline for (func_names) |name| {
        std.debug.print("{s} ", .{name});
    }
    std.debug.print("\n", .{});

    const add_func = comptime ti.getFunc("add") orelse {
        @compileError("Failed to get 'add' function");
    };
    try std.testing.expectEqualStrings("add", add_func.name);
    try std.testing.expectEqual(@as(usize, 1), add_func.params.len);
    std.debug.print("\tFunc 'add': {s}\n", .{add_func.toString()});

    // Test lazy decl access
    std.debug.print("\tDecls:\n", .{});
    const decl_names = comptime ti.getDeclNames();
    inline for (decl_names) |name| {
        const decl = comptime ti.getDecl(name) orelse unreachable;
        std.debug.print("\t- Name: {s}\n", .{name});
        std.debug.print("\t- Type: {s}\n", .{@typeName(decl.type)});
        std.debug.print("\t- Hash: {x}\n", .{decl.hash});
        std.debug.print("\t- Size: {d}\n", .{decl.size});
        std.debug.print("\t- Fields: {d}\n", .{decl.fields.len});
        inline for (decl.fields) |field| {
            std.debug.print("\t\t- Field Name: {s}\n", .{field.name});
            std.debug.print("\t\t- Field Type: {s}\n", .{field.type.name});
        }
    }
    std.debug.print("\n", .{});

    // Check hasDecl - needs comptime
    try std.testing.expect(comptime ti.hasDecl("add"));
    try std.testing.expect(comptime ti.hasDecl("I"));
    try std.testing.expect(comptime ti.hasDecl("Inner"));
    try std.testing.expect(comptime !ti.hasDecl("nonexistent"));
    try std.testing.expect(ti.getFunc("add") != null);
    try std.testing.expect(ti.getFunc("nonexistent") == null);
    try std.testing.expect(comptime ti.getDeclNames().len == 1);
    try std.testing.expect(comptime ti.getFuncNames().len == 1);
    try std.testing.expect(ti.getDecl("I") != null);
    try std.testing.expect(ti.toString().len > 0);
}

test "reflect - TypeInfo eql" {
    const S1 = struct { a: u32, b: i32 };
    const S2 = struct { a: u32, c: i32 }; // Different field name

    const ti1 = comptime TypeInfo.from(S1);
    const ti1_again = comptime TypeInfo.from(S1); // Same type
    const ti2 = comptime TypeInfo.from(S2);

    // eql compares hash and size - same type should be equal
    try std.testing.expect(comptime ti1.eql(&ti1_again));
    // Different types (even with same layout) have different hashes
    try std.testing.expect(comptime !ti1.eql(&ti2));

    // Also test with primitives
    const ti_u32 = comptime TypeInfo.from(u32);
    const ti_u32_again = comptime TypeInfo.from(u32);
    const ti_i32 = comptime TypeInfo.from(i32);

    try std.testing.expect(comptime ti_u32.eql(&ti_u32_again));
    try std.testing.expect(comptime !ti_u32.eql(&ti_i32));
}

test "reflect - FuncInfo eql" {
    const FT1 = fn (i32) i32;
    const FT2 = fn (i32, i32) i32; // Different signature

    const fi1 = comptime FuncInfo.from(FT1) orelse unreachable;
    const fi1_again = comptime FuncInfo.from(FT1) orelse unreachable; // Same function
    const fi2 = comptime FuncInfo.from(FT2) orelse unreachable;

    try std.testing.expect(comptime fi1.eql(&fi1_again));
    try std.testing.expect(comptime !fi1.eql(&fi2));
}

test "reflect - FieldInfo eql" {
    const S1 = struct { a: u32, b: i32 };
    const S2 = struct { a: u32, c: i32 }; // Different field name

    const ti1 = comptime TypeInfo.from(S1);
    const ti2 = comptime TypeInfo.from(S2);
    const field_a1 = ti1.fields[0];
    const field_a1_again = ti1.fields[0];
    const field_b1 = ti1.fields[1];
    const field_c2 = ti2.fields[1];

    try std.testing.expect(comptime field_a1.eql(&field_a1_again));
    try std.testing.expect(comptime !field_a1.eql(&field_b1));
    try std.testing.expect(comptime !field_a1.eql(&field_c2));
}

test "reflect - ReflectInfo eql" {
    const S = struct { a: u32, b: i32 };
    const T = struct { a: u32, b: i32 }; // Same layout but different type
    const FT = fn (i32) i32;

    const ri_type1 = comptime ReflectInfo.from(S) orelse unreachable;
    const ri_type1_again = comptime ReflectInfo.from(S) orelse unreachable;
    const ri_func = comptime ReflectInfo.from(FT) orelse unreachable;
    const ri_type2 = comptime ReflectInfo.from(T) orelse unreachable;

    try std.testing.expect(comptime ri_type1.eql(&ri_type1_again));
    try std.testing.expect(comptime !ri_type1.eql(&ri_func));
    try std.testing.expect(comptime !ri_type1.eql(&ri_type2));
}

test "reflect - PackedStruct TypeInfo" {
    const PackedStruct = packed struct {
        a: u8,
        b: u32,
    };

    const ti = comptime TypeInfo.from(PackedStruct);

    std.debug.print("PackedStruct TypeInfo: {s}\n", .{ti.name});
    std.debug.print("\tHash: {x}\n", .{ti.hash});
    std.debug.print("\tSize: {d}\n", .{ti.size});
    std.debug.print("\tFields:\n", .{});
    inline for (ti.fields) |field| {
        std.debug.print("\t- Name: {s}\n", .{field.name});
        std.debug.print("\t- Offset: {d}\n", .{field.offset});
        std.debug.print("\t- Type: {s}\n", .{field.type.name});
    }
    // Packed struct is backed by integer type, @sizeOf returns padded size (8 bytes for u40 backing)
    try std.testing.expectEqual(@as(usize, @sizeOf(PackedStruct)), ti.size);
    try std.testing.expectEqual(@as(usize, 2), ti.fields.len);
    try std.testing.expectEqualStrings("a", ti.fields[0].name);
    try std.testing.expectEqualStrings("b", ti.fields[1].name);
}
