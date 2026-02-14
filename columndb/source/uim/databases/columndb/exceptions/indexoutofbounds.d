/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.errors.indexoutofbounds;

@safe:

/// Exception for index out of bounds
class IndexOutOfBoundsException : CdbException {
  this(ulong index, ulong maxIndex, string file = __FILE__, size_t line = __LINE__) {
    super("Index out of bounds: " ~ index.to!string ~ " >= " ~ maxIndex.to!string, file, line);
  }
}