/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Wire format of the REST API, kept apart from the application DTOs so the HTTP contract can evolve on its own.
module uim.databases.relational.presentation.rest.models;

import vibe.data.json : Json;
import vibe.data.serialization : optional, wireName = name;

@safe:

// --- Requests ---

/// `value` is the operand; for IN it is a JSON array.
struct RestCondition {
  string column;
  string op;
  @optional Json value;
}

struct RestColumn {
  string name;
  string type;
  @optional bool nullable = true;
  @optional bool primaryKey;
  @optional bool unique;
  @optional @wireName("default") Json defaultValue;
}

struct RestForeignKey {
  string column;
  string refTable;
  string refColumn;
}

struct RestCreateTableRequest {
  string name;
  RestColumn[] columns;
  @optional RestForeignKey[] foreignKeys;
}

struct RestSelectRequest {
  @optional string[] columns;
  @optional RestCondition[] where;
  @optional string orderBy;
  @optional bool ascending = true;
  @optional ulong limit;
  @optional ulong offset;
}

struct RestUpdateRequest {
  Json set;
  @optional RestCondition[] where;
}

struct RestDeleteRequest {
  @optional RestCondition[] where;
}

struct RestJoinRequest {
  string leftTable;
  string rightTable;
  string leftColumn;
  string rightColumn;
  @optional RestCondition[] leftWhere;
  @optional RestCondition[] rightWhere;
}

// --- Responses ---

struct RestHealth {
  string status;
  string type;
  ulong tableCount;
}

struct RestTableStats {
  string name;
  ulong rowCount;
  ulong columnCount;
}

struct RestStats {
  string name;
  ulong tableCount;
  RestTableStats[] tables;
}

struct RestTableList {
  string[] tables;
  ulong count;
}

struct RestColumnInfo {
  string name;
  string type;
  bool nullable;
  bool primaryKey;
  bool unique;
  /// null when the column has no default.
  @wireName("default") Json defaultValue;
}

struct RestSchema {
  string tableName;
  /// "" when the table has no primary key.
  string primaryKey;
  RestColumnInfo[] columns;
  RestForeignKey[] foreignKeys;
}

struct RestTableCreated {
  string table;
  string message;
}

struct RestMessage {
  string message;
}

struct RestCount {
  ulong count;
}

struct RestInserted {
  ulong inserted;
  ulong[] rowIds;
  string message;
}

struct RestRows {
  string[] columns;
  Json[] rows;
  ulong count;
}

struct RestUpdated {
  ulong updated;
  string message;
}

struct RestDeleted {
  ulong deleted;
  string message;
}

struct RestRow {
  Json row;
}
