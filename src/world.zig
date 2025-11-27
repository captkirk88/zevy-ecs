const std = @import("std");
const errors = @import("errors.zig");
const ArchetypeStorage = @import("archetype_storage.zig").ArchetypeStorage;
const archetype = @import("archetype.zig");
const ArchetypeSignature = archetype.ArchetypeSignature;
const Entity = @import("ecs.zig").Entity;
const Query = @import("query.zig").Query;
const reflect = @import("reflect.zig");
const serialize = @import("serialize.zig");
pub const ComponentInstance = serialize.ComponentInstance;
const ComponentReader = serialize.ComponentReader;
const ComponentWriter = serialize.ComponentWriter;

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

    /// Add components to the entity, initializing with values from a tuple.
    /// If the entity already has components, it will be migrated to a new archetype.
    /// `values` must be a tuple of component instances.
    ///
    /// Example:
    /// ```zig
    /// world.add(entity, .{ Position{ .x = 0, .y = 0 }, Velocity{ .x = 1, .y = 1 } });
    /// ```
    pub fn add(self: *World, entity: Entity, values: anytype) !void {
        const components_type = @TypeOf(values);
        const info = @typeInfo(components_type);
        comptime if (info != .@"struct" or !info.@"struct".is_tuple) @compileError(std.fmt.comptimePrint("values must be a tuple of component instances: {s}", .{@typeName(components_type)}));
        const field_count = info.@"struct".fields.len;

        // Check if entity exists (migration path)
        if (self.archetypes.get(entity)) |entry| {
            // Slow: Gather new component info, using heap-allocated buffers for data
            var new_components: [field_count]ComponentInstance = undefined;
            var heap_data: [field_count][]u8 = undefined;
            inline for (info.@"struct".fields, 0..) |field, i| {
                const FieldType = field.type;
                const comp_info = reflect.getTypeInfo(FieldType);
                var runtime_value: FieldType = values[i];
                const bytes = std.mem.asBytes(&runtime_value);
                heap_data[i] = try self.allocator.alloc(u8, comp_info.size);
                @memmove(heap_data[i], bytes);
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

            // Temporary storage for copied component data to avoid aliasing
            var temp_data = try self.allocator.alloc([]u8, hashes.len);
            defer {
                for (temp_data) |data| {
                    if (data.len > 0) self.allocator.free(data);
                }
                self.allocator.free(temp_data);
            }

            for (hashes, 0..) |h, i| {
                // If this is a new component, use new_components
                var found_new = false;
                for (new_components) |comp| {
                    if (comp.hash == h) {
                        sizes_mig[i] = comp.size;
                        // Copy new component data to temp storage
                        temp_data[i] = try self.allocator.alloc(u8, comp.size);
                        @memcpy(temp_data[i], comp.data[0..comp.size]);
                        data_mig[i] = temp_data[i];
                        found_new = true;
                        break;
                    }
                }
                if (!found_new) {
                    // Copy from old archetype to temp storage to avoid aliasing
                    for (src_types, 0..) |src_h, j| {
                        if (src_h == h) {
                            sizes_mig[i] = src_sizes[j];
                            const comp_size = src_sizes[j];
                            const arr = &src_arrays[j];
                            const offset = src_idx * comp_size;
                            // Copy to temporary storage instead of referencing arr.items directly
                            temp_data[i] = try self.allocator.alloc(u8, comp_size);
                            @memcpy(temp_data[i], arr.items[offset .. offset + comp_size]);
                            data_mig[i] = temp_data[i];
                            break;
                        }
                    }
                }
            }
            // Always heap-allocate hashes for migration signature
            const hashes_heap = try self.allocator.alloc(u64, hashes.len);
            @memmove(hashes_heap, hashes);
            const signature_mig = ArchetypeSignature{ .types = hashes_heap };
            self.remove(entity); // Remove from old archetype before adding to new
            try self.archetypes.add(entity, signature_mig, sizes_mig, data_mig);
            // Free the migration signature's types after use
            self.allocator.free(signature_mig.types);
        } else {
            // FAST: New entity - use stack allocations and avoid all heap operations

            if (field_count == 0) {
                // Empty entity - special case
                const empty_hashes = try self.allocator.alloc(u64, 0);
                defer self.allocator.free(empty_hashes);
                const signature = ArchetypeSignature{ .types = empty_hashes };
                const empty_sizes: []const usize = &[_]usize{};
                const empty_data: [][]const u8 = &[_][]const u8{};
                try self.archetypes.add(entity, signature, empty_sizes, @constCast(empty_data));
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
            const stack_signature = ArchetypeSignature{ .types = &sorted_hashes };

            const archetype_ptr = try self.archetypes.getOrCreate(stack_signature, &sizes);

            const idx = archetype_ptr.entities.items.len;

            // Ensure capacity first
            try archetype_ptr.entities.ensureUnusedCapacity(self.allocator, 1);
            for (archetype_ptr.component_arrays, 0..) |*arr, i| {
                try arr.ensureUnusedCapacity(self.allocator, sizes[i]);
            }

            // Direct write to entity array
            archetype_ptr.entities.items.ptr[idx] = entity;
            archetype_ptr.entities.items.len += 1;

            // Direct @memcpy for component data
            for (data, 0..) |component_data, i| {
                const size = sizes[i];
                const arr = &archetype_ptr.component_arrays[i];
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
            self.archetypes.entity_sparse_array.items[entity_id] = .{ .archetype = archetype_ptr, .index = idx };
        }
    }

    /// Add an entity from an array of ComponentInstance
    /// This is used for deserializing entities
    pub fn addFromComponentInstances(self: *World, entity: Entity, components: []const ComponentInstance) !void {
        if (components.len == 0) {
            const empty_components = .{};
            try self.add(entity, empty_components);
            return;
        }

        // Build sorted arrays of hashes, sizes, and data
        var hashes = try self.allocator.alloc(u64, components.len);
        defer self.allocator.free(hashes);
        var sizes = try self.allocator.alloc(usize, components.len);
        defer self.allocator.free(sizes);
        var data = try self.allocator.alloc([]const u8, components.len);
        defer self.allocator.free(data);

        for (components, 0..) |comp, i| {
            hashes[i] = comp.hash;
            sizes[i] = comp.size;
            data[i] = comp.data;
        }

        // Sort all arrays by hash to match archetype signature format
        const SortContext = struct {
            hashes: []u64,
            sizes: []usize,
            data: [][]const u8,

            pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                return ctx.hashes[a_index] < ctx.hashes[b_index];
            }

            pub fn swap(ctx: @This(), a_index: usize, b_index: usize) void {
                std.mem.swap(u64, &ctx.hashes[a_index], &ctx.hashes[b_index]);
                std.mem.swap(usize, &ctx.sizes[a_index], &ctx.sizes[b_index]);
                std.mem.swap([]const u8, &ctx.data[a_index], &ctx.data[b_index]);
            }
        };

        const sort_ctx = SortContext{ .hashes = hashes, .sizes = sizes, .data = data };
        std.sort.pdqContext(0, components.len, sort_ctx);

        // Create signature
        const signature_hashes = try self.allocator.alloc(u64, hashes.len);
        defer self.allocator.free(signature_hashes);
        @memmove(signature_hashes, hashes);
        const signature = ArchetypeSignature{ .types = signature_hashes };

        // Add entity to archetype
        try self.archetypes.add(entity, signature, sizes, data);
    }

    /// Add multiple entities with the same component set and values (much faster than calling add() in a loop)
    pub fn addBatch(self: *World, entities: []const Entity, values: anytype) !void {
        if (entities.len == 0) return;

        const components_type = @TypeOf(values);
        const info = @typeInfo(components_type);
        comptime if (info != .@"struct" or !info.@"struct".is_tuple) @compileError(std.fmt.comptimePrint("values must be a tuple of component instances: {s}", .{@typeName(components_type)}));

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
        const stack_signature = ArchetypeSignature{ .types = &sorted_hashes };

        // Get or create archetype
        const archetype_ptr = try self.archetypes.getOrCreate(stack_signature, &sizes);

        // Reserve capacity in archetype for batch
        try archetype_ptr.entities.ensureTotalCapacity(self.allocator, archetype_ptr.entities.items.len + entities.len);
        for (archetype_ptr.component_arrays, 0..) |*arr, i| {
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
            const idx = archetype_ptr.entities.items.len;

            // Direct write to entity array
            archetype_ptr.entities.items.ptr[idx] = entity;
            archetype_ptr.entities.items.len += 1;

            // Direct @memcpy for component data
            for (data, 0..) |component_data, i| {
                const size = sizes[i];
                const arr = &archetype_ptr.component_arrays[i];
                const dest = arr.items.ptr + arr.items.len;
                @memcpy(dest[0..size], component_data[0..size]);
                arr.items.len += size;
            }

            // Direct sparse array write (capacity already ensured)
            self.archetypes.entity_sparse_array.items[entity.id] = .{ .archetype = archetype_ptr, .index = idx };
        }
    }

    /// Get a pointer to component T for an entity, or null if not present
    pub fn get(self: *World, entity: Entity, comptime T: type) ?*T {
        const info = reflect.getTypeInfo(T);
        if (self.archetypes.get(entity)) |entry| {
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
    ///
    /// Caller is responsible for freeing the returned array
    pub fn getAllComponents(self: *World, allocator: std.mem.Allocator, entity: Entity) error{OutOfMemory}![]ComponentInstance {
        if (self.archetypes.get(entity)) |entry| {
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
        if (self.archetypes.get(entity)) |entry| {
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
                    @memmove(arr.items[off .. off + comp_size], arr.items[last_off .. last_off + comp_size]);
                }
                arr.items.len -= comp_size;
            }
            if (last_idx != idx) {
                const swapped_entity = arch.entities.items[idx];
                self.archetypes.set(swapped_entity, .{ .archetype = arch, .index = idx }) catch {};
            }
            self.archetypes.remove(entity);
        }
    }

    /// Remove a single component T from an entity by migrating it to a new archetype without T
    pub fn removeComponent(self: *World, entity: Entity, comptime T: type) error{OutOfMemory}!void {
        if (self.archetypes.get(entity)) |entry| {
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
            @memmove(dst_types_heap, new_types.items[0..n]);
            const dst_sizes = new_sizes.items[0..n];
            const dst_data = new_data.items[0..n];
            const dst_signature = ArchetypeSignature{ .types = dst_types_heap };
            // Remove from old archetype first
            self.remove(entity);
            // Add to new archetype
            self.archetypes.add(entity, dst_signature, dst_sizes, dst_data) catch return;
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
