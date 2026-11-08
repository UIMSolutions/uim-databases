/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Requests entering the driving ports. Names and operators arrive as text; the interactors turn them
/// into validated domain types, so all rules live in the domain.
module uim.databases.relational.application.dtos.commands;

import uim.databases.relational.domain.types : RowData, Value;
import std.typecons : Nullable;

@safe:

struct ColumnSpec {
  string name;
  /// A type name such as INTEGER, FLOAT, STRING, BOOLEAN, DATE, JSON (or an alias like varchar).
  string type;
  bool nullable = true;
  bool primaryKey;
  bool unique;
  Nullable!Value defaultValue;
}

struct ForeignKeySpec {
  string column;
  string refTable;
  string refColumn;
}

struct CreateTableCommand {
  string name;
  ColumnSpec[] columns;
  ForeignKeySpec[] foreignKeys;
}

/// One WHERE condition. `value` is the operand of comparisons and LIKE, `values` the list for IN.
struct ConditionSpec {
  string column;
  /// =, !=, <>, >, <, >=, <=, LIKE, IN, IS NULL, IS NOT NULL
  string op;
  Value value;
  Value[] values;
}

struct SelectRequest {
  /// Empty or ["*"] selects all columns.
  string[] columns;
  ConditionSpec[] where;
  /// Empty for insertion order.
  string orderBy;
  bool ascending = true;
  /// 0 = no limit.
  size_t limit;
  size_t offset;
}

struct UpdateCommand {
  RowData changes;
  ConditionSpec[] where;
}

struct DeleteCommand {
  /// Must not be empty: deleting every row by accident is refused.
  ConditionSpec[] where;
}

struct JoinRequest {
  string leftTable;
  string rightTable;
  string leftColumn;
  string rightColumn;
  ConditionSpec[] leftWhere;
  ConditionSpec[] rightWhere;
}
