/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.services.join;

import uim.databases.relational.domain.entities.table;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types;
import std.algorithm : map;
import std.array : array;

@safe:

/// INNER JOIN on `left.leftColumn = right.rightColumn` (hash join, O(left + right + result)).
/// Result columns are qualified as `table.column`; rows come in left order, then right order.
/// NULL keys never match, as in SQL.
/// Throws: InvalidQueryException for unknown columns or a self join.
QueryResult innerJoin(const Table left, string leftColumn, const Condition[] leftWhere,
  const Table right, string rightColumn, const Condition[] rightWhere) {
  if (left.name == right.name) {
    throw new InvalidQueryException("Self joins are not supported: qualified column names would collide");
  }
  left.schema.column(leftColumn);
  right.schema.column(rightColumn);

  auto rightRows = right.rowsWhere(rightWhere);
  size_t[][Value] byKey;
  foreach (i, row; rightRows) {
    Value key = row[rightColumn];
    if (!key.isNull) {
      byKey[key] ~= i;
    }
  }

  RowData[] joined;
  foreach (leftRow; left.rowsWhere(leftWhere)) {
    Value key = leftRow[leftColumn];
    if (key.isNull) {
      continue;
    }
    if (auto hits = key in byKey) {
      foreach (i; *hits) {
        RowData row;
        foreach (column, value; leftRow) {
          row[left.name ~ "." ~ column] = value;
        }
        foreach (column, value; rightRows[i]) {
          row[right.name ~ "." ~ column] = value;
        }
        joined ~= row;
      }
    }
  }

  auto columns = left.schema.columnNames.map!(c => left.name ~ "." ~ c).array
    ~ right.schema.columnNames.map!(c => right.name ~ "." ~ c).array;
  return QueryResult(columns, joined);
}

unittest {
  import uim.databases.relational.domain.enumerations;
  import std.exception : assertThrown;

  alias C = ColumnDefinition;
  auto users = new Table(TableSchema("users", [C("id", ColumnType.INTEGER, false, true), C("name", ColumnType.STRING)]));
  auto orders = new Table(TableSchema("orders", [
      C("id", ColumnType.INTEGER, false, true), C("user_id", ColumnType.INTEGER), C("amount", ColumnType.FLOAT)
    ]));
  users.insertAll([
    ["id": Value.integer(1), "name": Value.text("Ada")],
    ["id": Value.integer(2), "name": Value.text("Bob")],
  ]);
  orders.insertAll([
    ["id": Value.integer(10), "user_id": Value.integer(1), "amount": Value.integer(5)],
    ["id": Value.integer(11), "user_id": Value.integer(1), "amount": Value.floating(7.5)],
    ["id": Value.integer(12), "user_id": Value.null_, "amount": Value.integer(1)],
    ["id": Value.integer(13), "user_id": Value.integer(9), "amount": Value.integer(1)],
  ]);

  auto result = innerJoin(users, "id", null, orders, "user_id", null);
  assert(result.count == 2);
  assert(result.rows[0]["users.name"] == Value.text("Ada") && result.rows[1]["orders.amount"] == Value.floating(7.5));
  assert(result.columns == ["users.id", "users.name", "orders.id", "orders.user_id", "orders.amount"]);

  auto filtered = innerJoin(users, "id", null, orders, "user_id",
    [Condition("amount", ComparisonOperator.greater, Value.integer(6))]);
  assert(filtered.count == 1);

  assertThrown!InvalidQueryException(innerJoin(users, "nope", null, orders, "user_id", null));
  assertThrown!InvalidQueryException(innerJoin(users, "id", null, users, "id", null));
}
