const std = @import("std");
const zevy_ecs = @import("src/root.zig");

// ============================================================================
// Components
// ============================================================================

const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: []const u8,
    body: []const u8,
    timestamp: i64,
};

const Response = struct {
    status: u16 = 200,
    content_type: []const u8 = "text/html",
    body: []const u8,
    sent: bool = false,
};

const Session = struct {
    id: []const u8,
    user_id: ?u32 = null,
    created_at: i64,
    last_accessed: i64,
    data: std.StringHashMap([]const u8),
};

const RouteMatch = struct {
    handler_name: []const u8,
};

const AuthToken = struct {
    token: []const u8,
    user_id: u32,
    expires_at: i64,
};

const RateLimit = struct {
    requests_count: u32 = 0,
    window_start: i64,
    max_requests: u32 = 100,
    window_seconds: i64 = 60,
};

// ============================================================================
// Events
// ============================================================================

const RequestEvent = struct {
    entity: zevy_ecs.Entity,
    path: []const u8,
};

const ResponseSentEvent = struct {
    entity: zevy_ecs.Entity,
    status: u16,
    duration_ms: i64,
};

const AuthFailedEvent = struct {
    entity: zevy_ecs.Entity,
    reason: []const u8,
};

// ============================================================================
// Resources
// ============================================================================

const ServerConfig = struct {
    port: u16,
    host: []const u8,
    max_connections: u32,
    request_timeout_ms: i64,
};

const ServerStats = struct {
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    active_connections: u32 = 0,
    uptime_seconds: i64 = 0,
};

const RouteRegistry = struct {
    routes: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) RouteRegistry {
        return .{ .routes = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn register(self: *RouteRegistry, path: []const u8, handler: []const u8) !void {
        try self.routes.put(path, handler);
    }

    pub fn match(self: *RouteRegistry, path: []const u8) ?[]const u8 {
        return self.routes.get(path);
    }

    pub fn deinit(self: *RouteRegistry) void {
        self.routes.deinit();
    }
};

const SessionStore = struct {
    sessions: std.StringHashMap(Session),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SessionStore {
        return .{
            .sessions = std.StringHashMap(Session).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn create(self: *SessionStore, session_id: []const u8, timestamp: i64) !void {
        const session = Session{
            .id = session_id,
            .created_at = timestamp,
            .last_accessed = timestamp,
            .data = std.StringHashMap([]const u8).init(self.allocator),
        };
        try self.sessions.put(session_id, session);
    }

    pub fn get(self: *SessionStore, session_id: []const u8) ?*Session {
        return self.sessions.getPtr(session_id);
    }

    pub fn deinit(self: *SessionStore) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.data.deinit();
        }
        self.sessions.deinit();
    }
};

const CurrentTime = struct {
    timestamp: i64,
};

// ============================================================================
// Application States
// ============================================================================

const ServerState = enum {
    Starting,
    Running,
    ShuttingDown,
    Stopped,
};

// ============================================================================
// Systems
// ============================================================================

/// Startup system to initialize server resources
fn startupSystem(
    config: zevy_ecs.Res(ServerConfig),
) !void {
    std.debug.print("🚀 Server starting on {s}:{d}\n", .{ config.ptr.host, config.ptr.port });
    std.debug.print("📊 Max connections: {d}\n", .{config.ptr.max_connections});
}

/// System to count all incoming requests
fn requestCountingSystem(
    stats: zevy_ecs.Res(ServerStats),
    query: zevy_ecs.Query(
        struct {
            request: Request,
        },
        .{},
    ),
) void {
    var count: usize = 0;
    while (query.next()) |_| {
        count += 1;
    }
    stats.ptr.total_requests = @intCast(count);
}

/// System to route incoming requests to appropriate handlers
fn routingSystem(
    commands: *zevy_ecs.Commands,
    routes: zevy_ecs.Res(RouteRegistry),
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
        },
        .{RouteMatch},
    ),
    writer: zevy_ecs.EventWriter(RequestEvent),
) void {
    while (query.next()) |item| {
        if (routes.ptr.match(item.request.path)) |handler| {
            // Add route match component
            commands.addComponent(item.entity, RouteMatch, .{
                .handler_name = handler,
            }) catch continue;

            // Emit request event
            writer.write(.{
                .entity = item.entity,
                .path = item.request.path,
            });
        } else {
            // No route matched - add 404 response
            const body_text = std.fmt.allocPrint(commands.allocator, "404 Not Found: The requested path '{s}' is gone...", .{item.request.path}) catch "404 Not Found";

            commands.addComponent(item.entity, Response, .{
                .status = 404,
                .content_type = "text/plain",
                .body = body_text,
                .sent = false,
            }) catch {};
        }
    }
}

