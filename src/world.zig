const std = @import("std");
const errors = @import("errors.zig");
const ArchetypeStorage = @import("archetype_storage.zig").ArchetypeStorage;
const Entity = @import("ecs.zig").Entity;
const Query = @import("query.zig").Query;
const reflect = @import("reflect.zig");

/// Represents a component instance with its type information and data
///
/// Example:
/// ```zig
/// const pos = Position{ .x = 10.0, .y = 20.0 };
/// const comp_instance = ComponentInstance.from(Position, &pos);
/// ```
///
/// Write Example:
/// ```zig
/// var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
/// defer buffer.deinit(allocator);
/// var writer = std.io.fixedBufferWriter(&buffer);
/// try comp_instance.writeTo(&writer);
/// ```
/// Read Example:
/// ```zig
/// var reader = std.io.fixedBufferReader(buffer.items);
/// const read_comp = try ComponentInstance.readFrom(&reader, allocator);
/// ```
pub const ComponentInstance = struct {
    hash: u64,
    size: usize,
    data: []const u8,

    pub fn from(comptime T: type, value: *const T) ComponentInstance {
        const info = comptime reflect.getTypeInfo(T);
        return ComponentInstance{
            .hash = info.hash,
            .size = info.size,
            .data = std.mem.asBytes(value),
        };
    }

    /// Get the component data as a specific type T
    /// Returns null if the type hash doesn't match
    pub fn as(self: ComponentInstance, comptime T: type) ?*const T {
        const expected_info = reflect.getTypeInfo(T);
        if (self.hash == expected_info.hash and self.size == expected_info.size) {
            return @alignCast(std.mem.bytesAsValue(T, self.data[0..self.size]));
        }

        return null;
    }

    /// Get the component data as a mutable specific type T
    /// Returns null if the type hash doesn't match
    /// Note: This is unsafe as it allows mutation of the original data
    pub fn asMut(self: ComponentInstance, comptime T: type) ?*T {
        const expected_info = reflect.getTypeInfo(T);
        if (self.hash == expected_info.hash and self.size == expected_info.size) {
            return @alignCast(std.mem.bytesAsValue(T, @constCast(self.data[0..self.size])));
        }
        return null;
    }

    /// Write this component to any std.io.Writer
    pub fn writeTo(self: ComponentInstance, writer: std.io.AnyWriter) !void {
        try writer.writeInt(u64, self.hash, .little);
        try writer.writeInt(usize, self.size, .little);
        try writer.writeAll(self.data);
    }

    /// Create a ComponentInstance from any std.io.Reader
    /// The caller is responsible for freeing the returned data
    pub fn readFrom(reader: std.io.AnyReader, allocator: std.mem.Allocator) !ComponentInstance {
        const comp_hash = try reader.readInt(u64, .little);
        const comp_size = try reader.readInt(usize, .little);
        const comp_data = try allocator.alloc(u8, comp_size);
        _ = try reader.readAll(comp_data);
        return ComponentInstance{
            .hash = comp_hash,
            .size = comp_size,
            .data = comp_data,
        };
    }
};

/// ComponentWriter for writing multiple components to a stream
pub const ComponentWriter = struct {
    writer: std.io.AnyWriter,

    pub fn init(writer: std.io.AnyWriter) ComponentWriter {
        return ComponentWriter{ .writer = writer };
    }

    /// Write a single component to the stream
    pub fn writeComponent(self: *ComponentWriter, component: ComponentInstance) !void {
        try component.writeTo(self.writer);
    }

    /// Write multiple components to the stream with a count header
    pub fn writeComponents(self: *ComponentWriter, components: []const ComponentInstance) !void {
        try self.writer.writeInt(usize, components.len, .little);
        for (components) |component| {
            try self.writeComponent(component);
        }
    }

    /// Write a component of type T with value
    pub fn writeTypedComponent(self: *ComponentWriter, comptime T: type, value: *const T) !void {
        const info = reflect.getTypeInfo(T);
        const bytes = std.mem.asBytes(value);
        const component = ComponentInstance{
            .hash = info.hash,
            .size = info.size,
            .data = bytes,
        };
        try self.writeComponent(component);
    }
};

