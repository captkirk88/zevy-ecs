const std = @import("std");
const builtin = @import("builtin");
const archetype_storage = @import("archetype_storage.zig");
const archetype_mod = @import("archetype.zig");
const Entity = @import("ecs.zig").Entity;
const reflect = @import("zevy_reflect");

const MarkerKind = enum { none, with, without };
const ResultKind = enum { entity, component };
const ConstraintKind = enum { require, exclude };

const FilterConstraint = struct {
    kind: ConstraintKind,
    component_type: type,
};

const ResultFieldMeta = struct {
    source_name: [:0]const u8,
    result_name: []const u8,
    component_type: type,
    kind: ResultKind,
    is_optional: bool,
    result_index: usize,
};

const ENTITY_SENTINEL: usize = std.math.maxInt(usize) - 1;
const MISSING_COMPONENT_SENTINEL: usize = std.math.maxInt(usize);

/// Marker type for a query that matches only entities that have the given component
/// types. Use `With(T)` in a query spec to indicate that only entities that have
/// component `T` should be included in the query results.
pub fn With(comptime Types: anytype) type {
    return struct {
        pub const QueryMarker = MarkerKind.with;
        pub const Payload = Types;
    };
}

/// Marker type for a query that excludes the given component types from matching
/// entities. Use `Without(T)` in a query spec to indicate that entities with
/// component `T` should be excluded from the query results.
pub fn Without(comptime Types: anytype) type {
    return struct {
        pub const QueryMarker = MarkerKind.without;
        pub const Payload = Types;
    };
}

fn normalizeQuerySpecType(comptime Spec: anytype) type {
    return if (@TypeOf(Spec) == type) Spec else @TypeOf(Spec);
}

/// Check if a type is optional (?T) and return the child type if so.
fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

/// Extract the child type from an optional type (?T -> T).
fn optionalChildType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .optional) {
        return info.optional.child;
    }
    return T;
}

/// Get the actual component type, unwrapping optionals.
pub fn getComponentType(comptime T: type) type {
    return optionalChildType(T);
}

fn typeCanHaveDecls(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => true,
        else => false,
    };
}

fn markerLabel(comptime kind: MarkerKind) []const u8 {
    return switch (kind) {
        .with => "With",
        .without => "Without",
        .none => "",
    };
}

fn queryMarkerKindNonOptional(comptime T: type) MarkerKind {
    if (!typeCanHaveDecls(T) or !@hasDecl(T, "QueryMarker")) {
        return .none;
    }
    const marker = @field(T, "QueryMarker");
    if (@TypeOf(marker) != MarkerKind) {
        @compileError("Query marker '" ++ @typeName(T) ++ "' has an invalid QueryMarker declaration.");
    }
    return marker;
}

fn queryMarkerKind(comptime T: type) MarkerKind {
    if (isOptionalType(T)) {
        const child = optionalChildType(T);
        const child_marker = queryMarkerKindNonOptional(child);
        if (child_marker != .none) {
            @compileError("Query markers cannot be optional. Use " ++ markerLabel(child_marker) ++ "(...) directly.");
        }
        return .none;
    }
    return queryMarkerKindNonOptional(T);
}

fn markerPayloadCount(comptime Payload: anytype) usize {
    if (@TypeOf(Payload) == type) {
        return 1;
    }

    const payload_info = @typeInfo(@TypeOf(Payload));
    if (payload_info != .@"struct" or !payload_info.@"struct".is_tuple) {
        @compileError("Query markers accept either a single type or a tuple of types.");
    }

    comptime var count: usize = 0;
    inline for (payload_info.@"struct".fields) |field| {
        const entry = @field(Payload, field.name);
        if (@TypeOf(entry) != type) {
            @compileError("Query marker payload tuples must contain types only.");
        }
        count += 1;
    }
    return count;
}

fn markerPayloadTypeAt(comptime Payload: anytype, comptime index: usize) type {
    if (@TypeOf(Payload) == type) {
        if (index != 0) unreachable;
        return Payload;
    }

    const payload_info = @typeInfo(@TypeOf(Payload));
    if (payload_info != .@"struct" or !payload_info.@"struct".is_tuple) {
        @compileError("Query markers accept either a single type or a tuple of types.");
    }

    inline for (payload_info.@"struct".fields, 0..) |field, payload_index| {
        if (payload_index == index) {
            const entry = @field(Payload, field.name);
            if (@TypeOf(entry) != type) {
                @compileError("Query marker payload tuples must contain types only.");
            }
            return entry;
        }
    }

    unreachable;
}

