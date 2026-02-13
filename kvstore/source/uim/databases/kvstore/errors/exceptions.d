/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.kvstore.errors.exceptions;

@safe:

/// Exception thrown when a key is not found
class KeyNotFoundException : Exception {
  this(string key, string file = __FILE__, size_t line = __LINE__) {
    super("Key not found: " ~ key, file, line);
  }
}

/// Exception thrown for invalid operations
class InvalidOperationException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Invalid operation: " ~ message, file, line);
  }
}

/// Exception thrown for store errors
class StoreException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Store error: " ~ message, file, line);
  }
}
