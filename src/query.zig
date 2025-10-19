const std = @import("std");
const archetype_storage = @import("archetype_storage.zig");
const archetype_mod = @import("archetype.zig");
const Entity = @import("ecs.zig").Entity;
const reflect = @import("reflect.zig");

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
        pub const IncludeTypesParam = IncludeTypes;
        pub const ExcludeTypesParam = ExcludeTypes;
        pub const IncludeTypesTupleType = blk: {
            const is_tuple = include_info.@"struct".is_tuple;
            const fields = blk2: {
                var f: [include_info.@"struct".fields.len]std.builtin.Type.StructField = undefined;
                for (include_info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    // Handle case where T is 'type' itself (when passing tuples like .{Position})
                    // In this case, we need to extract the actual type from IncludeTypes
                    const component_type = if (T == type) @field(IncludeTypes, field.name) else getComponentType(T);
                    var field_type: type = undefined;
                    // if (T == type) {
                    //     // Bare type in tuple/struct - return pointer to component
                    //     if (component_type == Entity) {
                    //         field_type = Entity;
                    //     } else {
                    //         field_type = *component_type;
                    //     }
                    // }
                    if (isOptionalType(T) and T != type) {
                        if (component_type == Entity) {
                            field_type = ?Entity;
                        } else {
                            field_type = ?*component_type;
                        }
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
                break :blk2 f;
            };
            break :blk @Type(.{ .@"struct" = .{
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
                        const type_info = reflect.getTypeInfo(component_type);
                        var found = false;
                        for (signature.types) |h| {
                            if (h == type_info.hash) {
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
                const type_info = reflect.getTypeInfo(getComponentType(T));
                for (signature.types) |h| {
                    if (h == type_info.hash) {
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
                    const type_hash = reflect.getTypeInfo(component_type).hash;
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
                                @panic("Entity field does not have ENTITY_SENTINEL index");
                            }
                            @field(result, field.name) = arch.entities.items[mutable_self.entity_index];
                        } else {
                            // This field is for a component
                            if (j == MISSING_COMPONENT_SENTINEL) {
                                const is_optional = comptime if (T == type) false else isOptionalType(T);
                                if (comptime is_optional) {
                                    @field(result, field.name) = null;
                                } else {
                                    @panic("Required component not found in archetype: " ++ @typeName(T));
                                }
                            } else if (j == ENTITY_SENTINEL) {
                                @panic("Component field has ENTITY_SENTINEL: " ++ @typeName(component_type));
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
                                                    @panic("Optional component field in struct is not a pointer type: " ++ @typeName(opt_info.child));
                                                }
                                            },
                                            else => {
                                                @panic("Component field in struct is not a pointer type: " ++ @typeName(struct_field_type));
                                            },
                                        }
                                    },
                                    else => @panic("Struct type is not a struct: " ++ @typeName(@TypeOf(result))),
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
