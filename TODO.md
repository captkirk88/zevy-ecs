### What to do...

- [x] Best effort to avoid pointers in system params.
- [x] Improve SystemParam.analyze to make it easier to analyze the type passed in using zevy-reflect or make SystemParam a generic function that can infer the type at compile time rather than having to analyze it at runtime which eliminates the analyze function entirely and simplifies it to just calling apply.
- [x] Commands should have a queue method to enqueue commands to be executed later by the ECS, this would eliminate the need for DeferredFlusher and allow commands to be queued up and executed at a later point in the ECS update loop rather than immediately.
- [x] Commands needs to be opaque, maybe a struct that hides the internal representation and only exposes the API needed to queue commands.
- [x] Modify Res to be const return with only read-lock access and implement a ResMut with Read/Write lock access for mutable access.
- [x] Move setupExamples to zevy-buildtools repo
- [x] Explore threading when Zig's threading model is more mature
  - Specifically the newer std.Io APIs
- [x] Relations doesn't remove the Relations component when all relations are removed from an entity
- [x] Test packed struct components. Should work already...
- [x] New project repo zevy_raylib using zevy_ecs and raylib-zig
  - Test zevy_ecs in a more real world scenario that helps find bugs and ideas for improvements
- [x] Improve reflect.hasFunc and reflect.verifyFuncArgs to handle pointer types transparently (moved to zevy-reflect)
- [x] Avoid abstracting away relations too much
  - Allow users to work with relations directly when needed through the RelationsManager resource

### What might do...

- [x] Seperate reflect.zig into separate repo for general purpose reflection utilities? (done: [zevy-reflect](https://github.com/captkirk88/zevy-reflect))
- [ ] Create a zevy-app repo for a generic App that uses zevy-ecs Scheduler and provides a main loop.
  - This would create a common structure and allow for easier integration with other libraries.
  - It would also allow for better separation of concerns and make it easier to maintain and update the App and Scheduler independently.
  - The Scheduler currently only takes a zevy_ecs.Manager, but it could be modified to take a context that by default includes the Manager but can also include other resources as needed. This would allow for more flexibility and make it easier to integrate with other libraries and systems. (This would be a breaking change, so it would be better to do this in a future major release.)

### Will recursively do...

- [x] Deprecated api by the next tag release will be removed.
- [x] Update README.md with any new features or changes.
- [x] Add or amend tests for any new features or changes.
