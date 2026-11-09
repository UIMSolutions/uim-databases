/// Business errors. Inbound adapters map the three families to HTTP 400, 404 and 409.
module uim.databases.object.domain.exceptions.errors;

@safe:

/// Base class of every business error of the object database.
abstract class ObjectDatabaseException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

// --- Invalid input (400) ---

/// Invalid names, ids, field paths, documents or query parameters.
class ValidationException : ObjectDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// An attempt to drop a collection that must always exist (the configured default collection).
class ProtectedCollectionException : ValidationException {
  this(string collection, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Collection '" ~ collection ~ "' is protected and cannot be dropped", file, line);
  }
}

// --- Missing things (404) ---

abstract class NotFoundException : ObjectDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class CollectionNotFoundException : NotFoundException {
  this(string collection, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Collection '" ~ collection ~ "' not found", file, line);
  }
}

class DocumentNotFoundException : NotFoundException {
  this(string collection, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Document '" ~ id ~ "' not found in collection '" ~ collection ~ "'", file, line);
  }
}

class IndexNotFoundException : NotFoundException {
  this(string collection, string field, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Index on '" ~ field ~ "' not found in collection '" ~ collection ~ "'", file, line);
  }
}

// --- Conflicts with existing state (409) ---

abstract class ConflictException : ObjectDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class CollectionAlreadyExistsException : ConflictException {
  this(string collection, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Collection '" ~ collection ~ "' already exists", file, line);
  }
}

class DocumentAlreadyExistsException : ConflictException {
  this(string collection, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Document '" ~ id ~ "' already exists in collection '" ~ collection ~ "'", file, line);
  }
}

class IndexAlreadyExistsException : ConflictException {
  this(string collection, string field, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Index on '" ~ field ~ "' already exists in collection '" ~ collection ~ "'", file, line);
  }
}
