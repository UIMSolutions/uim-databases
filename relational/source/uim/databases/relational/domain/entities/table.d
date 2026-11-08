/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.entities.table;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.services.comparison;
import uim.databases.relational.domain.services.predicates;
import uim.databases.relational.domain.types;
import std.algorithm : filter, map, sort, SwapStrategy;
import std.array : array;
import std.format : format;
import std.range : assumeSorted, iota;
import std.typecons : Nullable, nullable;

@safe:

/// Entity and aggregate root: a table (identified by its name) with its rows and constraint indexes.
///
/// Every mutation is all-or-nothing: rows are validated and constraints checked before anything changes.
/// Rows get a stable, increasing row id; rows handed out are copies.
final class Table {
  private {
    struct StoredRow {
      ulong id;
      RowData cells;
    }

    TableSchema _schema;
    StoredRow[] _rows; // ordered by id
    ulong _nextRowId = 1;
    ulong[Value][string] _uniqueIndex; // unique column -> value -> row id (NULLs are not indexed)
  }

  this(TableSchema schema) {
    _schema = schema;
  }

  string name() const pure nothrow @nogc {
    return _schema.tableName;
  }

  const(TableSchema) schema() const pure nothrow @nogc {
    return _schema;
  }

  size_t rowCount() const pure nothrow @nogc {
    return _rows.length;
  }

  /// Throws: ValidationException, ConstraintViolationException.
  ulong insert(const RowData input) {
    return insertAll([copyRow(input)])[0];
  }

  /// Inserts all rows or none. Returns their row ids.
  /// Throws: ValidationException, ConstraintViolationException.
  ulong[] insertAll(const RowData[] inputs) {
    StoredRow[] fresh;
    foreach (i, input; inputs) {
      fresh ~= StoredRow(_nextRowId + i, _schema.conformRow(input));
    }

    // Check against existing rows and within the batch, then commit.
    ulong[Value][string] added;
    foreach (row; fresh) {
      foreach (column; uniqueColumns) {
        Value value = row.cells[column];
        if (value.isNull) {
          continue;
        }
        if (auto existing = column in _uniqueIndex) {
          if (value in *existing) {
            throw violation(column, value);
          }
        }
        if (auto batch = column in added) {
          if (value in *batch) {
            throw violation(column, value);
          }
        }
        added[column][value] = row.id;
      }
    }

    foreach (column, values; added) {
      foreach (value, id; values) {
        _uniqueIndex[column][value] = id;
      }
    }
    _rows ~= fresh;
    _nextRowId += fresh.length;
    return fresh.map!(r => r.id).array;
  }

  /// Throws: InvalidQueryException for unknown columns.
  QueryResult select(const Query query) const {
    auto projection = query.columns.length == 0 || query.columns == ["*"] ? _schema.columnNames : query.columns.dup;
    _schema.requireColumns(projection);
    requireConditionColumns(query.where);
    foreach (o; query.orderBy) {
      _schema.column(o.column);
    }

    // Sort positions, not rows: rows are const here.
    auto matched = iota(_rows.length).filter!(i => matchesAll(query.where, _rows[i].cells)).array;
    if (query.orderBy.length > 0) {
      matched.sort!((a, b) => compareRows(_rows[a].cells, _rows[b].cells, query.orderBy) < 0, SwapStrategy.stable);
    }

    immutable from = query.offset < matched.length ? query.offset : matched.length;
    auto window = matched[from .. $];
    if (query.limit > 0 && query.limit < window.length) {
      window = window[0 .. query.limit];
    }

    RowData[] rows;
    foreach (i; window) {
      RowData projected;
      foreach (column; projection) {
        projected[column] = _rows[i].cells[column];
      }
      rows ~= projected;
    }
    return QueryResult(projection, rows);
  }

  /// Copies of all rows matching `where`, all columns. Throws: InvalidQueryException.
  RowData[] rowsWhere(const Condition[] where) const {
    requireConditionColumns(where);
    return _rows.filter!(r => matchesAll(where, r.cells)).map!(r => copyRow(r.cells)).array;
  }

  /// Applies `changes` to every matching row. Returns the number of rows changed.
  /// Throws: ValidationException, InvalidQueryException, ConstraintViolationException.
  size_t update(const RowData changes, const Condition[] where) {
    auto conformed = _schema.conformChanges(changes);
    requireConditionColumns(where);

    size_t changed;
    auto next = _rows.dup;
    foreach (ref row; next) {
      if (matchesAll(where, row.cells)) {
        auto cells = copyRow(row.cells);
        foreach (column, value; conformed) {
          cells[column] = value;
        }
        row.cells = cells;
        changed++;
      }
    }
    if (changed > 0) {
      auto index = buildUniqueIndex(next); // throws before anything is replaced
      _rows = next;
      _uniqueIndex = index;
    }
    return changed;
  }

  /// Deletes every matching row. Returns the number of rows deleted. Throws: InvalidQueryException.
  size_t remove(const Condition[] where) {
    requireConditionColumns(where);
    auto remaining = _rows.filter!(r => !matchesAll(where, r.cells)).array;
    immutable deleted = _rows.length - remaining.length;
    if (deleted > 0) {
      _uniqueIndex = buildUniqueIndex(remaining);
      _rows = remaining;
    }
    return deleted;
  }

  /// Throws: InvalidQueryException.
  size_t count(const Condition[] where = null) const {
    requireConditionColumns(where);
    size_t n;
    foreach (r; _rows) {
      if (matchesAll(where, r.cells)) {
        n++;
      }
    }
    return n;
  }

