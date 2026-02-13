/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.errors.columnnotfound;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

/// Exception for column not found
class ColumnNotFoundException : CdbException {
  this(string columnName, string file = __FILE__, size_t line = __LINE__) {
    super("Column not found: " ~ columnName, file, line);
  }
}