fn validateMarkerPayloadType(comptime kind: MarkerKind, comptime ComponentType: type) void {
    if (queryMarkerKind(ComponentType) != .none) {
        @compileError(markerLabel(kind) ++ " payloads cannot contain nested query markers.");
    }
    if (ComponentType == Entity) {
        @compileError(markerLabel(kind) ++ " cannot reference Entity.");
    }
    if (isOptionalType(ComponentType)) {
        @compileError(markerLabel(kind) ++ " payloads must contain component value types, not optional types.");
    }
    if (@typeInfo(ComponentType) == .pointer) {
        @compileError(markerLabel(kind) ++ " payloads must contain component value types, not pointers.");
    }
}

fn validateRegularField(comptime field_name: []const u8, comptime DeclaredType: type) void {
    if (@typeInfo(DeclaredType) == .pointer) {
        @compileError(std.fmt.comptimePrint("Query field '{s}' must use a component value type, not {s}", .{ field_name, @typeName(DeclaredType) }));
    }

    if (isOptionalType(DeclaredType)) {
        const child = optionalChildType(DeclaredType);
        if (@typeInfo(child) == .pointer) {
            @compileError(std.fmt.comptimePrint("Query field '{s}' must use ?Component, not ?{s}", .{ field_name, @typeName(child) }));
        }
        if (child == Entity) {
            @compileError("Query field '" ++ field_name ++ "' cannot be ?Entity. Entity is always available when requested and should never be optional.");
        }
    }
}

fn queryFieldDeclaredType(comptime IncludeTypes: anytype, comptime field: anytype) type {
    return if (field.type == type) @field(IncludeTypes, field.name) else field.type;
}

fn debugPayloadString(comptime Payload: anytype) []const u8 {
    if (@TypeOf(Payload) == type) {
        return @typeName(Payload);
    }

    const payload_count = markerPayloadCount(Payload);
    comptime var out: []const u8 = ".{";
    inline for (0..payload_count) |payload_index| {
        if (payload_index > 0) out = out ++ ", ";
        out = out ++ @typeName(markerPayloadTypeAt(Payload, payload_index));
    }
    return out ++ "}";
}

fn debugFieldString(comptime DeclaredType: type) []const u8 {
    return switch (queryMarkerKind(DeclaredType)) {
        .none => @typeName(DeclaredType),
        .with => "With(" ++ debugPayloadString(DeclaredType.Payload) ++ ")",
        .without => "Without(" ++ debugPayloadString(DeclaredType.Payload) ++ ")",
    };
}

fn debugQueryString(comptime IncludeTypes: anytype) []const u8 {
    const include_type = normalizeQuerySpecType(IncludeTypes);
    const include_info = @typeInfo(include_type);
    comptime if (include_info != .@"struct") @compileError("IncludeTypes must be a struct or tuple");

    comptime var include_str: []const u8 = "";
    inline for (include_info.@"struct".fields, 0..) |field, i| {
        const declared_type = queryFieldDeclaredType(IncludeTypes, field);
        if (i > 0) include_str = include_str ++ ", ";
        include_str = include_str ++ debugFieldString(declared_type);
    }

    return "Query({" ++ include_str ++ "})";
}

fn validateConstraints(comptime constraints: anytype) void {
    inline for (constraints, 0..) |lhs, i| {
        inline for (constraints[i + 1 ..]) |rhs| {
            if (lhs.component_type == rhs.component_type) {
                if (lhs.kind == rhs.kind) {
                    @compileError("Duplicate query constraint for component '" ++ @typeName(lhs.component_type) ++ "'.");
                }
                @compileError("Contradictory query constraints for component '" ++ @typeName(lhs.component_type) ++ "'.");
            }
        }
    }
}

fn resultFieldOutputType(comptime field: ResultFieldMeta) type {
    if (field.kind == .entity) {
        return Entity;
    }
    if (field.is_optional) {
        return ?*field.component_type;
    }
    return *field.component_type;
}

