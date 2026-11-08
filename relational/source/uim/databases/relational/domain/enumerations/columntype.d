/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.enumerations.columntype;

import uim.databases.relational.domain.exceptions;
import std.string : strip, toLower;

@safe:

/// Data type of a column.
enum ColumnType {
  INTEGER, /// 64-bit signed integer
  FLOAT, /// 64-bit floating point; integers are widened
  STRING, /// text
  BOOLEAN, /// true / false
  DATE, /// ISO 8601 date or date-time text, e.g. 2026-11-08 or 2026-11-08T10:15:00
  JSON /// any value, including arrays and objects
}

/// Parses a type name, accepting common SQL aliases. Throws: SchemaException for unknown names.
ColumnType parseColumnType(string name) {
  switch (name.strip.toLower) {
    case "integer", "int", "bigint":
      return ColumnType.INTEGER;
    case "float", "double", "real":
      return ColumnType.FLOAT;
    case "string", "text", "varchar":
      return ColumnType.STRING;
    case "boolean", "bool":
      return ColumnType.BOOLEAN;
    case "date", "datetime":
      return ColumnType.DATE;
    case "json":
      return ColumnType.JSON;
    default:
      throw new SchemaException("Unknown column type '" ~ name ~ "'");
  }
}

unittest {
  import std.exception : assertThrown;

  assert(parseColumnType("VARCHAR") == ColumnType.STRING);
  assert(parseColumnType(" int ") == ColumnType.INTEGER);
  assertThrown!SchemaException(parseColumnType("blob"));
}
