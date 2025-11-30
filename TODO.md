### What to do...

- [ ] Seperate reflect.zig into separate repo for general purpose reflection utilities
- [ ] Explore threading when Zig's threading model is more mature
  - Specifically the newer std.Io APIs
- [x] New project repo zevy_raylib using zevy_ecs and raylib-zig
  - Test zevy_ecs in a more real world scenario that helps find bugs and ideas for improvements
- [x] Improve reflect.hasFunc and reflect.verifyFuncArgs to handle pointer types transparently
- [x] Avoid abstracting away relations too much
  - Allow users to work with relations directly when needed through the RelationsManager resource
