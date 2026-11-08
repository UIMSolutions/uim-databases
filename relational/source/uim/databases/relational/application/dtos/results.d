/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Results leaving the driving ports. Row sets use the domain's QueryResult (plain data).
module uim.databases.relational.application.dtos.results;

import uim.databases.relational.domain;
import std.algorithm : map;
import std.array : array;
import std.conv : to;
import std.typecons : Nullable;

@safe:

struct ColumnView {
  string name;
  string type;
  bool nullable;
  bool primaryKey;
  bool unique;
  Nullable!Value defaultValue;
}

struct ForeignKeyView {
  string column;
  string refTable;
  string refColumn;
}

struct TableSchemaView {
  string tableName;
  /// "" when the table has no primary key.
  string primaryKey;
  ColumnView[] columns;
  ForeignKeyView[] foreignKeys;

  static TableSchemaView from(const TableSchema schema) {
    return TableSchemaView(schema.tableName, schema.primaryKey,
      schema.columns.map!(c => ColumnView(c.name, c.type.to!string, c.nullable, c.primaryKey, c.unique,
        c.defaultValue)).array,
      schema.foreignKeys.map!(f => ForeignKeyView(f.column, f.referencedTable, f.referencedColumn)).array);
  }
}

struct TableStatistics {
  string name;
  size_t rowCount;
  size_t columnCount;
}

struct DatabaseStatistics {
  string name;
  size_t tableCount;
  TableStatistics[] tables;
}

struct HealthStatus {
  string status;
  string type;
  size_t tableCount;
}