/// ComponentReader for reading components from a stream
pub const ComponentReader = struct {
    reader: std.io.AnyReader,
    allocator: std.mem.Allocator,

    pub fn init(reader: std.io.AnyReader, allocator: std.mem.Allocator) ComponentReader {
        return ComponentReader{ .reader = reader, .allocator = allocator };
    }

    /// Read a single component from the stream
    /// The caller is responsible for freeing the component data
    pub fn readComponent(self: *ComponentReader) !ComponentInstance {
        return ComponentInstance.readFrom(self.reader, self.allocator);
    }

    /// Read multiple components from the stream, expecting a count header
    /// The caller is responsible for freeing the returned array and component data
    pub fn readComponents(self: *ComponentReader) ![]ComponentInstance {
        const count = try self.reader.readInt(usize, .little);
        const components = try self.allocator.alloc(ComponentInstance, count);
        for (components, 0..) |_, i| {
            components[i] = try self.readComponent();
        }
        return components;
    }

    /// Free component data allocated by readComponent or readComponents
    pub fn freeComponent(self: *ComponentReader, component: ComponentInstance) void {
        self.allocator.free(component.data);
    }

    /// Free components array and all component data allocated by readComponents
    pub fn freeComponents(self: *ComponentReader, components: []ComponentInstance) void {
        for (components) |component| {
            self.freeComponent(component);
        }
        self.allocator.free(components);
    }
};

