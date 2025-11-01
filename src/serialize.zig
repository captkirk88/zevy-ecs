const std = @import("std");
const reflect = @import("reflect.zig");
const ecs = @import("ecs.zig");

/// Represents a component instance with its type information and data
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

    /// Write this component to any std.io.Writer
    pub fn writeTo(self: ComponentInstance, writer: std.io.AnyWriter) anyerror!void {
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

/// Represents a serialized entity with all its components
pub const EntityInstance = struct {
    components: []ComponentInstance,

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

        return EntityInstance{ .components = components };
    }

    /// Create an entity in the ECS from this EntityInstance
    /// Returns the created entity
    pub fn toEntity(self: EntityInstance, manager: *ecs.Manager) !ecs.Entity {
        return try manager.createFromComponents(self.components);
    }

    /// Write this entity instance to any std.io.Writer
    pub fn writeTo(self: EntityInstance, writer: std.io.AnyWriter) anyerror!void {
        try writer.writeInt(usize, self.components.len, .little);
        for (self.components) |component| {
            try component.writeTo(writer);
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

        return EntityInstance{ .components = components };
    }

    /// Free all memory associated with this EntityInstance
    pub fn deinit(self: EntityInstance, allocator: std.mem.Allocator) void {
        for (self.components) |component| {
            allocator.free(component.data);
        }
        allocator.free(self.components);
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
