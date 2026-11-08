/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.query;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.types.condition;
import uim.databases.relational.domain.types.value;

@safe:

/// One ORDER BY key.
struct Ordering {
  string column;
  SortDirection direction;
}

/// A single-table SELECT.
struct Query {
  /// Projection; empty (or `["*"]`) selects every column in schema order.
  string[] columns;
  /// Combined with AND.
  Condition[] where;
  /// Applied in order; ties keep insertion order.
  Ordering[] orderBy;
  /// 0 = no limit.
  size_t limit;
  size_t offset;
}

/// Rows returned by a query or join, with their column names in output order.
struct QueryResult {
  string[] columns;
  RowData[] rows;

  size_t count() const pure nothrow @nogc {
    return rows.length;
  }
}