/// Authentication middleware system
fn authenticationSystem(
    commands: *zevy_ecs.Commands,
    sessions: zevy_ecs.Res(SessionStore),
    time: zevy_ecs.Res(CurrentTime),
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
            route: RouteMatch,
        },
        .{AuthToken},
    ),
    auth_failed_writer: zevy_ecs.EventWriter(AuthFailedEvent),
) void {
    while (query.next()) |item| {
        // Check if route requires authentication
        if (std.mem.startsWith(u8, item.request.path, "/api/protected")) {
            // Look for session cookie in headers string
            if (std.mem.indexOf(u8, item.request.headers, "session_id=")) |idx| {
                const session_start = idx + 11;
                const session_end = std.mem.indexOfPos(u8, item.request.headers, session_start, ";") orelse item.request.headers.len;
                const session_id = item.request.headers[session_start..session_end];

                if (sessions.ptr.get(session_id)) |session| {
                    // Update last accessed time
                    session.last_accessed = time.ptr.timestamp;

                    if (session.user_id) |user_id| {
                        // Add auth token component
                        commands.addComponent(item.entity, AuthToken, .{
                            .token = session.id,
                            .user_id = user_id,
                            .expires_at = session.created_at + 3600000, // 1 hour
                        }) catch continue;
                        continue;
                    }
                }
            }

            // Authentication failed
            auth_failed_writer.write(.{
                .entity = item.entity,
                .reason = "No valid session",
            });
        }
    }
}

/// Rate limiting middleware system
fn rateLimitingSystem(
    commands: *zevy_ecs.Commands,
    time: zevy_ecs.Res(CurrentTime),
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
        },
        .{},
    ),
) void {
    while (query.next()) |item| {
        // Try to get existing rate limit component or create new one
        const rate_limit = commands.getComponent(item.entity, RateLimit) catch null;

        if (rate_limit) |rl| {
            const window_elapsed = time.ptr.timestamp - rl.window_start;

            if (window_elapsed > rl.window_seconds * 1000) {
                // Reset window
                rl.requests_count = 1;
                rl.window_start = time.ptr.timestamp;
            } else {
                rl.requests_count += 1;

                if (rl.requests_count > rl.max_requests) {
                    // Rate limit exceeded - set response
                    commands.addComponent(item.entity, Response, .{
                        .status = 429,
                        .content_type = "text/plain",
                        .body = "Rate limit exceeded",
                        .sent = false,
                    }) catch {};
                }
            }
        } else {
            // First request from this source
            commands.addComponent(item.entity, RateLimit, .{
                .requests_count = 1,
                .window_start = time.ptr.timestamp,
                .max_requests = 100,
                .window_seconds = 60,
            }) catch {};
        }
    }
}

/// Request handler system for home page
fn homeHandlerSystem(
    commands: *zevy_ecs.Commands,
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
            route: RouteMatch,
        },
        .{Response},
    ),
) void {
    while (query.next()) |item| {
        if (std.mem.eql(u8, item.route.handler_name, "home")) {
            // Create response
            const body_text =
                \\<!DOCTYPE html>
                \\<html>
                \\<head><title>Welcome</title></head>
                \\<body>
                \\  <h1>Welcome to zevy_ecs Web Server!</h1>
                \\  <p>Request method: GET</p>
                \\</body>
                \\</html>
            ;

            commands.addComponent(item.entity, Response, .{
                .status = 200,
                .content_type = "text/html",
                .body = body_text,
                .sent = false,
            }) catch {};
        }
    }
}