  /// The row whose primary key equals `key`, if any.
  /// Throws: InvalidQueryException if the table has no primary key, ValidationException if `key` does not fit it.
  Nullable!RowData findByPrimaryKey(Value key) const {
    immutable pk = _schema.primaryKey;
    if (pk.length == 0) {
      throw new InvalidQueryException("Table '" ~ name ~ "' has no primary key");
    }
    auto conformed = _schema.column(pk).conform(key);
    if (auto byValue = pk in _uniqueIndex) {
      if (auto id = conformed in *byValue) {
        auto found = _rows.assumeSorted!((a, b) => a.id < b.id).equalRange(StoredRow(*id));
        if (!found.empty) {
          return nullable(copyRow(found.front.cells));
        }
      }
    }
    return Nullable!RowData.init;
  }

  /// True when some row holds `value` in `column` (uses the unique index when there is one).
  bool containsValue(string column, Value value) const {
    _schema.column(column);
    if (auto byValue = column in _uniqueIndex) {
      return (value in *byValue) !is null;
    }
    foreach (r; _rows) {
      if (r.cells[column] == value) {
        return true;
      }
    }
    return false;
  }

  private string[] uniqueColumns() const {
    return _schema.columns.filter!(c => c.unique).map!(c => c.name).array;
  }

  private ulong[Value][string] buildUniqueIndex(const StoredRow[] rows) const {
    ulong[Value][string] index;
    foreach (column; uniqueColumns) {
      foreach (r; rows) {
        Value value = r.cells[column];
        if (value.isNull) {
          continue;
        }
        if (auto byValue = column in index) {
          if (value in *byValue) {
            throw violation(column, value);
          }
        }
        index[column][value] = r.id;
      }
    }
    return index;
  }

  private ConstraintViolationException violation(string column, const Value value) const {
    immutable kind = column == _schema.primaryKey ? "Primary key" : "Unique constraint";
    return new ConstraintViolationException(format("%s violation: %s already exists in %s.%s",
        kind, value, name, column));
  }

  private void requireConditionColumns(const Condition[] where) const {
    foreach (c; where) {
      _schema.column(c.column);
    }
  }

  private static int compareRows(const RowData a, const RowData b, const Ordering[] orderBy) {
    foreach (o; orderBy) {
      const va = a[o.column], vb = b[o.column];
      if (va.isNull != vb.isNull) {
        return va.isNull ? 1 : -1; // NULLs last in both directions
      }
      immutable c = sortOrder(va, vb);
      if (c != 0) {
        return o.direction == SortDirection.ascending ? c : -c;
      }
    }
    return 0;
  }
}

unittest {
  import std.exception : assertThrown;

  alias C = ColumnDefinition;
  alias Op = ComparisonOperator;
  auto users = new Table(TableSchema("users", [
      C("id", ColumnType.INTEGER, false, true),
      C("email", ColumnType.STRING, true, false, true),
      C("age", ColumnType.INTEGER),
    ]));

  RowData user(long id, string email, Value age = Value.null_) {
    return ["id": Value.integer(id), "email": Value.text(email), "age": age];
  }

  assert(users.insertAll([user(1, "a@x", Value.integer(30)), user(2, "b@x", Value.integer(25)), user(3, "c@x")]) == [1, 2, 3]);

  // Constraints: nothing is inserted when one row fails.
  assertThrown!ConstraintViolationException(users.insertAll([user(4, "d@x"), user(1, "e@x")]));
  assertThrown!ConstraintViolationException(users.insertAll([user(4, "d@x"), user(5, "d@x")]));
  assert(users.rowCount == 3);
  // Unique columns accept several NULLs.
  users.insert(["id": Value.integer(6)]);
  users.insert(["id": Value.integer(7)]);
  assert(users.remove([Condition("id", Op.greater, Value.integer(5))]) == 2);

  // Select: order (NULLs last), limit, offset, projection.
  auto byAge = users.select(Query(["id"], null, [Ordering("age", SortDirection.descending)]));
  assert(byAge.columns == ["id"]);
  assert(byAge.rows.map!(r => r["id"].asInteger).array == [1, 2, 3]);
  assert(users.select(Query(null, null, [Ordering("age", SortDirection.ascending)], 1, 1)).rows[0]["id"] == Value.integer(1));
  assert(users.select(Query(null, null, null, 0, 10)).count == 0);
  assertThrown!InvalidQueryException(users.select(Query(["nope"])));
  assertThrown!InvalidQueryException(users.count([Condition("nope", Op.isNull)]));

  // Update is atomic and keeps the indexes right, including primary key changes.
  assertThrown!ConstraintViolationException(users.update(["email": Value.text("a@x")], [Condition("id", Op.equal, Value.integer(2))]));
  assert(users.findByPrimaryKey(Value.integer(2)).get["email"] == Value.text("b@x"));
  assert(users.update(["id": Value.integer(20)], [Condition("id", Op.equal, Value.integer(2))]) == 1);
  assert(users.findByPrimaryKey(Value.integer(2)).isNull);
  assert(users.findByPrimaryKey(Value.integer(20)).get["age"] == Value.integer(25));
  assertThrown!ValidationException(users.update(["age": Value.text("old")], null));

  // Rows handed out are copies.
  auto copy = users.findByPrimaryKey(Value.integer(1)).get;
  copy["age"] = Value.integer(99);
  assert(users.findByPrimaryKey(Value.integer(1)).get["age"] == Value.integer(30));

  assert(users.containsValue("email", Value.text("c@x")) && !users.containsValue("age", Value.integer(99)));
  assert(users.remove([Condition("age", Op.isNull)]) == 1);
  assert(users.count() == 2);
}