/// The World is the main interface for managing entities and components
pub const World = struct {
    allocator: std.mem.Allocator,
    archetypes: ArchetypeStorage,

    pub fn init(allocator: std.mem.Allocator) World {
        return World{
            .allocator = allocator,
            .archetypes = ArchetypeStorage.init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.archetypes.deinit();
    }

    /// Add components of types in Components to the entity, initializing with values.
    /// If the entity already has components, it will be migrated to a new archetype.
    /// Components must be a tuple of types, values a tuple of corresponding values.
    ///
    /// Example:
    /// ```zig
    /// api.add(entity, struct { Position: comps2d.Position, Velocity: comps2d.Velocity }, .{ .Position = pos, .Velocity = vel });
    /// ```
    pub fn add(self: *World, entity: Entity, comptime Components: anytype, values: anytype) !void {
        const components_type = if (@typeInfo(@TypeOf(Components)) == .type) Components else @TypeOf(Components);
        const info = @typeInfo(components_type);
        comptime if (info != .@"struct" and !info.@"struct".is_tuple) @compileError("Components must be a tuple of types");
        const field_count = info.@"struct".fields.len;

        // Check if entity exists (migration path)
        if (self.archetypes.getEntityEntry(entity)) |entry| {
            // SLOW PATH: Entity migration - use heap allocations
            // Gather new component info, using heap-allocated buffers for data
            var new_components: [field_count]ComponentInstance = undefined;
            var heap_data: [field_count][]u8 = undefined;
            inline for (info.@"struct".fields, 0..) |field, i| {
                const T = field.type;
                const comp_info = reflect.getTypeInfo(T);
                var runtime_value: T = values[i];
                const bytes = std.mem.asBytes(&runtime_value);
                heap_data[i] = try self.allocator.alloc(u8, comp_info.size);
                std.mem.copyForwards(u8, heap_data[i], bytes);
                new_components[i] = ComponentInstance{
                    .hash = comp_info.hash,
                    .size = comp_info.size,
                    .data = heap_data[i][0..comp_info.size],
                };
            }
            defer for (heap_data) |d| self.allocator.free(d);

            const src_arch = entry.archetype;
            const src_idx = entry.index;
            const src_types = src_arch.signature.types;
            const src_sizes = src_arch.component_sizes;
            const src_arrays = src_arch.component_arrays;

            // Build new signature: merge old and new component hashes, deduped
            var all_hashes = try std.ArrayList(u64).initCapacity(self.allocator, src_types.len + field_count);
            defer all_hashes.deinit(self.allocator);
            for (src_types) |h| try all_hashes.append(self.allocator, h);
            for (new_components) |comp| {
                var found = false;
                for (src_types) |h| {
                    if (h == comp.hash) found = true;
                }
                if (!found) try all_hashes.append(self.allocator, comp.hash);
            }
            const hashes = all_hashes.items;
            std.sort.insertion(u64, hashes, {}, std.sort.asc(u64));

            // Build new sizes and data arrays in signature order
            var sizes_mig = try self.allocator.alloc(usize, hashes.len);
            var data_mig = try self.allocator.alloc([]const u8, hashes.len);
            defer self.allocator.free(sizes_mig);
            defer self.allocator.free(data_mig);
            for (hashes, 0..) |h, i| {
                // If this is a new component, use new_components
                var found_new = false;
                for (new_components) |comp| {
                    if (comp.hash == h) {
                        sizes_mig[i] = comp.size;
                        data_mig[i] = comp.data;
                        found_new = true;
                        break;
                    }
                }
                if (!found_new) {
                    // Copy from old archetype
                    for (src_types, 0..) |src_h, j| {
                        if (src_h == h) {
                            sizes_mig[i] = src_sizes[j];
                            const comp_size = src_sizes[j];
                            const arr = &src_arrays[j];
                            const offset = src_idx * comp_size;
                            data_mig[i] = arr.items[offset .. offset + comp_size];
                            break;
                        }
                    }
                }
            }
            // Always heap-allocate hashes for migration signature
            const hashes_heap = try self.allocator.alloc(u64, hashes.len);
            std.mem.copyForwards(u64, hashes_heap, hashes);
            const signature_mig = @import("archetype.zig").ArchetypeSignature{ .types = hashes_heap };
            self.remove(entity); // Remove from old archetype before adding to new
            try self.archetypes.addEntityToArchetype(entity, signature_mig, sizes_mig, data_mig);
            // Free the migration signature's types after use
            self.allocator.free(signature_mig.types);
        } else {
            // FAST PATH: New entity - use stack allocations and avoid all heap operations

            if (field_count == 0) {
                // Empty entity - special case
                const empty_hashes = try self.allocator.alloc(u64, 0);
                defer self.allocator.free(empty_hashes);
                const signature = @import("archetype.zig").ArchetypeSignature{ .types = empty_hashes };
                const empty_sizes: []const usize = &[_]usize{};
                const empty_data: [][]const u8 = &[_][]const u8{};
                try self.archetypes.addEntityToArchetype(entity, signature, empty_sizes, @constCast(empty_data));
                return;
            }

            // Compute sorted component hashes at compile time
            comptime var sorted_indices: [field_count]usize = undefined;
            comptime {
                // Build array of (hash, index) pairs
                var hash_index_pairs: [field_count]struct { hash: u64, index: usize } = undefined;
                for (info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    const comp_info = reflect.getTypeInfo(T);
                    hash_index_pairs[i] = .{ .hash = comp_info.hash, .index = i };
                }
                // Sort by hash
                const lessThan = struct {
                    fn f(_: void, a: @TypeOf(hash_index_pairs[0]), b: @TypeOf(hash_index_pairs[0])) bool {
                        return a.hash < b.hash;
                    }
                }.f;
                std.sort.insertion(@TypeOf(hash_index_pairs[0]), &hash_index_pairs, {}, lessThan);
                // Extract sorted indices
                for (hash_index_pairs, 0..) |pair, i| {
                    sorted_indices[i] = pair.index;
                }
            }

            // Stack-allocate runtime data arrays
            var sorted_hashes: [field_count]u64 = undefined;
            var sizes: [field_count]usize = undefined;
            var data: [field_count][]const u8 = undefined;

            // Fill arrays in sorted order
            inline for (sorted_indices, 0..) |orig_idx, sorted_idx| {
                const field = info.@"struct".fields[orig_idx];
                const T = field.type;
                const comp_info = reflect.getTypeInfo(T);
                sorted_hashes[sorted_idx] = comp_info.hash;
                sizes[sorted_idx] = comp_info.size;

                // Get the value and store pointer to it
                var runtime_value: T = values[orig_idx];
                data[sorted_idx] = std.mem.asBytes(&runtime_value);
            }

            // Use stack-allocated signature for lookup
            const stack_signature = @import("archetype.zig").ArchetypeSignature{ .types = &sorted_hashes };

            // OPTIMIZATION: Direct archetype insertion (bypasses addEntityToArchetype wrapper)
            const archetype = try self.archetypes.getOrCreateArchetype(stack_signature, &sizes);

            const idx = archetype.entities.items.len;

            // Ensure capacity first
            try archetype.entities.ensureUnusedCapacity(self.allocator, 1);
            for (archetype.component_arrays, 0..) |*arr, i| {
                try arr.ensureUnusedCapacity(self.allocator, sizes[i]);
            }

            // Direct write to entity array
            archetype.entities.items.ptr[idx] = entity;
            archetype.entities.items.len += 1;

            // Direct @memcpy for component data
            for (data, 0..) |component_data, i| {
                const size = sizes[i];
                const arr = &archetype.component_arrays[i];
                const dest = arr.items.ptr + arr.items.len;
                @memcpy(dest[0..size], component_data[0..size]);
                arr.items.len += size;
            }

            // Update sparse array - UNSAFE: direct write after ensuring capacity
            const entity_id = entity.id;
            try self.archetypes.entity_sparse_array.ensureUnusedCapacity(self.allocator, @max(entity_id + 1, self.archetypes.entity_sparse_array.items.len) - self.archetypes.entity_sparse_array.items.len);
            if (self.archetypes.entity_sparse_array.items.len <= entity_id) {
                const old_len = self.archetypes.entity_sparse_array.items.len;
                self.archetypes.entity_sparse_array.items.len = entity_id + 1;
                @memset(self.archetypes.entity_sparse_array.items[old_len..entity_id], null);
            }
            self.archetypes.entity_sparse_array.items[entity_id] = .{ .archetype = archetype, .index = idx };
        }
    }

    /// Add multiple entities with the same component set and values (much faster than calling add() in a loop)
    pub fn addBatch(self: *World, entities: []const Entity, comptime Components: anytype, values: anytype) !void {
        if (entities.len == 0) return;

        const components_type = if (@typeInfo(@TypeOf(Components)) == .type) Components else @TypeOf(Components);
        const info = @typeInfo(components_type);
        comptime {
            if (info != .@"struct") @compileError("Components must be a tuple of types");
            if (!info.@"struct".is_tuple) @compileError("Components must be a tuple of types");
        }
        const field_count = info.@"struct".fields.len;

        // Compute sorted component hashes at compile time (same as add fast path)
        comptime var sorted_indices: [field_count]usize = undefined;
        comptime {
            if (field_count > 0) {
                var hash_index_pairs: [field_count]struct { hash: u64, index: usize } = undefined;
                for (info.@"struct".fields, 0..) |field, i| {
                    const T = field.type;
                    const comp_info = reflect.getTypeInfo(T);
                    hash_index_pairs[i] = .{ .hash = comp_info.hash, .index = i };
                }
                const lessThan = struct {
                    fn f(_: void, a: @TypeOf(hash_index_pairs[0]), b: @TypeOf(hash_index_pairs[0])) bool {
                        return a.hash < b.hash;
                    }
                }.f;
                std.sort.insertion(@TypeOf(hash_index_pairs[0]), &hash_index_pairs, {}, lessThan);
                for (hash_index_pairs, 0..) |pair, i| {
                    sorted_indices[i] = pair.index;
                }
            }
        }

        // Runtime arrays for sorted data
        var sorted_hashes: [field_count]u64 = undefined;
        var sizes: [field_count]usize = undefined;
        var data: [field_count][]const u8 = undefined;

        inline for (sorted_indices, 0..) |orig_idx, sorted_idx| {
            const field = info.@"struct".fields[orig_idx];
            const T = field.type;
            const comp_info = reflect.getTypeInfo(T);
            sorted_hashes[sorted_idx] = comp_info.hash;
            sizes[sorted_idx] = comp_info.size;
            var runtime_value: T = values[orig_idx];
            data[sorted_idx] = std.mem.asBytes(&runtime_value);
        }

        // Use stack signature for archetype lookup
        const stack_signature = @import("archetype.zig").ArchetypeSignature{ .types = &sorted_hashes };

        // Get or create archetype
        const archetype = try self.archetypes.getOrCreateArchetype(stack_signature, &sizes);

        // Reserve capacity in archetype for batch
        try archetype.entities.ensureTotalCapacity(self.allocator, archetype.entities.items.len + entities.len);
        for (archetype.component_arrays, 0..) |*arr, i| {
            const comp_size = sizes[i];
            const needed_bytes = comp_size * entities.len;
            try arr.ensureTotalCapacity(self.allocator, arr.items.len + needed_bytes);
        }

        // Ensure sparse array capacity for all entities
        const max_entity_id = blk: {
            var max: u32 = 0;
            for (entities) |e| {
                if (e.id > max) max = e.id;
            }
            break :blk max;
        };
        try self.archetypes.entity_sparse_array.ensureTotalCapacity(self.allocator, max_entity_id + 1);
        if (self.archetypes.entity_sparse_array.items.len < max_entity_id + 1) {
            const old_len = self.archetypes.entity_sparse_array.items.len;
            self.archetypes.entity_sparse_array.items.len = max_entity_id + 1;
            // Initialize new slots to null
            @memset(self.archetypes.entity_sparse_array.items[old_len .. max_entity_id + 1], null);
        }

        for (entities) |entity| {
            const idx = archetype.entities.items.len;

            // Direct write to entity array
            archetype.entities.items.ptr[idx] = entity;
            archetype.entities.items.len += 1;

            // Direct @memcpy for component data
            for (data, 0..) |component_data, i| {
                const size = sizes[i];
                const arr = &archetype.component_arrays[i];
                const dest = arr.items.ptr + arr.items.len;
                @memcpy(dest[0..size], component_data[0..size]);
                arr.items.len += size;
            }

            // Direct sparse array write (capacity already ensured)
            self.archetypes.entity_sparse_array.items[entity.id] = .{ .archetype = archetype, .index = idx };
        }
    }

    /// Get a pointer to component T for an entity, or null if not present
    pub fn get(self: *World, entity: Entity, comptime T: type) ?*T {
        const info = reflect.getTypeInfo(T);
        if (self.archetypes.getEntityEntry(entity)) |entry| {
            const arch = entry.archetype;
            var idx: ?usize = null;
            for (arch.signature.types, 0..) |h, i| {
                if (h == info.hash) idx = i;
            }
            if (idx) |i| {
                const comp_size = arch.component_sizes[i];
                const offset = entry.index * comp_size;
                const arr = &arch.component_arrays[i];

                if (offset + comp_size <= arr.items.len) {
                    return @alignCast(std.mem.bytesAsValue(T, arr.items[offset .. offset + comp_size]));
                }
            }
        }
        return null;
    }

    /// Check if an entity has a component T
    pub fn has(self: *World, entity: Entity, comptime T: type) bool {
        return self.get(entity, T) != null;
    }

    /// Get all components for an entity as an array of ComponentInstance
    /// Caller is responsible for freeing the returned array
    pub fn getAllComponents(self: *World, allocator: std.mem.Allocator, entity: Entity) ![]ComponentInstance {
        if (self.archetypes.getEntityEntry(entity)) |entry| {
            const arch = entry.archetype;
            const entity_index = entry.index;

            // Allocate array for all components
            var components = try allocator.alloc(ComponentInstance, arch.signature.types.len);

            // Fill in component data for each type in the archetype
            for (arch.signature.types, 0..) |type_hash, i| {
                const comp_size = arch.component_sizes[i];
                const offset = entity_index * comp_size;
                const arr = &arch.component_arrays[i];

                if (offset + comp_size <= arr.items.len) {
                    components[i] = ComponentInstance{
                        .hash = type_hash,
                        .size = comp_size,
                        .data = arr.items[offset .. offset + comp_size],
                    };
                } else {
                    // If we can't access the data, still create an entry but with empty data
                    components[i] = ComponentInstance{
                        .hash = type_hash,
                        .size = comp_size,
                        .data = &[_]u8{},
                    };
                }
            }

            return components;
        }

        // Entity not found, return empty array
        return try allocator.alloc(ComponentInstance, 0);
    }

    /// Remove an entity entirely from the ECS
    pub fn remove(self: *World, entity: Entity) void {
        if (self.archetypes.getEntityEntry(entity)) |entry| {
            const arch = entry.archetype;
            const idx = entry.index;
            const last_idx = arch.entities.items.len - 1;
            arch.entities.items[idx] = arch.entities.items[last_idx];
            arch.entities.items.len -= 1;
            for (arch.component_arrays, 0..) |*arr, i| {
                const comp_size = arch.component_sizes[i];
                const off = idx * comp_size;
                const last_off = last_idx * comp_size;
                if (idx != last_idx) {
                    std.mem.copyForwards(u8, arr.items[off .. off + comp_size], arr.items[last_off .. last_off + comp_size]);
                }
                arr.items.len -= comp_size;
            }
            if (last_idx != idx) {
                const swapped_entity = arch.entities.items[idx];
                self.archetypes.setEntityEntry(swapped_entity, .{ .archetype = arch, .index = idx }) catch {};
            }
            self.archetypes.removeEntity(entity);
        }
    }

    /// Remove a single component T from an entity by migrating it to a new archetype without T
    pub fn removeComponent(self: *World, entity: Entity, comptime T: type) error{OutOfMemory}!void {
        if (self.archetypes.getEntityEntry(entity)) |entry| {
            const src_arch = entry.archetype;
            const src_idx = entry.index;
            // Build new signature: remove T's hash from the current signature
            const t_info = reflect.getTypeInfo(T);
            const src_types = src_arch.signature.types;
            var new_types = try std.ArrayList(u64).initCapacity(self.allocator, src_types.len);
            defer new_types.deinit(self.allocator);
            var new_sizes = try std.ArrayList(usize).initCapacity(self.allocator, src_types.len);
            defer new_sizes.deinit(self.allocator);
            var new_data = try std.ArrayList([]const u8).initCapacity(self.allocator, src_types.len);
            defer new_data.deinit(self.allocator);
            var n: usize = 0;
            for (src_types, 0..) |h, i| {
                if (h != t_info.hash) {
                    try new_types.append(self.allocator, h);
                    try new_sizes.append(self.allocator, src_arch.component_sizes[i]);
                    const comp_size = src_arch.component_sizes[i];
                    const arr = &src_arch.component_arrays[i];
                    const offset = src_idx * comp_size;
                    try new_data.append(self.allocator, arr.items[offset .. offset + comp_size]);
                    n += 1;
                }
            }
            if (n == src_types.len) return; // T not found, nothing to do
            // Create new signature with heap-allocated types array
            const dst_types_heap = try self.allocator.alloc(u64, n);
            std.mem.copyForwards(u64, dst_types_heap, new_types.items[0..n]);
            const dst_sizes = new_sizes.items[0..n];
            const dst_data = new_data.items[0..n];
            const dst_signature = @import("archetype.zig").ArchetypeSignature{ .types = dst_types_heap };
            // Remove from old archetype first
            self.remove(entity);
            // Add to new archetype
            self.archetypes.addEntityToArchetype(entity, dst_signature, dst_sizes, dst_data) catch return;
            // Free the heap-allocated signature.types after use
            self.allocator.free(dst_signature.types);
        }
    }

    /// Query: iterate all entities with a given component set (returns iterator)
    pub fn query(self: *World, comptime Components: anytype, comptime Exclude: anytype) Query(Components, Exclude) {
        const components_type = if (@typeInfo(@TypeOf(Components)) == .type) Components else @TypeOf(Components);
        const info = @typeInfo(components_type);
        comptime if (info != .@"struct") @compileError("Components must be a struct with named fields or tuple of types");

        const field_count = info.@"struct".fields.len;
        var hashes: [field_count]u64 = undefined;
        inline for (info.@"struct".fields, 0..) |field, i| {
            const T = field.type;
            const comp_info = reflect.getTypeInfo(T);
            hashes[i] = comp_info.hash;
        }
        std.sort.insertion(u64, &hashes, {}, std.sort.asc(u64));

        const exclude_type = if (@typeInfo(@TypeOf(Exclude)) == .type) Exclude else @TypeOf(Exclude);
        const exclude_info = @typeInfo(exclude_type);
        comptime if (exclude_info != .@"struct") @compileError("Exclude must be a struct with named fields or tuple of types");

        const exclude_count = exclude_info.@"struct".fields.len;
        var exclude_hashes: [exclude_count]u64 = undefined;
        inline for (exclude_info.@"struct".fields, 0..) |field, i| {
            const T = field.type;
            const comp_info = reflect.getTypeInfo(T);
            exclude_hashes[i] = comp_info.hash;
        }
        std.sort.insertion(u64, &exclude_hashes, {}, std.sort.asc(u64));

        return @import("query.zig").Query(Components, Exclude).init(&self.archetypes);
    }
};

test "ComponentInstance.from creates component correctly" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const pos = TestPosition{ .x = 10.0, .y = 20.0 };
    const comp = ComponentInstance.from(TestPosition, &pos);

    const expected_info = reflect.getTypeInfo(TestPosition);
    try std.testing.expect(comp.hash == expected_info.hash);
    try std.testing.expect(comp.size == expected_info.size);
    try std.testing.expect(comp.data.len == @sizeOf(TestPosition));
}

