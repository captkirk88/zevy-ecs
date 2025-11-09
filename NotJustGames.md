## Complete Example: Web Server Application

This example demonstrates how to build a complete web server application using zevy_ecs with request handling, middleware, routing, and session management.

See the full code in [example_web.zig](example_web.zig)

### Key Concepts Demonstrated

1. **Component-Based Architecture**: Requests, responses, sessions, and authentication tokens are all components that can be attached to entities.

2. **System Pipeline**: Multiple systems process requests in stages:

   - Routing → Authentication → Rate Limiting → Handlers → Response Sending

3. **Event-Driven Communication**: Systems communicate via events (RequestEvent, ResponseSentEvent, AuthFailedEvent) for loose coupling.

4. **Resource Management**: Shared state (ServerConfig, ServerStats, RouteRegistry, SessionStore) is managed as resources.

5. **State Management**: Server states (Starting, Running, ShuttingDown, Stopped) control application lifecycle.

6. **Middleware Pattern**: Authentication and rate limiting act as middleware, adding components or modifying requests before handlers process them.

7. **Query-Based Processing**: Systems use queries to efficiently process only entities with relevant components.

8. **Scheduler Stages**: Different stages ensure proper ordering of operations (routing before auth, auth before handling, etc.).

This architecture provides:

- **Flexibility**: Easy to add new routes, middleware, or handlers
- **Performance**: ECS's cache-friendly iteration over components
- **Testability**: Systems are isolated and can be tested independently
- **Modularity**: Each system has a single responsibility
- **Scalability**: Easy to parallelize systems in different stages
