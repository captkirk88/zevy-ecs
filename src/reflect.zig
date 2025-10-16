const std = @import("std");

pub fn hasFunc(comptime T: type, comptime func_name: []const u8) bool {
    const type_info = @typeInfo(T);
    if (type_info == .@"struct") {
        return @hasDecl(T, func_name);
    } else if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return hasFunc(Child, func_name);
    }
    return false;
}

pub fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    const type_info = @typeInfo(T);
    if (type_info == .@"struct") {
        inline for (type_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return true;
            }
        }
        return false;
    } else if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return hasField(Child, field_name);
    }
    return false;
}

pub fn getFields(comptime T: type) []const []const u8 {
    return std.meta.fieldNames(T);
}

pub fn verifyFuncArgs(comptime T: type, comptime func_name: []const u8, comptime expected_arg_types: []const type) bool {
    const type_info = @typeInfo(T);
    if (type_info == .@"struct") {
        if (!hasFunc(T, func_name)) return false;
        if (!@hasDecl(T, func_name)) return false;
        const fn_type = @typeInfo(@TypeOf(@field(T, func_name)));
        if (fn_type != .@"fn") return false;
        if (fn_type.@"fn".params.len != expected_arg_types.len) return false;
        inline for (0..expected_arg_types.len) |i| {
            if (fn_type.@"fn".params[i].type != expected_arg_types[i]) {
                return false;
            }
        }
        return true;
    } else if (type_info == .pointer) {
        const Child = type_info.pointer.child;
        return verifyFuncArgs(Child, func_name, expected_arg_types);
    }
    return false;
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
/// Tracks which fields have been modified using a bitset (no allocator needed)
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
            return &self._data;
        }

        /// Get const access to the data
        pub fn getConst(self: *const Self) *const T {
            return &self._data;
        }

        /// Mark that changes have occurred
        /// Call this after modifying data to indicate it has changed
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

    try std.testing.expect(hasFunc(TestStruct, "testMethod"));
    try std.testing.expect(!hasFunc(TestStruct, "nonExistentMethod"));
}

test "hasFunc - pointer to struct" {
    const TestStruct = struct {
        value: i32,

        pub fn testMethod(self: @This()) i32 {
            return self.value;
        }
    };

    try std.testing.expect(hasFunc(*TestStruct, "testMethod"));
    try std.testing.expect(!hasFunc(*TestStruct, "nonExistentMethod"));
}

test "hasField - struct with fields" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
        active: bool,
    };

    try std.testing.expect(hasField(TestStruct, "id"));
    try std.testing.expect(hasField(TestStruct, "name"));
    try std.testing.expect(hasField(TestStruct, "active"));
    try std.testing.expect(!hasField(TestStruct, "nonExistentField"));
}

test "hasField - pointer to struct" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
        active: bool,
    };

    try std.testing.expect(hasField(*TestStruct, "id"));
    try std.testing.expect(hasField(*TestStruct, "name"));
    try std.testing.expect(hasField(*TestStruct, "active"));
    try std.testing.expect(!hasField(*TestStruct, "nonExistentField"));
}

test "getFields - returns all field names" {
    const TestStruct = struct {
        id: u32,
        name: []const u8,
        active: bool,
    };

    const fields = getFields(TestStruct);
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

test "verifyFuncArgs - correct arguments" {
    const TestStruct = struct {
        value: i32,

        pub fn add(self: @This(), other: i32) i32 {
            return self.value + other;
        }

        pub fn noArgs(self: @This()) i32 {
            return self.value;
        }
    };

    try std.testing.expect(verifyFuncArgs(TestStruct, "add", &[_]type{ TestStruct, i32 }));
    try std.testing.expect(verifyFuncArgs(TestStruct, "noArgs", &[_]type{TestStruct}));
    try std.testing.expect(!verifyFuncArgs(TestStruct, "add", &[_]type{TestStruct})); // Wrong arg count
    try std.testing.expect(!verifyFuncArgs(TestStruct, "nonExistent", &[_]type{TestStruct})); // Function doesn't exist
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