test "ComponentInstance.as returns correct typed pointer" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const TestVelocity = struct {
        dx: f32,
        dy: f32,
    };

    const pos = TestPosition{ .x = 15.5, .y = 25.5 };
    const comp = ComponentInstance.from(TestPosition, &pos);

    if (comp.as(TestPosition)) |retrieved_pos| {
        try std.testing.expect(retrieved_pos.x == 15.5);
        try std.testing.expect(retrieved_pos.y == 25.5);
    } else {
        try std.testing.expect(false); // Should not be null
    }

    // Test with wrong type returns null
    const wrong_type = comp.as(TestVelocity);
    try std.testing.expect(wrong_type == null);
}

test "ComponentInstance.asMut allows mutation" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    var pos = TestPosition{ .x = 5.0, .y = 10.0 };
    const comp = ComponentInstance.from(TestPosition, &pos);

    if (comp.asMut(TestPosition)) |mut_pos| {
        mut_pos.x = 100.0;
        mut_pos.y = 200.0;

        // Verify mutation worked
        try std.testing.expect(mut_pos.x == 100.0);
        try std.testing.expect(mut_pos.y == 200.0);
    } else {
        try std.testing.expect(false); // Should not be null
    }
}

test "ComponentInstance writeTo and readFrom" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const allocator = std.testing.allocator;

    // Create original component
    const original_pos = TestPosition{ .x = 42.0, .y = 84.0 };
    const original_comp = ComponentInstance.from(TestPosition, &original_pos);

    // Write to buffer
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);
    try original_comp.writeTo(buffer.writer(allocator).any());

    // Read back from buffer
    var fbs = std.io.fixedBufferStream(buffer.items);
    const read_comp = try ComponentInstance.readFrom(fbs.reader().any(), allocator);
    defer allocator.free(read_comp.data);

    // Verify the data matches
    try std.testing.expect(read_comp.hash == original_comp.hash);
    try std.testing.expect(read_comp.size == original_comp.size);

    if (read_comp.as(TestPosition)) |read_pos| {
        try std.testing.expect(read_pos.x == 42.0);
        try std.testing.expect(read_pos.y == 84.0);
    } else {
        try std.testing.expect(false); // Should not be null
    }
}

