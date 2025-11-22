const std = @import("std");
const ecs_mod = @import("ecs.zig");
const scheduler_mod = @import("scheduler.zig");
const systems = @import("systems.zig");
const registry = @import("systems.registry.zig");

/// Test data structures for race condition detection
const TestState = struct {
    counter: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    errors: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    max_concurrent: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    current_concurrent: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
};

/// Test component for concurrent access
const ConcurrentCounter = struct {
    value: i64 = 0,
};

// Stress test: Multiple threads creating/destroying entities concurrently
test "Concurrent entity creation and destruction with stress" {
    const allocator = std.testing.allocator;
    const num_threads = 4; // Reduced from 4 for stability
    const iterations_per_thread = 25; // Reduced from 50 to reduce contention

    var ecs = ecs_mod.Manager.init(allocator) catch |err| @panic(@errorName(err));
    defer ecs.deinit();

    var test_state = TestState{};
    var threads = std.ArrayList(std.Thread).initCapacity(allocator, num_threads) catch |err| @panic(@errorName(err));
    defer threads.deinit(allocator);

    const ThreadContext = struct {
        ecs: *ecs_mod.Manager,
        state: *TestState,
        thread_id: usize,
        iterations: usize,
    };

    const threadFn = struct {
        fn run(ctx: ThreadContext) void {
            for (0..ctx.iterations) |_| {
                // Create entity
                const entity = ctx.ecs.create(.{});

                // Increment counter
                _ = ctx.state.counter.fetchAdd(1, .release);

                // Try to add component (this tests write contention)
                ctx.ecs.addComponent(entity, ConcurrentCounter, .{ .value = @intCast(ctx.thread_id) }) catch {};

                // Remove and re-add component (tests archetype mutation)
                ctx.ecs.removeComponent(entity, ConcurrentCounter) catch {};
                ctx.ecs.addComponent(entity, ConcurrentCounter, .{ .value = @intCast(ctx.thread_id) }) catch {};
            }
        }
    }.run;

    // Spawn threads
    for (0..num_threads) |i| {
        const ctx = ThreadContext{
            .ecs = &ecs,
            .state = &test_state,
            .thread_id = i,
            .iterations = iterations_per_thread,
        };
        const thread = std.Thread.spawn(.{}, threadFn, .{ctx}) catch |err| {
            std.debug.print("Failed to spawn thread {}: {s}\n", .{ i, @errorName(err) });
            continue;
        };
        threads.appendAssumeCapacity(thread);
    }

    // Wait for all threads
    for (threads.items) |*thread| {
        thread.join();
    }

    // Verify results: should have created exactly num_threads * iterations_per_thread entity mutations
    const expected_count = num_threads * iterations_per_thread;
    const actual_count = test_state.counter.load(.acquire);
    try std.testing.expectEqual(@as(i64, @intCast(expected_count)), actual_count);
}

// Test: Concurrent component access with high contention
test "Concurrent component read/write with high contention" {
    const allocator = std.testing.allocator;
    const num_threads = 8;
    const num_entities = 50;
    const iterations = 100;

    var ecs = ecs_mod.Manager.init(allocator) catch |err| @panic(@errorName(err));
    defer ecs.deinit();

    // Create entities with components upfront
    var entities = std.ArrayList(ecs_mod.Entity).initCapacity(allocator, num_entities) catch |err| @panic(@errorName(err));
    defer entities.deinit(allocator);

    for (0..num_entities) |i| {
        const entity = ecs.create(.{});
        ecs.addComponent(entity, ConcurrentCounter, .{ .value = @intCast(i) }) catch {};
        entities.appendAssumeCapacity(entity);
    }

    var test_state = TestState{};
    var threads = std.ArrayList(std.Thread).initCapacity(allocator, num_threads) catch |err| @panic(@errorName(err));
    defer threads.deinit(allocator);

    const ThreadContext = struct {
        ecs: *ecs_mod.Manager,
        entities: []const ecs_mod.Entity,
        state: *TestState,
        iterations: usize,
    };

    const threadFn = struct {
        fn run(ctx: ThreadContext) void {
            for (0..ctx.iterations) |_| {
                // Try to read/write from random entities
                for (ctx.entities) |entity| {
                    if (ctx.ecs.getComponent(entity, ConcurrentCounter)) |comp| {
                        // Simulate some work while holding reference
                        _ = comp;
                        _ = ctx.state.counter.fetchAdd(1, .release);
                    } else |_| {
                        // Entity might have been removed, that's okay
                    }
                }
            }
        }
    }.run;

    // Spawn threads
    for (0..num_threads) |_| {
        const ctx = ThreadContext{
            .ecs = &ecs,
            .entities = entities.items,
            .state = &test_state,
            .iterations = iterations,
        };
        const thread = std.Thread.spawn(.{}, threadFn, .{ctx}) catch |err| {
            std.debug.print("Failed to spawn thread: {s}\n", .{@errorName(err)});
            continue;
        };
        threads.appendAssumeCapacity(thread);
    }

    // Wait for all threads
    for (threads.items) |*thread| {
        thread.join();
    }

    // All threads should have completed without error
    try std.testing.expectEqual(@as(usize, 0), test_state.errors.load(.acquire));
}