fn buildResultType(comptime is_tuple: bool, comptime result_fields: anytype) type {
    const len = result_fields.len;
    var field_types: [len]type = undefined;
    var field_names: [len][:0]const u8 = undefined;
    var field_attrs: [len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (result_fields, 0..) |field, i| {
        const field_type = resultFieldOutputType(field);
        field_types[i] = field_type;
        if (!is_tuple) {
            field_names[i] = field.source_name;
            field_attrs[i] = .{
                .@"comptime" = false,
                .@"align" = @alignOf(field_type),
                .default_value_ptr = null,
            };
        }
    }

    if (is_tuple) {
        return @Tuple(&field_types);
    }

    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
}

fn buildQueryMeta(comptime IncludeTypes: anytype) type {
    const include_type = normalizeQuerySpecType(IncludeTypes);
    const include_info = @typeInfo(include_type);
    comptime if (include_info != .@"struct") @compileError("IncludeTypes must be a struct or tuple");

    const fields = include_info.@"struct".fields;

    comptime var result_field_count: usize = 0;
    comptime var constraint_total: usize = 0;

    inline for (fields) |field| {
        const declared_type = queryFieldDeclaredType(IncludeTypes, field);
        const marker_kind = queryMarkerKind(declared_type);
        switch (marker_kind) {
            .none => {
                validateRegularField(field.name, declared_type);
                const component_type = getComponentType(declared_type);
                result_field_count += 1;
                if (!isOptionalType(declared_type) and component_type != Entity) {
                    constraint_total += 1;
                }
            },
            .with, .without => {
                const payload_count = markerPayloadCount(declared_type.Payload);
                if (payload_count == 0) {
                    @compileError(markerLabel(marker_kind) ++ " requires at least one component type.");
                }
                inline for (0..payload_count) |payload_index| {
                    validateMarkerPayloadType(marker_kind, markerPayloadTypeAt(declared_type.Payload, payload_index));
                }
                constraint_total += payload_count;
            },
        }
    }

    var result_fields_buf: [result_field_count]ResultFieldMeta = undefined;
    var constraints_buf: [constraint_total]FilterConstraint = undefined;
    comptime var result_index: usize = 0;
    comptime var constraint_index: usize = 0;

    inline for (fields) |field| {
        const declared_type = queryFieldDeclaredType(IncludeTypes, field);
        const marker_kind = queryMarkerKind(declared_type);

        switch (marker_kind) {
            .none => {
                const component_type = getComponentType(declared_type);
                const is_optional = isOptionalType(declared_type);
                result_fields_buf[result_index] = .{
                    .source_name = field.name,
                    .result_name = if (include_info.@"struct".is_tuple) std.fmt.comptimePrint("{d}", .{result_index}) else field.name,
                    .component_type = component_type,
                    .kind = if (component_type == Entity) .entity else .component,
                    .is_optional = is_optional,
                    .result_index = result_index,
                };
                result_index += 1;

                if (!is_optional and component_type != Entity) {
                    constraints_buf[constraint_index] = .{ .kind = .require, .component_type = component_type };
                    constraint_index += 1;
                }
            },
            .with, .without => {
                const payload_count = markerPayloadCount(declared_type.Payload);
                inline for (0..payload_count) |payload_index| {
                    constraints_buf[constraint_index] = .{
                        .kind = if (marker_kind == .with) .require else .exclude,
                        .component_type = markerPayloadTypeAt(declared_type.Payload, payload_index),
                    };
                    constraint_index += 1;
                }
            },
        }
    }

    validateConstraints(constraints_buf[0..]);

    const ResultTupleType = buildResultType(include_info.@"struct".is_tuple, result_fields_buf[0..]);
    const result_count_value = result_field_count;
    const constraint_count_value = constraint_total;
    const result_fields_value = result_fields_buf;
    const constraints_value = constraints_buf;
    return struct {
        pub const IncludeType = include_type;
        pub const IncludeInfo = include_info;
        pub const ResultType = ResultTupleType;
        pub const result_count = result_count_value;
        pub const constraint_count = constraint_count_value;
        pub const result_fields = result_fields_value;
        pub const constraints = constraints_value;
    };
}

fn signatureContainsComponent(signature: archetype_mod.ArchetypeSignature, comptime ComponentType: type) bool {
    const type_hash = comptime reflect.getReflectInfo(ComponentType).hash();
    for (signature.types) |hash| {
        if (hash == type_hash) {
            return true;
        }
    }
    return false;
}

fn archetypeComponentIndex(arch: *archetype_mod.Archetype, comptime ComponentType: type) usize {
    const type_hash = comptime reflect.getReflectInfo(ComponentType).hash();
    for (arch.signature.types, 0..) |hash, index| {
        if (hash == type_hash) {
            return index;
        }
    }
    return MISSING_COMPONENT_SENTINEL;
}

fn componentPointer(arch: *archetype_mod.Archetype, entity_index: usize, component_index: usize, comptime ComponentType: type) *ComponentType {
    const offset = entity_index * arch.component_sizes[component_index];
    const arr = arch.component_arrays[component_index];
    const slice = arr.items[offset .. offset + @sizeOf(ComponentType)];
    return @as(*ComponentType, @ptrCast(@alignCast(slice.ptr)));
}

pub fn Query(comptime IncludeTypes: anytype) type {
    const Meta = buildQueryMeta(IncludeTypes);

    return struct {
        storage: *archetype_storage.ArchetypeStorage,
        guard: archetype_storage.ArchetypeStorage.ReadGuard,
        arch_iter: std.HashMap(archetype_mod.ArchetypeSignature, *archetype_mod.Archetype, archetype_storage.Context, 80).Iterator,
        entity_index: usize,
        current_archetype: ?*archetype_mod.Archetype,
        component_indices: [Meta.result_count]usize,
        last_entity: ?Entity,
        guard_released: bool,
        shared_guard_released: ?*bool,

        pub const debugInfo = if (builtin.mode == .Debug) struct {
            pub fn get() []const u8 {
                return debugQueryString(IncludeTypes);
            }
        }.get else void;

        pub const IncludeTypesParam = IncludeTypes;
        pub const IncludeTypesTupleType = Meta.ResultType;

        /// Initialize the query, acquiring a read guard on the archetype storage and
        /// preparing the iterator over matching archetypes.
        pub fn init(storage: *archetype_storage.ArchetypeStorage) @This() {
            var guard = storage.readGuard();
            var self = @This(){
                .storage = storage,
                .guard = guard,
                .arch_iter = guard.get().archetypes.iterator(),
                .entity_index = 0,
                .current_archetype = null,
                .component_indices = undefined,
                .last_entity = null,
                .guard_released = false,
                .shared_guard_released = null,
            };
            self.advanceToNextMatchingArchetype();
            return self;
        }

        /// Share the deinitialization state of this query with an external boolean flag so that
        /// the external owner can track whether the read guard has already been released
        /// and avoid double-releasing it.
        pub fn shareDeinitState(self: *@This(), shared_state: *bool) void {
            shared_state.* = self.guard_released;
            self.shared_guard_released = shared_state;
        }

        /// Deinitialize the query, releasing the read guard on the archetype storage
        /// if it has not already been released via `isGuardReleased()` / `shareDeinitState()`.
        pub fn deinit(self: *@This()) void {
            if (!self.isGuardReleased()) {
                self.guard.deinit();
                self.setGuardReleased(true);
            }
        }

        fn isGuardReleased(self: *const @This()) bool {
            if (self.shared_guard_released) |shared_state| {
                return shared_state.*;
            }
            return self.guard_released;
        }

        fn setGuardReleased(self: *@This(), released: bool) void {
            self.guard_released = released;
            if (self.shared_guard_released) |shared_state| {
                shared_state.* = released;
            }
        }

        /// Get the current entity in the iteration.
        /// Can only be called after calling next() and getting a non-null result.
        pub fn entity(self: *const @This()) Entity {
            if (self.last_entity) |last_yielded_entity| {
                return last_yielded_entity;
            }
            @panic("Query.entity() called when no archetype is available. Ensure next() returned a non-null result before calling entity() or check with hasNext().");
        }

        /// Returns true if the query has no matching entities.
        pub fn hasNext(self: *const @This()) bool {
            if (self.current_archetype) |arch| {
                if (self.entity_index < arch.entities.items.len) {
                    return true;
                }
            }

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
            inline for (Meta.constraints) |constraint| {
                const has_component = signatureContainsComponent(signature, constraint.component_type);
                switch (constraint.kind) {
                    .require => if (!has_component) return false,
                    .exclude => if (has_component) return false,
                }
            }
            return true;
        }

        fn computeComponentIndices(self: *@This()) void {
            if (self.current_archetype) |arch| {
                inline for (Meta.result_fields) |field| {
                    self.component_indices[field.result_index] = switch (field.kind) {
                        .entity => ENTITY_SENTINEL,
                        .component => archetypeComponentIndex(arch, field.component_type),
                    };
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
            self.last_entity = null;
        }

        pub fn next(self: *const @This()) ?IncludeTypesTupleType {
            const mutable_self = @constCast(self);
            while (mutable_self.current_archetype) |arch| {
                if (mutable_self.entity_index < arch.entities.items.len) {
                    mutable_self.last_entity = arch.entities.items[mutable_self.entity_index];
                    var result: IncludeTypesTupleType = undefined;

                    inline for (Meta.result_fields) |field| {
                        const component_index = mutable_self.component_indices[field.result_index];
                        switch (field.kind) {
                            .entity => {
                                if (component_index != ENTITY_SENTINEL) {
                                    @panic("Entity query fields must use the entity sentinel index.");
                                }
                                @field(result, field.result_name) = arch.entities.items[mutable_self.entity_index];
                            },
                            .component => {
                                if (component_index == MISSING_COMPONENT_SENTINEL) {
                                    if (field.is_optional) {
                                        @field(result, field.result_name) = null;
                                    } else {
                                        @panic("Required query component '" ++ field.source_name ++ "' was missing from a matched archetype.");
                                    }
                                } else {
                                    const ptr = componentPointer(arch, mutable_self.entity_index, component_index, field.component_type);
                                    @field(result, field.result_name) = ptr;
                                }
                            },
                        }
                    }

                    mutable_self.entity_index += 1;
                    return result;
                }
                mutable_self.advanceToNextMatchingArchetype();
            }
            mutable_self.last_entity = null;
            return null;
        }
    };
}