/// API handler system for user data
fn apiUserHandlerSystem(
    commands: *zevy_ecs.Commands,
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
            route: RouteMatch,
            auth: AuthToken,
        },
        .{Response},
    ),
) void {
    while (query.next()) |item| {
        if (std.mem.eql(u8, item.route.handler_name, "api_user")) {
            const body_text = std.fmt.allocPrint(commands.allocator,
                \\{{"user_id": {d}, "authenticated": true, "token": "{s}"}}
            , .{ item.auth.user_id, item.auth.token }) catch "{}";

            commands.addComponent(item.entity, Response, .{
                .status = 200,
                .content_type = "application/json",
                .body = body_text,
                .sent = false,
            }) catch {};
        }
    }
}

/// Response sending system
fn responseSendingSystem(
    commands: *zevy_ecs.Commands,
    stats: zevy_ecs.Res(ServerStats),
    time: zevy_ecs.Res(CurrentTime),
    query: zevy_ecs.Query(
        struct {
            entity: zevy_ecs.Entity,
            request: Request,
            response: Response,
        },
        .{},
    ),
    writer: zevy_ecs.EventWriter(ResponseSentEvent),
) void {
    while (query.next()) |item| {
        if (!item.response.sent) {
            // Simulate sending response
            const duration = time.ptr.timestamp - item.request.timestamp;

            std.debug.print("📤 {s} {s} -> {d} ({d}ms)\n", .{
                item.request.method,
                item.request.path,
                item.response.status,
                duration,
            });

            // Update success/failure stats (total_requests is counted by requestCountingSystem)
            if (item.response.status < 400) {
                stats.ptr.successful_requests += 1;
            } else {
                stats.ptr.failed_requests += 1;
            }

            // Mark response as sent
            item.response.sent = true;

            // Emit event
            writer.write(.{
                .entity = item.entity,
                .status = item.response.status,
                .duration_ms = duration,
            });

            // Clean up request entity after sending
            commands.destroyEntity(item.entity) catch {};
        }
    }
}

/// System to handle authentication failures
fn authFailureHandlerSystem(
    commands: *zevy_ecs.Commands,
    reader: zevy_ecs.EventReader(AuthFailedEvent),
) void {
    while (reader.read()) |event| {
        std.debug.print("🔒 Auth failed for entity {d}: {s}\n", .{
            event.data.entity.id,
            event.data.reason,
        });

        // Add 401 response
        const body_text = std.fmt.allocPrint(commands.allocator,
            \\{{"error": "Unauthorized", "reason": "{s}"}}
        , .{event.data.reason}) catch "{}";

        _ = commands.addComponent(event.data.entity, Response, .{
            .status = 401,
            .content_type = "application/json",
            .body = body_text,
            .sent = false,
        }) catch {};

        event.handled = true;
    }
}

/// Stats display system
fn statsDisplaySystem(
    stats: zevy_ecs.Res(ServerStats),
) void {
    std.debug.print("\n📊 Server Stats:\n", .{});
    std.debug.print("   Total requests: {d}\n", .{stats.ptr.total_requests});
    std.debug.print("   Successful: {d}\n", .{stats.ptr.successful_requests});
    std.debug.print("   Failed: {d}\n", .{stats.ptr.failed_requests});
    std.debug.print("   Active connections: {d}\n", .{stats.ptr.active_connections});
    const success_rate = if (stats.ptr.total_requests > 0)
        @as(f64, @floatFromInt(stats.ptr.successful_requests)) / @as(f64, @floatFromInt(stats.ptr.total_requests)) * 100.0
    else
        0.0;
    std.debug.print("   Success rate: {d:.1}%\n\n", .{success_rate});
}

/// Cleanup system for expired sessions
fn sessionCleanupSystem(
    sessions: zevy_ecs.Res(SessionStore),
    time: zevy_ecs.Res(CurrentTime),
) void {
    var to_remove = std.ArrayList([]const u8).initCapacity(sessions.ptr.allocator, 0) catch return;
    defer to_remove.deinit(sessions.ptr.allocator);

    var it = sessions.ptr.sessions.iterator();
    while (it.next()) |entry| {
        const age = time.ptr.timestamp - entry.value_ptr.last_accessed;
        if (age > 3600000) { // 1 hour
            to_remove.append(sessions.ptr.allocator, entry.key_ptr.*) catch continue;
        }
    }

    for (to_remove.items) |session_id| {
        if (sessions.ptr.sessions.fetchRemove(session_id)) |removed| {
            var mutable_data = removed.value.data;
            mutable_data.deinit();
            std.debug.print("🧹 Cleaned up expired session: {s}\n", .{session_id});
        }
    }
}

