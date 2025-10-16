const std = @import("std");

/// A generic event store that maintains events in a queue-like structure
/// while allowing iteration without consuming events.
/// Internally uses a ring buffer for efficient operations.
pub fn EventStore(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Wrapper for events that tracks handling status
        pub const Event = struct {
            data: T,
            handled: bool = false,
        };

        /// Iterator for non-consuming access to events
        pub const Iterator = struct {
            store: *Self,
            index: usize,

            pub fn next(self: *Iterator) ?*Event {
                if (self.index >= self.store.len) return null;
                const wrapper = &self.store.events.items[self.store.getActualIndex(self.index)];
                self.index += 1;
                return wrapper;
            }

            pub fn markHandled(self: *Iterator) void {
                if (self.index > 0 and self.index <= self.store.len) {
                    const actual_index = self.store.getActualIndex(self.index - 1);
                    self.store.events.items[actual_index].handled = true;
                }
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        allocator: std.mem.Allocator,
        events: std.ArrayList(Event),
        head: usize, // Index of oldest event
        tail: usize, // Index where next event will be added
        len: usize, // Number of events currently stored
        capacity: usize,

        /// Initialize a new EventStore with the given capacity
        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) Self {
            return Self{
                .allocator = allocator,
                .events = std.ArrayList(Event).initCapacity(allocator, initial_capacity) catch |err| @panic(@errorName(err)),
                .head = 0,
                .tail = 0,
                .len = 0,
                .capacity = initial_capacity,
            };
        }

        /// Deinitialize the EventStore and free all memory
        pub fn deinit(self: *Self) void {
            self.events.deinit(self.allocator);
        }

        /// Add an event to the store (enqueue)
        pub fn push(self: *Self, event: T) void {
            // If we're at capacity, we need to grow
            if (self.len == self.capacity) {
                // Calculate new capacity
                const new_capacity = self.capacity * 2;

                // Create new array with proper size
                var new_events = std.ArrayList(Event).initCapacity(self.allocator, new_capacity) catch |err| @panic(@errorName(err));

                // Copy existing events in order
                for (0..self.len) |i| {
                    const src_idx = self.getActualIndex(i);
                    new_events.append(self.allocator, self.events.items[src_idx]) catch |err| {
                        new_events.deinit(self.allocator);
                        @panic(@errorName(err));
                    };
                }

                // Replace the old array
                self.events.deinit(self.allocator);
                self.events = new_events;

                // Reset indices since we're now contiguous
                self.head = 0;
                self.tail = self.len;
                self.capacity = new_capacity;
            }

            // Add the new event at the tail position
            self.events.append(self.allocator, Event{ .data = event, .handled = false }) catch |err| @panic(@errorName(err));
            self.tail = (self.tail + 1) % self.capacity;
            self.len += 1;
        }

        /// Remove and return the oldest event (dequeue)
        pub fn pop(self: *Self) ?Event {
            if (self.len == 0) return null;

            const wrapper = self.events.items[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.len -= 1;
            return wrapper;
        }

        /// Get the oldest event without removing it
        pub fn peek(self: *Self) ?*const Event {
            if (self.len == 0) return null;
            return &self.events.items[self.head];
        }

        /// Check if the store is empty
        pub fn isEmpty(self: *Self) bool {
            return self.len == 0;
        }

        /// Get the number of events currently stored
        pub fn count(self: *Self) usize {
            return self.len;
        }

        /// Get the current capacity
        pub fn getCapacity(self: *Self) usize {
            return self.capacity;
        }

        /// Clear all events from the store
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.len = 0;
        }

        /// Discard all handled events, keeping only unhandled ones
        /// This is typically called at the end of a frame to clean up consumed events
        pub fn discardHandled(self: *Self) void {
            if (self.len == 0) return;

            var write_index: usize = 0;
            var read_index: usize = 0;

            // Iterate through all events and keep only unhandled ones
            while (read_index < self.len) {
                const actual_read_idx = self.getActualIndex(read_index);
                if (!self.events.items[actual_read_idx].handled) {
                    // Move unhandled event to the write position
                    if (write_index != read_index) {
                        const actual_write_idx = self.getActualIndex(write_index);
                        self.events.items[actual_write_idx] = self.events.items[actual_read_idx];
                    }
                    write_index += 1;
                }
                read_index += 1;
            }

            // Update the queue state
            self.len = write_index;
            if (self.len == 0) {
                self.head = 0;
                self.tail = 0;
            } else {
                self.head = self.getActualIndex(0);
                self.tail = self.getActualIndex(self.len);
            }
        }

        /// Create an iterator for non-consuming access to all events
        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .store = self,
                .index = 0,
            };
        }

        /// Get a slice of all events in order (oldest first) without consuming
        /// Note: This creates a temporary allocation that must be freed by the caller
        pub fn getAllEvents(self: *Self) []Event {
            if (self.len == 0) return &[_]Event{};

            var result = self.allocator.alloc(Event, self.len) catch |err| @panic(@errorName(err));
            for (0..self.len) |i| {
                result[i] = self.events.items[self.getActualIndex(i)];
            }
            return result;
        }

        /// Internal helper to get the actual array index for a logical index
        fn getActualIndex(self: *const Self, logical_index: usize) usize {
            return (self.head + logical_index) % self.capacity;
        }

        /// Shrink the capacity to fit current usage
        pub fn shrinkToFit(self: *Self) void {
            if (self.len == 0) {
                self.events.shrinkAndFree(self.allocator, 0);
                self.capacity = 0;
                self.head = 0;
                self.tail = 0;
                return;
            }

            // Create a new array with just the current events
            var new_events = std.ArrayList(Event).initCapacity(self.allocator, self.len) catch |err| @panic(@errorName(err));
            var iter = self.iterator();
            while (iter.next()) |wrapper| {
                new_events.append(self.allocator, wrapper.*) catch |err| {
                    new_events.deinit(self.allocator);
                    @panic(@errorName(err));
                };
            }

            self.events.deinit(self.allocator);
            self.events = new_events;
            self.capacity = self.len;
            self.head = 0;
            self.tail = self.len;
        }
    };
}