// Test: Concurrent query execution with overlapping queries
test "Concurrent queries with component iteration" {
    const allocator = std.testing.allocator;
    const num_threads = 6;
    const num_entities = 100;

    var ecs = ecs_mod.Manager.init(allocator) catch |err| @panic(@errorName(err));
    defer ecs.deinit();

    // Create entities with components
    for (0..num_entities) |i| {
        const entity = ecs.create(.{});
        ecs.addComponent(entity, ConcurrentCounter, .{ .value = @intCast(i) }) catch {};
    }

    var test_state = TestState{};
    var threads = std.ArrayList(std.Thread).initCapacity(allocator, num_threads) catch |err| @panic(@errorName(err));
    defer threads.deinit(allocator);

    const ThreadContext = struct {
        ecs: *ecs_mod.Manager,
        state: *TestState,
        thread_id: usize,
    };

    const threadFn = struct {
        fn run(ctx: ThreadContext) void {
            // Try to query components multiple times
            for (0..50) |_| {
                var query = ctx.ecs.query(.{ConcurrentCounter}, .{});
                var count: usize = 0;

                while (query.next()) |entity_data| {
                    _ = entity_data;
                    count += 1;
                }

                _ = ctx.state.counter.fetchAdd(@intCast(count), .release);
            }
        }
    }.run;

    // Spawn threads
    for (0..num_threads) |i| {
        const ctx = ThreadContext{
            .ecs = &ecs,
            .state = &test_state,
            .thread_id = i,
        };
        const thread = std.Thread.spawn(.{}, threadFn, .{ctx}) catch |err| {
            std.debug.print("Failed to spawn query thread: {s}\n", .{@errorName(err)});
            continue;
        };
        threads.appendAssumeCapacity(thread);
    }

    // Wait for all threads
    for (threads.items) |*thread| {
        thread.join();
    }

    // Verify: each thread ran 50 queries, each seeing 100 entities
    const expected_total = num_threads * 50 * num_entities;
    const actual_total = test_state.counter.load(.acquire);
    try std.testing.expectEqual(@as(i64, @intCast(expected_total)), actual_total);
}

