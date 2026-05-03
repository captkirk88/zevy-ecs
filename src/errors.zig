const std = @import("std");

const Self = @This();

pub const ECSError = error{
    OutOfMemory,
    EntityNotAlive,
    ComponentNotFound,
    ResourceNotFound,
    ResourceAlreadyExists,
    InvalidEntity,
    ComponentAlreadyExists,
};

/// Errors that can occur during system parameter analysis and application
pub const SystemParamError = error{
    /// A system parameter type is not registered in the ParamRegistry
    UnknownSystemParam,
    /// A required resource was not found for a Res() or ResMut() parameter
    ResourceNotFound,
    /// A Single() parameter expected exactly one entity but found none
    SingleComponentNotFound,
    /// A Single() parameter expected exactly one entity but found multiple
    SingleComponentAmbiguous,
    /// Failed to create or access a state manager for State/NextState parameters
    StateManagerNotFound,
    /// Failed to create or access a relations manager
    RelationsManagerNotFound,
    /// Failed during state transition
    StateTransitionFailed,
};

/// Holds all errors collected.
/// Inspect with `hasErrors`, `first`, or `iterator`.
pub const ErrorGroup = struct {
    buf: [capacity]u16,
    len: u8,

    pub const capacity = 64;

    pub const none: ErrorGroup = std.mem.zeroes(ErrorGroup);

    /// Returns true if any system in the stage returned an error.
    pub fn hasErrors(self: *const ErrorGroup) bool {
        return self.len > 0;
    }

    /// Returns the first captured error, or null if there were none.
    pub fn first(self: *const ErrorGroup) ?anyerror {
        if (self.len == 0) return null;
        return @errorFromInt(self.buf[0]);
    }

    pub const Iterator = struct {
        group: *const ErrorGroup,
        idx: u8,

        pub fn next(self: *Iterator) ?anyerror {
            if (self.idx >= self.group.len) return null;
            const err = @errorFromInt(self.group.buf[self.idx]);
            self.idx += 1;
            return err;
        }
    };

    pub fn iterator(self: *const ErrorGroup) Iterator {
        return .{ .group = self, .idx = 0 };
    }

    pub fn throw(self: *const ErrorGroup) !void {
        if (self.len == 0) return;
        return @errorFromInt(self.buf[0]);
    }
};

/// Thread-safe collector of all per-task errors during concurrent stage execution.
/// Uses an atomic index to claim write slots without requiring an `Io` instance.
pub const ErrorGroupCapture = struct {
    buf: [ErrorGroup.capacity]u16 = [1]u16{0} ** ErrorGroup.capacity,
    next_idx: std.atomic.Value(u8) = .init(0),

    /// Claim a slot with an atomic increment and store the error integer.
    pub fn add(self: *ErrorGroupCapture, err: anyerror) void {
        const idx = self.next_idx.fetchAdd(1, .acq_rel);
        if (idx < ErrorGroup.capacity) {
            self.buf[idx] = @intFromError(err);
        }
    }

    pub fn addFromGroup(self: *ErrorGroupCapture, group: ErrorGroup) void {
        var it = group.iterator();
        while (it.next()) |err| {
            self.add(err);
        }
    }

    /// Build an `ErrorGroup` after all tasks have finished (`group.await` barrier).
    pub fn toErrorGroup(self: *const ErrorGroupCapture) ErrorGroup {
        const count = self.next_idx.load(.acquire);
        const len: u8 = if (count > ErrorGroup.capacity) ErrorGroup.capacity else @intCast(count);
        var eg: ErrorGroup = ErrorGroup.none;
        eg.len = len;
        @memcpy(eg.buf[0..len], self.buf[0..len]);
        return eg;
    }
};

test "ErrorGroup captures errors" {
    var eg = ErrorGroup.none;
    try std.testing.expect(!eg.hasErrors());

    eg.len = 2;
    eg.buf[0] = @intFromError(error.A);
    eg.buf[1] = @intFromError(error.B);

    var it = eg.iterator();
    try std.testing.expectEqual(@intFromError(error.A), @intFromError(it.next().?));
    try std.testing.expectEqual(@intFromError(error.B), @intFromError(it.next().?));
    try std.testing.expectEqual(null, it.next());
}
