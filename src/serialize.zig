const std = @import("std");
const reflect = @import("zevy_reflect");
const ecs = @import("ecs.zig");

/// Represents a component instance with its type information and data
pub const ComponentInstance = struct {
    hash: u64,
    size: usize,
    data: []const u8,

    pub fn from(comptime T: type, value: *const T) ComponentInstance {
        const info = comptime reflect.getReflectInfo(T).type;
        return ComponentInstance{
            .hash = info.hash,
            .size = info.size,
            .data = std.mem.asBytes(value),
        };
    }

    /// Get the component data as a specific type T
    /// Returns null if the type hash doesn't match
    pub fn as(self: *const ComponentInstance, comptime T: type) ?*const T {
        const expected_info = reflect.getReflectInfo(T).type;
        if (self.hash == expected_info.hash and self.size == expected_info.size) {
            return @alignCast(std.mem.bytesAsValue(T, self.data[0..self.size]));
        }

        return null;
    }

    /// Write this component to any std.io.Writer
    pub fn writeTo(self: *const ComponentInstance, writer: std.io.AnyWriter) anyerror!void {
        try writer.writeInt(u64, self.hash, .little);
        try writer.writeInt(usize, self.size, .little);
        try writer.writeAll(self.data);
    }

    /// Create a ComponentInstance from any std.io.Reader
    ///
    /// The caller is responsible for freeing the returned data
    pub fn readFrom(reader: std.io.AnyReader, allocator: std.mem.Allocator) anyerror!ComponentInstance {
        const comp_hash = try reader.readInt(u64, .little);
        const comp_size = try reader.readInt(usize, .little);
        const comp_data = try allocator.alloc(u8, comp_size);
        errdefer allocator.free(comp_data);
        const bytes_read = try reader.readAll(comp_data);
        if (bytes_read != comp_size) {
            return error.UnexpectedEndOfStream;
        }
        return ComponentInstance{
            .hash = comp_hash,
            .size = comp_size,
            .data = comp_data,
        };
    }
};