test "ComponentWriter writeComponent and writeTypedComponent" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const TestVelocity = struct {
        dx: f32,
        dy: f32,
    };

    const allocator = std.testing.allocator;

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    var writer = ComponentWriter.init(buffer.writer(allocator).any());

    // Test writeTypedComponent
    const pos = TestPosition{ .x = 1.0, .y = 2.0 };
    try writer.writeTypedComponent(TestPosition, &pos);

    const vel = TestVelocity{ .dx = 3.0, .dy = 4.0 };
    try writer.writeTypedComponent(TestVelocity, &vel);

    // Verify we can read them back
    var fbs = std.io.fixedBufferStream(buffer.items);
    var reader = ComponentReader.init(fbs.reader().any(), allocator);

    const read_pos_comp = try reader.readComponent();
    defer reader.freeComponent(read_pos_comp);
    const read_vel_comp = try reader.readComponent();
    defer reader.freeComponent(read_vel_comp);

    if (read_pos_comp.as(TestPosition)) |read_pos| {
        try std.testing.expect(read_pos.x == 1.0);
        try std.testing.expect(read_pos.y == 2.0);
    } else {
        try std.testing.expect(false);
    }

    if (read_vel_comp.as(TestVelocity)) |read_vel| {
        try std.testing.expect(read_vel.dx == 3.0);
        try std.testing.expect(read_vel.dy == 4.0);
    } else {
        try std.testing.expect(false);
    }
}

