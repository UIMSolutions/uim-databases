/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.errors.typemismatch;

@safe:

/// Exception for type mismatch
class TypeMismatchException : CdbException {
  this(string expectedType, string actualType, string file = __FILE__, size_t line = __LINE__) {
    super("Type mismatch: expected " ~ expectedType ~ ", got " ~ actualType, file, line);
  }
}