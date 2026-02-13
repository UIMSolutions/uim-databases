/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.errors.exceptions;

@safe:

/// Exception for index out of bounds
class IndexOutOfBoundsException : Exception {
  this(ulong index, ulong maxIndex, string file = __FILE__, size_t line = __LINE__) {
    super("Index out of bounds: " ~ index.to!string ~ " >= " ~ maxIndex.to!string, file, line);
  }
}

/// Exception for type mismatch
class TypeMismatchException : Exception {
  this(string expectedType, string actualType, string file = __FILE__, size_t line = __LINE__) {
    super("Type mismatch: expected " ~ expectedType ~ ", got " ~ actualType, file, line);
  }
}

/// Exception for column not found
class ColumnNotFoundException : Exception {
  this(string columnName, string file = __FILE__, size_t line = __LINE__) {
    super("Column not found: " ~ columnName, file, line);
  }
}

/// Exception for duplicate column
class DuplicateColumnException : Exception {
  this(string columnName, string file = __FILE__, size_t line = __LINE__) {
    super("Duplicate column: " ~ columnName, file, line);
  }
}

/// Exception for table operations
class TableException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Table error: " ~ message, file, line);
  }
}