test "ComponentWriter writeComponents with count header" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const TestHealth = struct {
        current: i32,
        max: i32,
    };
    const allocator = std.testing.allocator;

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    var writer = ComponentWriter.init(buffer.writer(allocator).any());

    // Create multiple components
    const pos1 = TestPosition{ .x = 1.0, .y = 2.0 };
    const pos2 = TestPosition{ .x = 3.0, .y = 4.0 };
    const health = TestHealth{ .current = 100, .max = 100 };

    const components = [_]ComponentInstance{
        ComponentInstance.from(TestPosition, &pos1),
        ComponentInstance.from(TestPosition, &pos2),
        ComponentInstance.from(TestHealth, &health),
    };

    try writer.writeComponents(&components);

    // Read them back
    var fbs = std.io.fixedBufferStream(buffer.items);
    var reader = ComponentReader.init(fbs.reader().any(), allocator);

    const read_components = try reader.readComponents();
    defer reader.freeComponents(read_components);

    try std.testing.expect(read_components.len == 3);

    // Verify first position
    if (read_components[0].as(TestPosition)) |read_pos| {
        try std.testing.expect(read_pos.x == 1.0);
        try std.testing.expect(read_pos.y == 2.0);
    } else {
        try std.testing.expect(false);
    }

    // Verify second position
    if (read_components[1].as(TestPosition)) |read_pos| {
        try std.testing.expect(read_pos.x == 3.0);
        try std.testing.expect(read_pos.y == 4.0);
    } else {
        try std.testing.expect(false);
    }

    // Verify health
    if (read_components[2].as(TestHealth)) |read_health| {
        try std.testing.expect(read_health.current == 100);
        try std.testing.expect(read_health.max == 100);
    } else {
        try std.testing.expect(false);
    }
}