// ============================================================================
// Main Application
// ============================================================================

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var manager = try zevy_ecs.Manager.init(allocator);
    defer manager.deinit();

    var scheduler = try zevy_ecs.Scheduler.init(allocator);
    defer scheduler.deinit();

    // Initialize resources
    _ = try manager.addResource(ServerConfig, .{
        .port = 8080,
        .host = "localhost",
        .max_connections = 1000,
        .request_timeout_ms = 30000,
    });

    _ = try manager.addResource(ServerStats, .{});

    var routes = RouteRegistry.init(allocator);
    try routes.register("/", "home");
    try routes.register("/api/user", "api_user");
    _ = try manager.addResource(RouteRegistry, routes);

    var sessions = try manager.addResource(SessionStore, SessionStore.init(allocator));

    _ = try manager.addResource(CurrentTime, .{ .timestamp = std.time.milliTimestamp() });

    // Register events
    try scheduler.registerEvent(&manager, RequestEvent, zevy_ecs.DefaultParamRegistry);
    try scheduler.registerEvent(&manager, ResponseSentEvent, zevy_ecs.DefaultParamRegistry);
    try scheduler.registerEvent(&manager, AuthFailedEvent, zevy_ecs.DefaultParamRegistry);

    // Register state
    try scheduler.registerState(&manager, ServerState);
    try scheduler.transitionTo(&manager, ServerState, .Starting);

    // Add systems to scheduler stages
    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Startup),
        startupSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.First),
        requestCountingSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.First),
        routingSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate),
        authenticationSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.PreUpdate),
        rateLimitingSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        homeHandlerSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        apiUserHandlerSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Update),
        authFailureHandlerSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.PostUpdate),
        responseSendingSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    scheduler.addSystem(
        &manager,
        zevy_ecs.Stage(zevy_ecs.Stages.Last),
        sessionCleanupSystem,
        zevy_ecs.DefaultParamRegistry,
    );

    // Startup
    try scheduler.runStage(&manager, zevy_ecs.Stage(zevy_ecs.Stages.Startup));
    try scheduler.transitionTo(&manager, ServerState, .Running);

    // Simulate incoming requests
    std.debug.print("\n🌐 Simulating incoming requests...\n\n", .{});

    // Create session for authenticated user
    try sessions.create("sess_12345", std.time.milliTimestamp());
    if (sessions.get("sess_12345")) |session| {
        session.user_id = 42;
    }

    // Request 1: Home page
    {
        _ = manager.create(.{
            Request{
                .method = "GET",
                .path = "/",
                .headers = "User-Agent: Mozilla/5.0",
                .body = "",
                .timestamp = std.time.milliTimestamp(),
            },
        });
    }

    // Request 2: API endpoint with authentication
    {
        _ = manager.create(.{
            Request{
                .method = "GET",
                .path = "/api/protected/user",
                .headers = "User-Agent: Mozilla/5.0; Cookie: session_id=sess_12345",
                .body = "Me hacker!!",
                .timestamp = std.time.milliTimestamp(),
            },
        });
    }

    // Request 3: Unauthenticated API request
    {
        _ = manager.create(.{
            Request{
                .method = "GET",
                .path = "/api/protected/data",
                .headers = "User-Agent: Mozilla/5.0",
                .body = "Ur data R belong 2 Us",
                .timestamp = std.time.milliTimestamp(),
            },
        });
    }

    // Process requests through pipeline
    try scheduler.runStages(&manager, zevy_ecs.Stage(zevy_ecs.Stages.First), zevy_ecs.Stage(zevy_ecs.Stages.Last));

    // Display stats
    statsDisplaySystem(.{ .ptr = manager.getResource(ServerStats).? });

    // Shutdown
    try scheduler.transitionTo(&manager, ServerState, .ShuttingDown);
    std.debug.print("👋 Server shutting down...\n", .{});
    try scheduler.transitionTo(&manager, ServerState, .Stopped);
}
