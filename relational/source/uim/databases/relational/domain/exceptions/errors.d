/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Business errors. Inbound adapters map the three families to HTTP 400, 404 and 409.
module uim.databases.relational.domain.exceptions.errors;

@safe:

/// Base class of every business error of the relational database.
abstract class RelationalException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

// --- Invalid input (400) ---

/// A value, row, query or definition breaks a rule.
class ValidationException : RelationalException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// An invalid table definition (names, columns, keys, types).
class SchemaException : ValidationException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// An invalid query (unknown column, operator, operand).
class InvalidQueryException : ValidationException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

// --- Missing things (404) ---

abstract class NotFoundException : RelationalException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class TableNotFoundException : NotFoundException {
  this(string table, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Table '" ~ table ~ "' not found", file, line);
  }
}

class RowNotFoundException : NotFoundException {
  this(string table, string key, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("No row with primary key " ~ key ~ " in table '" ~ table ~ "'", file, line);
  }
}

// --- Conflicts with existing state (409) ---

abstract class ConflictException : RelationalException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

class TableAlreadyExistsException : ConflictException {
  this(string table, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Table '" ~ table ~ "' already exists", file, line);
  }
}

/// A primary key or unique constraint would be violated, or a table is still referenced.
class ConstraintViolationException : ConflictException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}
