/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.enumerations.columntype;

import uim.databases.relational;
@safe:

/// Column data types
enum ColumnType {
  INTEGER,
  FLOAT,
  STRING,
  BOOLEAN,
  DATE,
  JSON
}
