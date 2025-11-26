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
    /// A required resource was not found for a Res() parameter
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
