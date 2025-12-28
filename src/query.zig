const std = @import("std");
const builtin = @import("builtin");
const archetype_storage = @import("archetype_storage.zig");
const archetype_mod = @import("archetype.zig");
const Entity = @import("ecs.zig").Entity;
const reflect = @import("zevy_reflect");

/// Check if a type is optional (?T) and return the child type if so
fn isOptionalType(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .optional;
}

/// Extract the child type from an optional type (?T -> T)
fn optionalChildType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .optional) {
        return info.optional.child;
    }
    return T;
}

/// Get the actual component type, unwrapping optionals
pub fn getComponentType(comptime T: type) type {
    return optionalChildType(T);
}

/// Check if a component type is required (not optional)
fn isRequiredComponent(comptime T: type) bool {
    return !isOptionalType(T);
}

const ENTITY_SENTINEL: usize = std.math.maxInt(usize) - 1;
const MISSING_COMPONENT_SENTINEL: usize = std.math.maxInt(usize);

pub fn Query(comptime IncludeTypes: anytype, comptime ExcludeTypes: anytype) type {
    const include_type = if (@typeInfo(@TypeOf(IncludeTypes)) == .type) IncludeTypes else @TypeOf(IncludeTypes);
    const include_info = @typeInfo(include_type);
    const exclude_type = if (@typeInfo(@TypeOf(ExcludeTypes)) == .type) ExcludeTypes else @TypeOf(ExcludeTypes);
    const exclude_info = @typeInfo(exclude_type);
    comptime {
        if (include_info != .@"struct")
            @compileError("IncludeTypes must be a struct or tuple");
        if (exclude_info != .@"struct")
            @compileError("ExcludeTypes must be a struct or tuple");
    }

    return struct {
        storage: *archetype_storage.ArchetypeStorage,
        arch_iter: std.HashMap(archetype_mod.ArchetypeSignature, *archetype_mod.Archetype, archetype_storage.Context, 80).Iterator,
        entity_index: usize,
        current_archetype: ?*archetype_mod.Archetype,
        component_indices: [include_info.@"struct".fields.len]usize,

        /// Returns a debug string representation of the Query type (only in Debug builds)
        pub const debugInfo = if (builtin.mode == .Debug) struct {
            pub fn get() []const u8 {
                // Build include types string by iterating through fields
                comptime var include_str: []const u8 = "";
                inline for (include_info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
                    if (i > 0) include_str = include_str ++ ", ";
                    include_str = include_str ++ @typeName(component_type);
                }

                // Build exclude types string by iterating through fields
                comptime var exclude_str: []const u8 = "";
                inline for (exclude_info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    const component_type = if (T == type) @field(ExcludeTypes, field.name) else getComponentType(T);
                    if (i > 0) exclude_str = exclude_str ++ ", ";
                    exclude_str = exclude_str ++ @typeName(component_type);
                }

                return "Query({" ++ include_str ++ "}, {" ++ exclude_str ++ "})";
            }
        }.get else void;

        pub const IncludeTypesParam = IncludeTypes;
        pub const ExcludeTypesParam = ExcludeTypes;
        pub const IncludeTypesTupleType = ret: {
            const is_tuple = include_info.@"struct".is_tuple;
            const fields = blk: {
                var f: [include_info.@"struct".fields.len]std.builtin.Type.StructField = undefined;
                for (include_info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    // Handle case where T is 'type' itself (when passing tuples like .{Position})
                    // In this case, we need to extract the actual type from IncludeTypes
                    const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
                    var field_type: type = undefined;
                    // Determine field type based on whether it's optional or not
                    if (isOptionalType(T) and T != type) {
                        if (component_type == Entity) {
                            @compileError("Query field '" ++ field.name ++ "' cannot be ?Entity. Entity is always available in query results and should never be optional.");
                        } else {
                            field_type = ?*component_type;
                        }
                    } else if (@typeInfo(T) == .pointer) {
                        @compileError(std.fmt.comptimePrint("Query includes/excludes must be value types {s}", @typeName(T)));
                    } else {
                        if (component_type == Entity) {
                            field_type = Entity;
                        } else {
                            field_type = *component_type;
                        }
                    }
                    f[i] = std.builtin.Type.StructField{
                        .name = field.name,
                        .type = field_type,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf(field_type),
                    };
                }
                break :blk f;
            };
            break :ret @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = is_tuple,
            } });
        };
        const IncludesEntity = includesEntity(IncludeTypes);

        pub fn init(storage: *archetype_storage.ArchetypeStorage) @This() {
            var self = @This(){
                .storage = storage,
                .arch_iter = storage.archetypes.iterator(),
                .entity_index = 0,
                .current_archetype = null,
                .component_indices = undefined,
            };
            self.advanceToNextMatchingArchetype();
            return self;
        }

        /// Get the current entity in the iteration
        /// Can only be called after calling next() and getting a non-null result
        pub fn entity(self: *const @This()) Entity {
            if (self.current_archetype) |arch| {
                return arch.entities.items[self.entity_index];
            }
            @panic("Query.entity() called when no archetype is available. Ensure next() returned a non-null result before calling entity() or check with hasNext().");
        }

        /// Returns true if the query has no matching entities
        pub fn hasNext(self: *const @This()) bool {
            // If we have a current archetype with entities remaining, not empty
            if (self.current_archetype) |arch| {
                if (self.entity_index < arch.entities.items.len) {
                    return true;
                }
            }
            // Check if there are any more matching archetypes with entities
            // We need to peek ahead without modifying state, so we iterate a copy
            var temp_iter = self.arch_iter;
            while (temp_iter.next()) |entry| {
                const arch = entry.value_ptr.*;
                if (@constCast(self).archetypeMatches(arch.signature) and arch.entities.items.len > 0) {
                    return true;
                }
            }
            return false;
        }

        fn archetypeMatches(_: *@This(), signature: archetype_mod.ArchetypeSignature) bool {
            // Check all required include types are present
            inline for (include_info.@"struct".fields) |field| {
                const T = field.type;
                // When T == type, we need to get the actual type from IncludeTypes
                const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
                const is_required = if (T == type) true else isRequiredComponent(T);
                if (is_required) {
                    // Skip Entity since it's not stored as a component in archetypes
                    if (component_type != Entity) {
                        const incl_comp_hash = comptime reflect.getReflectInfo(component_type).hash();
                        var found = false;
                        for (signature.types) |h| {
                            if (h == incl_comp_hash) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            return false;
                        }
                    }
                }
            }
            // Check none of the exclude types are present
            inline for (exclude_info.@"struct".fields) |field| {
                const T = field.type;
                const excl_comp_hash = comptime reflect.getReflectInfo(getComponentType(T)).hash();
                for (signature.types) |h| {
                    if (h == excl_comp_hash) {
                        return false;
                    }
                }
            }
            return true;
        }

        fn computeComponentIndices(self: *@This()) void {
            if (self.current_archetype) |arch| {
                inline for (include_info.@"struct".fields, 0..) |field, original_i| {
                    const T = field.type;
                    const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
                    if (component_type == Entity) {
                        self.component_indices[original_i] = ENTITY_SENTINEL;
                        continue;
                    }
                    const type_hash = comptime reflect.getReflectInfo(component_type).hash();
                    var found = false;
                    for (arch.signature.types, 0..) |h, j| {
                        if (h == type_hash) {
                            self.component_indices[original_i] = j;
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        self.component_indices[original_i] = MISSING_COMPONENT_SENTINEL;
                    }
                }
            }
        }

        fn advanceToNextMatchingArchetype(self: *@This()) void {
            while (self.arch_iter.next()) |entry| {
                const arch = entry.value_ptr.*;
                if (self.archetypeMatches(arch.signature)) {
                    self.current_archetype = arch;
                    self.entity_index = 0;
                    self.computeComponentIndices();
                    return;
                }
            }
            self.current_archetype = null;
        }

        pub fn next(self: *const @This()) ?IncludeTypesTupleType {
            // Need to get mutable self for iteration
            const mutable_self = @constCast(self);
            while (mutable_self.current_archetype) |arch| {
                if (mutable_self.entity_index < arch.entities.items.len) {
                    var result: IncludeTypesTupleType = undefined;
                    inline for (include_info.@"struct".fields, 0..) |field, original_i| {
                        const j = mutable_self.component_indices[original_i];
                        const T = field.type;
                        const component_type = comptime if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);

                        // Branch on component type at comptime to avoid type mismatches
                        if (comptime component_type == Entity) {
                            // This field is for Entity
                            if (j != ENTITY_SENTINEL) {
                                @panic("Entity field '" ++ field.name ++ "' does not have ENTITY_SENTINEL index. Expected Entity to always map to ENTITY_SENTINEL sentinel value.");
                            }
                            @field(result, field.name) = arch.entities.items[mutable_self.entity_index];
                        } else {
                            // This field is for a component
                            if (j == MISSING_COMPONENT_SENTINEL) {
                                const is_optional = comptime if (T == type) false else isOptionalType(T);
                                if (comptime is_optional) {
                                    @field(result, field.name) = null;
                                } else {
                                    @panic("Required component field '" ++ field.name ++ "' of type '" ++ @typeName(T) ++ "' is NOT included in Query's IncludeTypes. All non-optional fields in the result struct must be included in the Query's component set. Ensure '" ++ @typeName(component_type) ++ "' is in your Query specification.");
                                }
                            } else {
                                // Only assign pointer if struct field type is a pointer or optional pointer
                                switch (@typeInfo(@TypeOf(result))) {
                                    .@"struct" => |struct_info| {
                                        const struct_field_type = struct_info.fields[original_i].type;
                                        switch (@typeInfo(struct_field_type)) {
                                            .pointer => {
                                                const offset = mutable_self.entity_index * arch.component_sizes[j];
                                                const arr = arch.component_arrays[j];
                                                const slice = arr.items[offset .. offset + @sizeOf(component_type)];
                                                const ptr = @as(*component_type, @ptrCast(@alignCast(slice.ptr)));
                                                @field(result, field.name) = ptr;
                                            },
                                            .optional => |opt_info| {
                                                // Handle optional pointer types like ?*Component
                                                if (@typeInfo(opt_info.child) == .pointer) {
                                                    const offset = mutable_self.entity_index * arch.component_sizes[j];
                                                    const arr = arch.component_arrays[j];
                                                    const slice = arr.items[offset .. offset + @sizeOf(component_type)];
                                                    const ptr = @as(*component_type, @ptrCast(@alignCast(slice.ptr)));
                                                    @field(result, field.name) = ptr;
                                                } else {
                                                    @panic("Field '" ++ field.name ++ "' is optional but the child type must be a pointer (*Component). Got ?" ++ @typeName(opt_info.child) ++ " but expected ?*<Component>. Optional fields must be of form ?*T where T is a component.");
                                                }
                                            },
                                            else => {
                                                @panic("Field '" ++ field.name ++ "' has type '" ++ @typeName(struct_field_type) ++ "' but component fields in Query results must be pointers (*T) or optional pointers (?*T). Query stores components as byte arrays and returns pointers to them.");
                                            },
                                        }
                                    },
                                    else => {
                                        @panic("Query result type '" ++ @typeName(@TypeOf(result)) ++ "' must be a struct or tuple type. All Query results must be passed as struct or tuple types.");
                                    },
                                }
                            }
                        }
                    }
                    mutable_self.entity_index += 1;
                    return result;
                }
                mutable_self.advanceToNextMatchingArchetype();
            }
            return null;
        }
    };
}

/// Check if Entity is explicitly included in IncludeTypes
fn includesEntity(comptime IncludeTypes: anytype) bool {
    const include_info = @typeInfo(@TypeOf(IncludeTypes));
    inline for (include_info.@"struct".fields) |field| {
        const T = field.type;
        const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
        if (component_type == Entity) {
            return true;
        }
    }
    return false;
}