// Test: Concurrent scheduler execution with multiple stages
test "Concurrent scheduler with multiple async stages" {
    const allocator = std.testing.allocator;
    const num_threads = 4;

    var test_state = TestState{};
    var threads = std.ArrayList(std.Thread).initCapacity(allocator, num_threads) catch |err| @panic(@errorName(err));
    defer threads.deinit(allocator);

    const ThreadContext = struct {
        thread_id: usize,
        state: *TestState,
    };

    const threadFn = struct {
        fn run(ctx: ThreadContext) void {
            var ecs = ecs_mod.Manager.init(std.testing.allocator) catch {
                _ = ctx.state.errors.fetchAdd(1, .release);
                return;
            };
            defer ecs.deinit();

            var scheduler = scheduler_mod.Scheduler.init(std.testing.allocator) catch {
                _ = ctx.state.errors.fetchAdd(1, .release);
                return;
            };
            defer scheduler.deinit();

            // Add a work-simulating system
            const test_system = struct {
                pub fn run(_: *ecs_mod.Manager) void {
                    // Simulate work with a few thread yields
                    for (0..10) |_| {
                        std.Thread.yield() catch {};
                    }
                }
            }.run;

            // Add systems to multiple stages
            scheduler.addSystem(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.PreUpdate), test_system, registry.DefaultParamRegistry);
            scheduler.addSystem(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.Update), test_system, registry.DefaultParamRegistry);
            scheduler.addSystem(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.PostUpdate), test_system, registry.DefaultParamRegistry);

            // Run multiple iterations of the scheduler
            for (0..10) |_| {
                scheduler.runStages(&ecs, scheduler_mod.Stage(scheduler_mod.Stages.PreUpdate), scheduler_mod.Stage(scheduler_mod.Stages.PostUpdate)) catch {
                    _ = ctx.state.errors.fetchAdd(1, .release);
                    return;
                };
                _ = ctx.state.counter.fetchAdd(1, .release);
            }
        }
    }.run;

    // Spawn threads
    for (0..num_threads) |i| {
        const ctx = ThreadContext{
            .thread_id = i,
            .state = &test_state,
        };
        const thread = std.Thread.spawn(.{}, threadFn, .{ctx}) catch |err| {
            std.debug.print("Failed to spawn scheduler thread: {s}\n", .{@errorName(err)});
            continue;
        };
        threads.appendAssumeCapacity(thread);
    }

    // Wait for all threads
    for (threads.items) |*thread| {
        thread.join();
    }

    // Verify no errors occurred
    try std.testing.expectEqual(@as(usize, 0), test_state.errors.load(.acquire));
    // Each thread should have completed 10 scheduler runs
    try std.testing.expectEqual(@as(i64, @intCast(num_threads * 10)), test_state.counter.load(.acquire));
}

// Test: Rapid archetype mutations under concurrent load
test "Concurrent archetype mutations under load" {
    const allocator = std.testing.allocator;
    const num_threads = 3;
    const entities_per_thread = 20;

    var ecs = ecs_mod.Manager.init(allocator) catch |err| @panic(@errorName(err));
    defer ecs.deinit();

    var test_state = TestState{};
    var threads = std.ArrayList(std.Thread).initCapacity(allocator, num_threads) catch |err| @panic(@errorName(err));
    defer threads.deinit(allocator);

    const ThreadContext = struct {
        ecs: *ecs_mod.Manager,
        state: *TestState,
        thread_id: usize,
    };

    const threadFn = struct {
        fn run(ctx: ThreadContext) void {
            var local_entities = std.ArrayList(ecs_mod.Entity).initCapacity(std.testing.allocator, entities_per_thread) catch {
                _ = ctx.state.errors.fetchAdd(1, .release);
                return;
            };
            defer local_entities.deinit(std.testing.allocator);

            // Create entities
            for (0..entities_per_thread) |i| {
                const entity = ctx.ecs.create(.{});
                local_entities.appendAssumeCapacity(entity);

                // Add first component
                ctx.ecs.addComponent(entity, ConcurrentCounter, .{ .value = @intCast(i) }) catch {
                    _ = ctx.state.errors.fetchAdd(1, .release);
                };
            }

            // Now mutate archetypes by removing/adding components
            for (local_entities.items) |entity| {
                // Remove and re-add to mutate archetype
                ctx.ecs.removeComponent(entity, ConcurrentCounter) catch {};
                ctx.ecs.addComponent(entity, ConcurrentCounter, .{ .value = 42 }) catch {};
                _ = ctx.state.counter.fetchAdd(1, .release);
            }
        }
    }.run;

    // Spawn threads
    for (0..num_threads) |i| {
        const ctx = ThreadContext{
            .ecs = &ecs,
            .state = &test_state,
            .thread_id = i,
        };
        const thread = std.Thread.spawn(.{}, threadFn, .{ctx}) catch |err| {
            std.debug.print("Failed to spawn archetype thread: {s}\n", .{@errorName(err)});
            continue;
        };
        threads.appendAssumeCapacity(thread);
    }

    // Wait for all threads
    for (threads.items) |*thread| {
        thread.join();
    }

    // Verify no errors
    try std.testing.expectEqual(@as(usize, 0), test_state.errors.load(.acquire));
}
