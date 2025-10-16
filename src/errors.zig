pub const ECSError = error{
    OutOfMemory,
    EntityNotAlive,
    ComponentNotFound,
    ResourceNotFound,
    ResourceAlreadyExists,
    InvalidEntity,
    ComponentAlreadyExists,
};
