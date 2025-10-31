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
