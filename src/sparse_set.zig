const std = @import("std");

/// A sparse set data structure optimized for ECS entity lookups.
/// Provides O(1) lookup, insert, and remove operations with cache-friendly iteration.
///
/// The sparse set maintains two arrays:
/// - A sparse array mapping IDs to dense indices
/// - A dense array storing actual values in packed form
///
/// This allows iteration over only valid entries without checking nulls,
/// and swap-and-pop removal without leaving holes.
pub fn SparseSet(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        /// Sparse array: ID -> index in dense array (null if not present)
        sparse: std.ArrayList(?u32),
        /// Dense array of entity IDs (packed, no holes)
        dense_ids: std.ArrayList(u32),
        /// Dense array of values (parallel to dense_ids)
        dense_values: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .sparse = std.ArrayList(?u32).initCapacity(allocator, 0) catch unreachable,
                .dense_ids = std.ArrayList(u32).initCapacity(allocator, 0) catch unreachable,
                .dense_values = std.ArrayList(T).initCapacity(allocator, 0) catch unreachable,
            };
        }

        /// Initialize with pre-allocated capacity for the sparse array
        pub fn initCapacity(allocator: std.mem.Allocator, sparse_capacity: usize) !Self {
            var sparse = try std.ArrayList(?u32).initCapacity(allocator, sparse_capacity);
            // Pre-fill with nulls
            sparse.items.len = sparse_capacity;
            @memset(sparse.items, null);
            return .{
                .allocator = allocator,
                .sparse = sparse,
                .dense_ids = std.ArrayList(u32).initCapacity(allocator, 0) catch unreachable,
                .dense_values = std.ArrayList(T).initCapacity(allocator, 0) catch unreachable,
            };
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit(self.allocator);
            self.dense_ids.deinit(self.allocator);
            self.dense_values.deinit(self.allocator);
        }

        /// Check if an ID exists in the set
        pub fn contains(self: *const Self, id: u32) bool {
            if (id >= self.sparse.items.len) return false;
            return self.sparse.items[id] != null;
        }

        /// Get value by ID, or null if not present
        pub fn get(self: *const Self, id: u32) ?T {
            if (id >= self.sparse.items.len) return null;
            if (self.sparse.items[id]) |dense_idx| {
                return self.dense_values.items[dense_idx];
            }
            return null;
        }

        /// Get pointer to value by ID, or null if not present
        pub fn getPtr(self: *Self, id: u32) ?*T {
            if (id >= self.sparse.items.len) return null;
            if (self.sparse.items[id]) |dense_idx| {
                return &self.dense_values.items[dense_idx];
            }
            return null;
        }

        /// Get const pointer to value by ID, or null if not present
        pub fn getPtrConst(self: *const Self, id: u32) ?*const T {
            if (id >= self.sparse.items.len) return null;
            if (self.sparse.items[id]) |dense_idx| {
                return &self.dense_values.items[dense_idx];
            }
            return null;
        }

        /// Insert or update a value for the given ID
        pub fn set(self: *Self, id: u32, value: T) !void {
            // Grow sparse array if needed
            if (id >= self.sparse.items.len) {
                const old_len = self.sparse.items.len;
                try self.sparse.resize(self.allocator, id + 1);
                @memset(self.sparse.items[old_len..], null);
            }

            if (self.sparse.items[id]) |dense_idx| {
                // Update existing value
                self.dense_values.items[dense_idx] = value;
            } else {
                // Insert new entry
                const new_dense_idx: u32 = @intCast(self.dense_ids.items.len);
                try self.dense_ids.append(self.allocator, id);
                try self.dense_values.append(self.allocator, value);
                self.sparse.items[id] = new_dense_idx;
            }
        }

        /// Remove an entry by ID using swap-and-pop
        pub fn remove(self: *Self, id: u32) void {
            if (id >= self.sparse.items.len) return;
            const dense_idx_opt = self.sparse.items[id];
            if (dense_idx_opt == null) return;
            const dense_idx = dense_idx_opt.?;

            const last_idx = self.dense_ids.items.len - 1;

            if (dense_idx != last_idx) {
                // Swap with last element
                const last_id = self.dense_ids.items[last_idx];
                self.dense_ids.items[dense_idx] = last_id;
                self.dense_values.items[dense_idx] = self.dense_values.items[last_idx];
                // Update swapped entity's sparse reference
                self.sparse.items[last_id] = dense_idx;
            }

            // Pop last element
            _ = self.dense_ids.pop();
            _ = self.dense_values.pop();
            self.sparse.items[id] = null;
        }

        /// Number of entries in the set
        pub fn count(self: *const Self) usize {
            return self.dense_ids.items.len;
        }

        /// Check if empty
        pub fn isEmpty(self: *const Self) bool {
            return self.dense_ids.items.len == 0;
        }

        /// Clear all entries
        pub fn clear(self: *Self) void {
            @memset(self.sparse.items, null);
            self.dense_ids.clearRetainingCapacity();
            self.dense_values.clearRetainingCapacity();
        }

        /// Iterator over all valid (id, value) pairs
        /// Iteration order is NOT sorted by ID
        pub fn iterator(self: *Self) Iterator {
            return .{ .set = self, .index = 0 };
        }

        /// Const iterator over all valid (id, value) pairs
        pub fn constIterator(self: *const Self) ConstIterator {
            return .{ .set = self, .index = 0 };
        }

        pub const Entry = struct {
            id: u32,
            value: *T,
        };

        pub const ConstEntry = struct {
            id: u32,
            value: *const T,
        };

        pub const Iterator = struct {
            set: *Self,
            index: usize,

            pub fn next(self: *Iterator) ?Entry {
                if (self.index >= self.set.dense_ids.items.len) return null;
                const idx = self.index;
                self.index += 1;
                return .{
                    .id = self.set.dense_ids.items[idx],
                    .value = &self.set.dense_values.items[idx],
                };
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        pub const ConstIterator = struct {
            set: *const Self,
            index: usize,

            pub fn next(self: *ConstIterator) ?ConstEntry {
                if (self.index >= self.set.dense_ids.items.len) return null;
                const idx = self.index;
                self.index += 1;
                return .{
                    .id = self.set.dense_ids.items[idx],
                    .value = &self.set.dense_values.items[idx],
                };
            }

            pub fn reset(self: *ConstIterator) void {
                self.index = 0;
            }
        };

        /// Get slice of all dense IDs (for bulk operations)
        pub fn ids(self: *const Self) []const u32 {
            return self.dense_ids.items;
        }

        /// Get slice of all dense values (for bulk operations)
        pub fn values(self: *Self) []T {
            return self.dense_values.items;
        }

        /// Get const slice of all dense values
        pub fn valuesConst(self: *const Self) []const T {
            return self.dense_values.items;
        }

        /// Reserve capacity for dense arrays (for batch insert)
        pub fn reserve(self: *Self, additional: usize) !void {
            try self.dense_ids.ensureTotalCapacity(self.allocator, self.dense_ids.items.len + additional);
            try self.dense_values.ensureTotalCapacity(self.allocator, self.dense_values.items.len + additional);
        }

        /// Insert many (id, value) pairs efficiently in batch
        pub fn insertMany(self: *Self, entity_ids: []const u32, batch_values: []const T) !void {
            try self.reserve(entity_ids.len);
            // Find max id for sparse resize
            var max_id: u32 = 0;
            for (entity_ids) |id| {
                if (id > max_id) max_id = id;
            }
            if (max_id >= self.sparse.items.len) {
                const old_len = self.sparse.items.len;
                try self.sparse.resize(self.allocator, max_id + 1);
                @memset(self.sparse.items[old_len..], null);
            }
            for (entity_ids, 0..) |id, i| {
                if (self.sparse.items[id] == null) {
                    const new_dense_idx: u32 = @intCast(self.dense_ids.items.len);
                    self.dense_ids.appendAssumeCapacity(id);
                    self.dense_values.appendAssumeCapacity(batch_values[i]);
                    self.sparse.items[id] = new_dense_idx;
                } else {
                    self.dense_values.items[self.sparse.items[id].?] = batch_values[i];
                }
            }
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "SparseSet basic operations" {
    const allocator = std.testing.allocator;
    var set = SparseSet(u64).init(allocator);
    defer set.deinit();

    // Insert
    try set.set(5, 100);
    try set.set(10, 200);
    try set.set(3, 300);

    try std.testing.expectEqual(@as(usize, 3), set.count());

    // Get
    try std.testing.expectEqual(@as(?u64, 100), set.get(5));
    try std.testing.expectEqual(@as(?u64, 200), set.get(10));
    try std.testing.expectEqual(@as(?u64, 300), set.get(3));
    try std.testing.expectEqual(@as(?u64, null), set.get(999));

    // Contains
    try std.testing.expect(set.contains(5));
    try std.testing.expect(set.contains(10));
    try std.testing.expect(!set.contains(999));

    // Update
    try set.set(5, 150);
    try std.testing.expectEqual(@as(?u64, 150), set.get(5));
    try std.testing.expectEqual(@as(usize, 3), set.count());
}

test "SparseSet remove with swap-and-pop" {
    const allocator = std.testing.allocator;
    var set = SparseSet(u64).init(allocator);
    defer set.deinit();

    try set.set(1, 10);
    try set.set(2, 20);
    try set.set(3, 30);

    // Remove middle element
    set.remove(2);

    try std.testing.expectEqual(@as(usize, 2), set.count());
    try std.testing.expectEqual(@as(?u64, 10), set.get(1));
    try std.testing.expectEqual(@as(?u64, null), set.get(2));
    try std.testing.expectEqual(@as(?u64, 30), set.get(3));

    // Remove first
    set.remove(1);
    try std.testing.expectEqual(@as(usize, 1), set.count());
    try std.testing.expectEqual(@as(?u64, 30), set.get(3));

    // Remove last
    set.remove(3);
    try std.testing.expect(set.isEmpty());
}

test "SparseSet iteration" {
    const allocator = std.testing.allocator;
    var set = SparseSet(u64).init(allocator);
    defer set.deinit();

    try set.set(100, 1000);
    try set.set(50, 500);
    try set.set(200, 2000);

    var sum: u64 = 0;
    var id_sum: u64 = 0;
    var iter = set.iterator();
    while (iter.next()) |entry| {
        sum += entry.value.*;
        id_sum += entry.id;
    }

    try std.testing.expectEqual(@as(u64, 3500), sum);
    try std.testing.expectEqual(@as(u64, 350), id_sum);
}

test "SparseSet with struct values" {
    const TestStruct = struct {
        x: i32,
        y: i32,
    };

    const allocator = std.testing.allocator;
    var set = SparseSet(TestStruct).init(allocator);
    defer set.deinit();

    try set.set(0, .{ .x = 10, .y = 20 });
    try set.set(5, .{ .x = 50, .y = 60 });

    const val = set.get(0).?;
    try std.testing.expectEqual(@as(i32, 10), val.x);
    try std.testing.expectEqual(@as(i32, 20), val.y);

    // Modify via pointer
    if (set.getPtr(5)) |ptr| {
        ptr.x = 999;
    }
    try std.testing.expectEqual(@as(i32, 999), set.get(5).?.x);
}

test "SparseSet initCapacity" {
    const allocator = std.testing.allocator;
    var set = try SparseSet(u32).initCapacity(allocator, 1000);
    defer set.deinit();

    // Should be able to set IDs up to 999 without growing sparse array
    try set.set(999, 42);
    try std.testing.expectEqual(@as(?u32, 42), set.get(999));

    // Setting beyond capacity should still work (grows automatically)
    try set.set(2000, 84);
    try std.testing.expectEqual(@as(?u32, 84), set.get(2000));
}

test "SparseSet clear" {
    const allocator = std.testing.allocator;
    var set = SparseSet(u32).init(allocator);
    defer set.deinit();

    try set.set(1, 10);
    try set.set(2, 20);
    try set.set(3, 30);

    set.clear();

    try std.testing.expect(set.isEmpty());
    try std.testing.expectEqual(@as(?u32, null), set.get(1));
    try std.testing.expectEqual(@as(?u32, null), set.get(2));
    try std.testing.expectEqual(@as(?u32, null), set.get(3));
}
