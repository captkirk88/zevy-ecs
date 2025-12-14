const std = @import("std");
const reflect = @import("zevy_reflect");

/// Check if a type is the Entity type
pub fn isEntity(comptime T: type) bool {
    // Entity is defined as a struct with id: u32 and generation: u32
    const type_info = reflect.getTypeInfo(T);
    if (type_info.category != .Struct) return false;

    const fields = type_info.fields;
    if (fields.len != 2) return false;

    const has_id = type_info.getField("id") != null;
    const has_generation = type_info.getField("generation") != null;

    return has_id and has_generation;
}

/// Check if a struct has any Entity fields
pub fn hasEntityFields(comptime T: type) bool {
    const type_info = reflect.getTypeInfo(T);
    if (type_info.category != .Struct) return false;

    inline for (type_info.fields) |field| {
        if (isEntity(field.type.type)) {
            return true;
        }
    }

    return false;
}

/// Get indices of all Entity fields in a struct
pub fn getEntityFieldIndices(comptime T: type) []const usize {
    const type_info = reflect.getTypeInfo(T);
    if (type_info.category != .Struct) return &[_]usize{};

    var indices: [16]usize = undefined; // Reasonable limit for entity fields
    var count: usize = 0;

    inline for (type_info.fields, 0..) |field, i| {
        if (isEntity(field.type.type)) {
            indices[count] = i;
            count += 1;
        }
    }

    return @constCast(&indices[0..count]);
}
