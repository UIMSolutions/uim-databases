/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.errors.column;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

/// Exception for invalid column operations
class ColumnException : CdbException {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Column error: " ~ message, file, line);
  }
}