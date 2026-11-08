/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.schema;

import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types.column;
import uim.databases.relational.domain.types.foreignkey;
import uim.databases.relational.domain.types.identifier;
import uim.databases.relational.domain.types.value;
import std.algorithm : count, map;
import std.array : array;

@safe:

/// Value object: the validated definition of a table.
struct TableSchema {
  private {
    string _tableName;
    ColumnDefinition[] _columns;
    ForeignKey[] _foreignKeys;
  }

  /// Throws: SchemaException for invalid names, duplicate columns, more than one primary key,
  /// or a foreign key on an unknown column.
  this(string tableName, ColumnDefinition[] columns, ForeignKey[] foreignKeys = null) {
    requireIdentifier(tableName, "table");
    if (columns.length == 0) {
      throw new SchemaException("Table '" ~ tableName ~ "' needs at least one column");
    }
    bool[string] seen;
    foreach (column; columns) {
      if (column.name in seen) {
        throw new SchemaException("Duplicate column '" ~ column.name ~ "' in table '" ~ tableName ~ "'");
      }
      seen[column.name] = true;
    }
    if (columns.count!(c => c.primaryKey) > 1) {
      throw new SchemaException("Table '" ~ tableName ~ "' has more than one primary key column");
    }
    bool[string] constrained;
    foreach (fk; foreignKeys) {
      if (fk.column !in seen) {
        throw new SchemaException("Foreign key on unknown column '" ~ fk.column ~ "'");
      }
      if (fk.column in constrained) {
        throw new SchemaException("Column '" ~ fk.column ~ "' has more than one foreign key");
      }
      constrained[fk.column] = true;
    }
    _tableName = tableName;
    _columns = columns.dup;
    _foreignKeys = foreignKeys.dup;
  }

  string tableName() const pure nothrow @nogc {
    return _tableName;
  }

  const(ColumnDefinition)[] columns() const pure nothrow @nogc {
    return _columns;
  }

  const(ForeignKey)[] foreignKeys() const pure nothrow @nogc {
    return _foreignKeys;
  }

  string[] columnNames() const pure nothrow {
    return _columns.map!(c => c.name).array;
  }

  bool hasColumn(string name) const pure nothrow @nogc {
    foreach (ref c; _columns) {
      if (c.name == name) {
        return true;
      }
    }
    return false;
  }

  /// Throws: InvalidQueryException for an unknown column.
  ColumnDefinition column(string name) const {
    foreach (c; _columns) {
      if (c.name == name) {
        return c;
      }
    }
    throw new InvalidQueryException("Unknown column '" ~ name ~ "' in table '" ~ _tableName ~ "'");
  }

  /// Name of the primary key column, or "" if the table has none.
  string primaryKey() const pure nothrow @nogc {
    foreach (ref c; _columns) {
      if (c.primaryKey) {
        return c.name;
      }
    }
    return "";
  }

  /// Throws: InvalidQueryException naming the first unknown column.
  void requireColumns(const string[] names) const {
    foreach (name; names) {
      column(name);
    }
  }

  /// A complete row for insertion: unknown columns are rejected, defaults applied, every value conformed.
  /// Throws: ValidationException.
  RowData conformRow(const RowData input) const {
    requireColumns(input.keys);
    RowData row;
    foreach (c; _columns) {
      if (auto given = c.name in input) {
        row[c.name] = c.conform(*given);
      } else if (!c.defaultValue.isNull) {
        row[c.name] = c.defaultValue.get;
      } else {
        row[c.name] = c.conform(Value.null_); // throws for NOT NULL columns
      }
    }
    return row;
  }

  /// Conformed SET values for an update. Throws: ValidationException.
  RowData conformChanges(const RowData changes) const {
    if (changes.length == 0) {
      throw new ValidationException("Nothing to update: SET is empty");
    }
    RowData conformed;
    foreach (name, value; changes) {
      conformed[name] = column(name).conform(value);
    }
    return conformed;
  }
}

unittest {
  import uim.databases.relational.domain.enumerations : ColumnType;
  import std.exception : assertThrown;
  import std.typecons : nullable;

  auto users = TableSchema("users", [
      ColumnDefinition("id", ColumnType.INTEGER, false, true),
      ColumnDefinition("name", ColumnType.STRING, false),
      ColumnDefinition("active", ColumnType.BOOLEAN, false, false, false, nullable(Value.boolean(true))),
      ColumnDefinition("age", ColumnType.INTEGER),
    ]);
  assert(users.primaryKey == "id" && users.columnNames == ["id", "name", "active", "age"]);

  auto row = users.conformRow(["id": Value.integer(1), "name": Value.text("Ada")]);
  assert(row["active"] == Value.boolean(true) && row["age"].isNull);

  assertThrown!ValidationException(users.conformRow(["id": Value.integer(2)])); // name is NOT NULL
  assertThrown!InvalidQueryException(users.conformRow(["id": Value.integer(2), "name": Value.text("x"),
      "extra": Value.integer(1)]));
  assertThrown!ValidationException(users.conformChanges(null));

  alias C = ColumnDefinition;
  assertThrown!SchemaException(TableSchema("t", []));
  assertThrown!SchemaException(TableSchema("t", [C("a", ColumnType.INTEGER), C("a", ColumnType.STRING)]));
  assertThrown!SchemaException(TableSchema("t", [C("a", ColumnType.INTEGER, false, true), C("b", ColumnType.INTEGER, false, true)]));
  assertThrown!SchemaException(TableSchema("t", [C("a", ColumnType.INTEGER)], [ForeignKey("b", "u", "id")]));
}
