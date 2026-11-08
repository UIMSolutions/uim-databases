/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Business errors. Inbound adapters map the three families to HTTP 400, 404 and 409.
module uim.databases.vector.domain.exceptions.errors;

@safe:

/// Base class of every business error of the vector database.
abstract class VectorDatabaseException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

// --- Invalid input (400) ---

/// Invalid names, ids, values, dimensions or search parameters.
class ValidationException : VectorDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// A vector whose length differs from the collection's dimension.
class DimensionMismatchException : ValidationException {
  this(size_t expected, size_t actual, string file = __FILE__, size_t line = __LINE__) {
    import std.conv : to;

    super("Vector dimension " ~ actual.to!string ~ " does not match collection dimension " ~ expected.to!string,
      file, line);
  }
}

// --- Missing things (404) ---

abstract class NotFoundException : VectorDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class CollectionNotFoundException : NotFoundException {
  this(string collection, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Collection '" ~ collection ~ "' not found", file, line);
  }
}

class VectorNotFoundException : NotFoundException {
  this(string collection, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Vector '" ~ id ~ "' not found in collection '" ~ collection ~ "'", file, line);
  }
}

// --- Conflicts with existing state (409) ---

abstract class ConflictException : VectorDatabaseException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class CollectionAlreadyExistsException : ConflictException {
  this(string collection, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Collection '" ~ collection ~ "' already exists", file, line);
  }
}

class VectorAlreadyExistsException : ConflictException {
  this(string collection, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Vector '" ~ id ~ "' already exists in collection '" ~ collection ~ "'", file, line);
  }
}