// Example usage and tests
test "EventStore basic operations" {
    const allocator = std.testing.allocator;

    var store = EventStore(i32).init(allocator, 4);
    defer store.deinit();

    // Test empty store
    try std.testing.expect(store.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), store.count());

    // Add some events
    store.push(1);
    store.push(2);
    store.push(3);

    try std.testing.expect(!store.isEmpty());
    try std.testing.expectEqual(@as(usize, 3), store.count());

    // Peek at oldest
    if (store.peek()) |wrapper| {
        try std.testing.expectEqual(@as(i32, 1), wrapper.data);
        try std.testing.expectEqual(false, wrapper.handled);
    }

    // Iterate without consuming
    var iter = store.iterator();
    var count: usize = 0;
    while (iter.next()) |wrapper| {
        count += 1;
        try std.testing.expect(wrapper.data >= 1 and wrapper.data <= 3);
        try std.testing.expectEqual(false, wrapper.handled);
    }
    try std.testing.expectEqual(@as(usize, 3), count);

    // Iterator should be reusable
    iter.reset();
    count = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);

    // Pop events
    if (store.pop()) |wrapper| {
        try std.testing.expectEqual(@as(i32, 1), wrapper.data);
        try std.testing.expectEqual(false, wrapper.handled);
    }
    if (store.pop()) |wrapper| {
        try std.testing.expectEqual(@as(i32, 2), wrapper.data);
        try std.testing.expectEqual(false, wrapper.handled);
    }

    try std.testing.expectEqual(@as(usize, 1), store.count());

    // Clear and verify
    store.clear();
    try std.testing.expect(store.isEmpty());
}

test "EventStore capacity growth" {
    const allocator = std.testing.allocator;

    var store = EventStore(u8).init(allocator, 2);
    defer store.deinit();

    // Fill to capacity
    store.push(10);
    store.push(20);
    try std.testing.expectEqual(@as(usize, 2), store.count());

    // Add one more - should grow capacity
    store.push(30);
    try std.testing.expectEqual(@as(usize, 3), store.count());
    try std.testing.expect(store.getCapacity() >= 3);

    // Verify all events are accessible
    var iter = store.iterator();
    const values = [_]u8{ 10, 20, 30 };
    var i: usize = 0;
    while (iter.next()) |wrapper| {
        try std.testing.expectEqual(values[i], wrapper.data);
        try std.testing.expectEqual(false, wrapper.handled);
        i += 1;
    }
}

