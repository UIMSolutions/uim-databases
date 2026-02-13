/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.enumerations.columntype;

@safe:

/// Column data types
enum ColumnType {
  INTEGER,    // 64-bit signed integer
  DOUBLE,     // 64-bit floating point
  STRING,     // UTF-8 string
  BOOLEAN,    // Boolean value
  TIMESTAMP   // System time
}