/// Represents a serialized entity with all its components and referenced entities
pub const EntityInstance = struct {
    components: []ComponentInstance,
    /// Entities referenced by this entity (for relations with Entity fields)
    /// These are serialized recursively
    referenced_entities: []EntityInstance = &[_]EntityInstance{},

    /// Create an EntityInstance from an entity's components
    /// The EntityInstance owns copies of the component data
    pub fn fromEntity(allocator: std.mem.Allocator, manager: *ecs.Manager, entity: ecs.Entity) !EntityInstance {
        const components_view = try manager.getAllComponents(allocator, entity);
        defer allocator.free(components_view);

        // Allocate the components array
        const components = try allocator.alloc(ComponentInstance, components_view.len);
        errdefer allocator.free(components);

        var i: usize = 0;
        errdefer {
            // Free any component data we've already copied
            for (components[0..i]) |comp| {
                allocator.free(comp.data);
            }
        }

        // Make owned copies of each component's data
        for (components_view, 0..) |comp_view, idx| {
            const data_copy = try allocator.alloc(u8, comp_view.data.len);
            @memcpy(data_copy, comp_view.data);
            components[idx] = ComponentInstance{
                .hash = comp_view.hash,
                .size = comp_view.size,
                .data = data_copy,
            };
            i += 1;
        }

        return EntityInstance{
            .components = components,
            .referenced_entities = &[_]EntityInstance{},
        };
    }

    /// Create an EntityInstance that also includes all referenced entities
    /// This is useful for serializing complete entity hierarchies with relations
    /// referenced_entities_map tracks which entities have already been serialized to avoid duplicates
    pub fn fromEntityWithReferences(
        allocator: std.mem.Allocator,
        manager: *ecs.Manager,
        entity: ecs.Entity,
        referenced_entities_map: *std.AutoHashMap(u32, ecs.Entity),
    ) !EntityInstance {
        const components_view = try manager.getAllComponents(allocator, entity);
        defer allocator.free(components_view);

        // Allocate the components array
        const components = try allocator.alloc(ComponentInstance, components_view.len);
        errdefer allocator.free(components);

        var i: usize = 0;
        errdefer {
            for (components[0..i]) |comp| {
                allocator.free(comp.data);
            }
        }

        // Copy component data and collect referenced entities
        var referenced_list = try std.ArrayList(EntityInstance).initCapacity(allocator, 0);
        errdefer {
            for (referenced_list.items) |*ref_entity| {
                ref_entity.deinit(allocator);
            }
            referenced_list.deinit(allocator);
        }

        for (components_view, 0..) |comp_view, idx| {
            const data_copy = try allocator.alloc(u8, comp_view.data.len);
            @memcpy(data_copy, comp_view.data);
            components[idx] = ComponentInstance{
                .hash = comp_view.hash,
                .size = comp_view.size,
                .data = data_copy,
            };
            i += 1;

            // Check if this component has Entity fields (like Relation components)
            // We look for patterns like Relation(...) which have a target: Entity field
            if (comp_view.size > 0) {
                // Try to detect Entity fields in the component data
                // This is a heuristic: if the component contains valid entity IDs, serialize them
                if (comp_view.data.len >= @sizeOf(ecs.Entity)) {
                    // Check if first field might be an Entity (id + generation)
                    const potential_entity = @as(*const ecs.Entity, @alignCast(std.mem.bytesAsValue(ecs.Entity, comp_view.data[0..@sizeOf(ecs.Entity)]))).*;
                    if (manager.isAlive(potential_entity)) {
                        const gop = try referenced_entities_map.getOrPut(potential_entity.id);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = potential_entity;
                            const ref_instance = try fromEntity(allocator, manager, potential_entity);
                            try referenced_list.append(allocator, ref_instance);
                        }
                    }
                }
            }
        }

        return EntityInstance{
            .components = components,
            .referenced_entities = try referenced_list.toOwnedSlice(allocator),
        };
    }

    /// Create an entity in the ECS from this EntityInstance
    /// Returns the created entity
    /// Note: Entity references in components will maintain their original ID values
    pub fn toEntity(self: *EntityInstance, manager: *ecs.Manager) !ecs.Entity {
        return try manager.createFromComponents(self.components);
    }

    /// Create all referenced entities and the main entity
    /// Returns the main entity; referenced entities are created separately
    pub fn toEntityWithReferences(self: *EntityInstance, manager: *ecs.Manager, allocator: std.mem.Allocator) !ecs.Entity {
        // Create all referenced entities first
        var entity_map = std.AutoHashMap(u32, ecs.Entity).init(allocator);
        defer entity_map.deinit();

        for (self.referenced_entities) |ref_entity_instance| {
            const created_entity = try ref_entity_instance.toEntity(manager);
            // In a real implementation, we'd track the original entity ID from serialization
            try entity_map.put(created_entity.id, created_entity);
        }

        // Create the main entity
        return try self.toEntity(manager);
    }

    /// Write this entity instance to any std.io.Writer
    pub fn writeTo(self: *const EntityInstance, writer: std.io.AnyWriter) anyerror!void {
        try writer.writeInt(usize, self.components.len, .little);
        for (self.components) |component| {
            try component.writeTo(writer);
        }
        // Write referenced entities
        try writer.writeInt(usize, self.referenced_entities.len, .little);
        for (self.referenced_entities) |ref_entity| {
            try ref_entity.writeTo(writer);
        }
    }

    /// Read an EntityInstance from any std.io.Reader
    /// The caller is responsible for freeing the returned data using deinit()
    pub fn readFrom(reader: std.io.AnyReader, allocator: std.mem.Allocator) anyerror!EntityInstance {
        const count = try reader.readInt(usize, .little);
        const components = try allocator.alloc(ComponentInstance, count);
        errdefer allocator.free(components);

        var i: usize = 0;
        errdefer {
            // Free any components that were successfully read before the error
            for (components[0..i]) |component| {
                allocator.free(component.data);
            }
        }

        for (components) |*component| {
            component.* = try ComponentInstance.readFrom(reader, allocator);
            i += 1;
        }

        // Read referenced entities
        const ref_count = try reader.readInt(usize, .little);
        const referenced_entities = try allocator.alloc(EntityInstance, ref_count);
        errdefer allocator.free(referenced_entities);

        var j: usize = 0;
        errdefer {
            for (referenced_entities[0..j]) |*ref_entity| {
                ref_entity.deinit(allocator);
            }
        }

        for (referenced_entities) |*ref_entity| {
            ref_entity.* = try readFrom(reader, allocator);
            j += 1;
        }

        return EntityInstance{
            .components = components,
            .referenced_entities = referenced_entities,
        };
    }

    /// Free all memory associated with this EntityInstance
    pub fn deinit(self: *EntityInstance, allocator: std.mem.Allocator) void {
        for (self.components) |component| {
            allocator.free(component.data);
        }
        allocator.free(self.components);
        var i: usize = 0;
        while (i < self.referenced_entities.len) : (i += 1) {
            var ref_entity: *EntityInstance = @constCast(&self.referenced_entities[i]);
            ref_entity.deinit(allocator);
        }
        allocator.free(self.referenced_entities);
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
            try component.writeTo(self.writer);
        }
    }

    /// Write a component of type T with value
    pub fn writeTypedComponent(self: *ComponentWriter, comptime T: type, value: *const T) !void {
        const info = reflect.getReflectInfo(T).type;
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

    pub fn init(reader: std.io.AnyReader) ComponentReader {
        return ComponentReader{ .reader = reader };
    }

    /// Read a single component from the stream
    /// The caller is responsible for freeing the component data
    ///
    /// Returns errors from the underlying reader or OutOfMemory from allocation.
    pub fn readComponent(self: *ComponentReader, allocator: std.mem.Allocator) anyerror!ComponentInstance {
        return ComponentInstance.readFrom(self.reader, allocator);
    }

    /// Read multiple components from the stream, expecting a count header
    /// The caller is responsible for freeing the returned array and component data
    ///
    /// Returns errors from the underlying reader or OutOfMemory from allocation.
    pub fn readComponents(self: *ComponentReader, allocator: std.mem.Allocator) anyerror![]ComponentInstance {
        const count = try self.reader.readInt(usize, .little);
        const components = try allocator.alloc(ComponentInstance, count);
        errdefer allocator.free(components);

        var i: usize = 0;
        errdefer {
            // Free any components that were successfully read before the error
            for (components[0..i]) |component| {
                allocator.free(component.data);
            }
        }

        for (components) |*component| {
            component.* = try self.readComponent(allocator);
            i += 1;
        }
        return components;
    }

    /// Free component data allocated by readComponent or readComponents
    ///
    /// Convieniece method to free a single component
    pub fn freeComponent(self: *ComponentReader, allocator: std.mem.Allocator, component: ComponentInstance) void {
        _ = self;
        allocator.free(component.data);
    }

    /// Free components array and all component data allocated by readComponents
    pub fn freeComponents(self: *ComponentReader, allocator: std.mem.Allocator, components: []ComponentInstance) void {
        for (components) |component| {
            self.freeComponent(allocator, component);
        }
        allocator.free(components);
    }
};