test "EventStore getAllEvents" {
    const allocator = std.testing.allocator;

    var store = EventStore(u32).init(allocator, 3);
    defer store.deinit();

    store.push(100);
    store.push(200);
    store.push(300);

    const wrappers = store.getAllEvents();
    defer allocator.free(wrappers);

    try std.testing.expectEqual(@as(usize, 3), wrappers.len);
    try std.testing.expectEqual(@as(u32, 100), wrappers[0].data);
    try std.testing.expectEqual(@as(u32, 200), wrappers[1].data);
    try std.testing.expectEqual(@as(u32, 300), wrappers[2].data);
    try std.testing.expectEqual(false, wrappers[0].handled);
    try std.testing.expectEqual(false, wrappers[1].handled);
    try std.testing.expectEqual(false, wrappers[2].handled);

    // Verify events weren't consumed
    try std.testing.expectEqual(@as(usize, 3), store.count());
}

test "EventStore mark handled and discard handled" {
    const allocator = std.testing.allocator;

    var store = EventStore(u8).init(allocator, 4);
    defer store.deinit();

    // Add some events
    store.push(1);
    store.push(2);
    store.push(3);
    store.push(4);

    try std.testing.expectEqual(@as(usize, 4), store.count());

    // Mark some events as handled during iteration
    var iter = store.iterator();
    var handled_count: usize = 0;
    while (iter.next()) |wrapper| {
        if (wrapper.data == 2 or wrapper.data == 4) {
            iter.markHandled();
            handled_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), handled_count);

    // Discard handled events (consumes them)
    store.discardHandled();

    // Should only have 2 events left (the unhandled ones: 1 and 3)
    try std.testing.expectEqual(@as(usize, 2), store.count());

    // Verify the remaining events are the unhandled ones
    var remaining_values = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer remaining_values.deinit(allocator);

    iter.reset();
    while (iter.next()) |wrapper| {
        try remaining_values.append(allocator, wrapper.data);
        try std.testing.expect(!wrapper.handled);
    }

    try std.testing.expectEqual(@as(usize, 2), remaining_values.items.len);
    // The order might be different due to the discard operation, so just check they exist
    var has_1 = false;
    var has_3 = false;
    for (remaining_values.items) |val| {
        if (val == 1) has_1 = true;
        if (val == 3) has_3 = true;
    }
    try std.testing.expect(has_1);
    try std.testing.expect(has_3);
}

test "EventReader and EventWriter usage" {
    const allocator = std.testing.allocator;

    // Local definitions for testing (normally imported from systems.zig)
    const TestEventReader = struct {
        event_store: *EventStore(u32),

        pub fn iter(self: *@This()) EventStore(u32).Iterator {
            return self.event_store.iterator();
        }

        pub fn len(self: *@This()) usize {
            return self.event_store.count();
        }

        pub fn isEmpty(self: *@This()) bool {
            return self.event_store.isEmpty();
        }
    };

    const TestEventWriter = struct {
        event_store: *EventStore(u32),

        pub fn send(self: *@This(), event: u32) !void {
            self.event_store.push(event);
        }

        pub fn len(self: *@This()) usize {
            return self.event_store.count();
        }
    };

    // Create an EventStore as a resource
    var event_store = EventStore(u32).init(allocator, 4);
    defer event_store.deinit();

    // Simulate EventReader usage
    var reader = TestEventReader{ .event_store = &event_store };
    try std.testing.expect(reader.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), reader.len());

    // Add events via EventWriter
    var writer = TestEventWriter{ .event_store = &event_store };
    try writer.send(100);
    try writer.send(200);
    try writer.send(300);

    try std.testing.expect(!reader.isEmpty());
    try std.testing.expectEqual(@as(usize, 3), reader.len());
    try std.testing.expectEqual(@as(usize, 3), writer.len());

    // Read events using iterator
    var iter = reader.iter();
    var count: usize = 0;
    while (iter.next()) |wrapper| {
        try std.testing.expect(wrapper.data >= 100 and wrapper.data <= 300);
        try std.testing.expectEqual(false, wrapper.handled);
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);

    // Mark events as handled during iteration
    iter.reset();
    while (iter.next()) |wrapper| {
        if (wrapper.data == 200) {
            iter.markHandled();
        }
    }

    // Discard handled events (consumes them)
    event_store.discardHandled();

    // Should only have the unhandled events (100 and 300) remaining
    try std.testing.expectEqual(@as(usize, 2), reader.len());
    iter.reset();
    var found_100 = false;
    var found_300 = false;
    while (iter.next()) |wrapper| {
        try std.testing.expect(!wrapper.handled);
        if (wrapper.data == 100) found_100 = true;
        if (wrapper.data == 300) found_300 = true;
    }
    try std.testing.expect(found_100);
    try std.testing.expect(found_300);
}
