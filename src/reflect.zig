const std = @import("std");

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