test "ComponentReader memory management" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const allocator = std.testing.allocator;

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    // Write a component
    const pos = TestPosition{ .x = 123.45, .y = 678.90 };
    const comp = ComponentInstance.from(TestPosition, &pos);
    try comp.writeTo(buffer.writer(allocator).any());

    // Read it back and ensure proper cleanup
    var fbs = std.io.fixedBufferStream(buffer.items);
    var reader = ComponentReader.init(fbs.reader().any(), allocator);

    const read_comp = try reader.readComponent();

    // Verify data is correct
    if (read_comp.as(TestPosition)) |read_pos| {
        try std.testing.expect(read_pos.x == 123.45);
        try std.testing.expect(read_pos.y == 678.90);
    } else {
        try std.testing.expect(false);
    }

    // Clean up memory
    reader.freeComponent(read_comp);

    // Test should complete without memory leaks when run with testing allocator
}

test "ComponentInstance type safety" {
    // Test structures for component serialization tests
    const TestPosition = struct {
        x: f32,
        y: f32,
    };

    const TestVelocity = struct {
        dx: f32,
        dy: f32,
    };

    const pos = TestPosition{ .x = 1.0, .y = 2.0 };
    const pos_comp = ComponentInstance.from(TestPosition, &pos);

    const vel = TestVelocity{ .dx = 3.0, .dy = 4.0 };
    const vel_comp = ComponentInstance.from(TestVelocity, &vel);

    // Verify components have different hashes
    try std.testing.expect(pos_comp.hash != vel_comp.hash);

    // Verify cross-type access returns null
    try std.testing.expect(pos_comp.as(TestVelocity) == null);
    try std.testing.expect(vel_comp.as(TestPosition) == null);
    try std.testing.expect(pos_comp.asMut(TestVelocity) == null);
    try std.testing.expect(vel_comp.asMut(TestPosition) == null);

    // Verify correct type access works
    try std.testing.expect(pos_comp.as(TestPosition) != null);
    try std.testing.expect(vel_comp.as(TestVelocity) != null);
}

test "empty component array serialization" {
    const allocator = std.testing.allocator;

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer buffer.deinit(allocator);

    var writer = ComponentWriter.init(buffer.writer(allocator).any());

    // Write empty array
    const empty_components: []const ComponentInstance = &[_]ComponentInstance{};
    try writer.writeComponents(empty_components);

    // Read back empty array
    var fbs = std.io.fixedBufferStream(buffer.items);
    var reader = ComponentReader.init(fbs.reader().any(), allocator);

    const read_components = try reader.readComponents();
    defer reader.freeComponents(read_components);

    try std.testing.expect(read_components.len == 0);
}
