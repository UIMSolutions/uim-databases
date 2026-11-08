/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.column;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types.identifier;
import uim.databases.relational.domain.types.value;
import std.datetime : Date, DateTime, DateTimeException, SysTime;
import std.format : format;
import std.typecons : Nullable;

@safe:

/// Value object: the definition of one column. A primary key column is always NOT NULL and UNIQUE.
struct ColumnDefinition {
  private {
    string _name;
    ColumnType _type;
    bool _nullable = true;
    bool _primaryKey;
    bool _unique;
    Nullable!Value _defaultValue;
  }

  /// Throws: SchemaException for an invalid name or a default that does not fit the column.
  this(string name, ColumnType type, bool nullable = true, bool primaryKey = false, bool unique = false,
    Nullable!Value defaultValue = Nullable!Value.init) {
    requireIdentifier(name, "column");
    _name = name;
    _type = type;
    _primaryKey = primaryKey;
    _nullable = nullable && !primaryKey;
    _unique = unique || primaryKey;
    if (!defaultValue.isNull) {
      try {
        _defaultValue = conform(defaultValue.get);
      } catch (ValidationException e) {
        throw new SchemaException("Invalid default for column '" ~ name ~ "': " ~ e.msg);
      }
    }
  }

  string name() const pure nothrow @nogc {
    return _name;
  }

  ColumnType type() const pure nothrow @nogc {
    return _type;
  }

  bool nullable() const pure nothrow @nogc {
    return _nullable;
  }

  bool primaryKey() const pure nothrow @nogc {
    return _primaryKey;
  }

  bool unique() const pure nothrow @nogc {
    return _unique;
  }

  Nullable!Value defaultValue() const pure nothrow @nogc {
    return _defaultValue;
  }

  /// Checks `value` against type and nullability and returns its stored form (FLOAT widens integers).
  /// Throws: ValidationException.
  Value conform(Value value) const {
    if (value.isNull) {
      if (!_nullable) {
        throw new ValidationException("Column '" ~ _name ~ "' cannot be null");
      }
      return value;
    }
    final switch (_type) {
      case ColumnType.INTEGER:
        if (value.kind == ValueKind.integer) {
          return value;
        }
        break;
      case ColumnType.FLOAT:
        if (value.isNumeric) {
          return Value.floating(value.asFloating);
        }
        break;
      case ColumnType.STRING:
        if (value.kind == ValueKind.text) {
          return value;
        }
        break;
      case ColumnType.BOOLEAN:
        if (value.kind == ValueKind.boolean) {
          return value;
        }
        break;
      case ColumnType.DATE:
        if (value.kind == ValueKind.text && isIsoDate(value.asText)) {
          return value;
        }
        break;
      case ColumnType.JSON:
        return value;
    }
    throw new ValidationException(format("Column '%s' (%s) cannot hold %s", _name, _type, value));
  }
}

/// True for ISO 8601 extended dates and date-times (with optional fraction and zone).
bool isIsoDate(string text) {
  foreach (parse; [
      (string s) @safe => cast(void) Date.fromISOExtString(s),
      (string s) @safe => cast(void) DateTime.fromISOExtString(s),
      (string s) @safe => cast(void) SysTime.fromISOExtString(s)
    ]) {
    try {
      parse(text);
      return true;
    } catch (DateTimeException) {
    }
  }
  return false;
}

unittest {
  import std.exception : assertThrown;
  import std.typecons : nullable;

  auto id = ColumnDefinition("id", ColumnType.INTEGER, true, true);
  assert(!id.nullable && id.unique);
  assertThrown!ValidationException(id.conform(Value.null_));
  assertThrown!ValidationException(id.conform(Value.floating(1.5)));

  auto price = ColumnDefinition("price", ColumnType.FLOAT);
  assert(price.conform(Value.integer(3)).kind == ValueKind.floating);

  auto day = ColumnDefinition("day", ColumnType.DATE);
  assert(day.conform(Value.text("2026-11-08")) == Value.text("2026-11-08"));
  day.conform(Value.text("2026-11-08T10:15:00Z"));
  assertThrown!ValidationException(day.conform(Value.text("tomorrow")));

  auto active = ColumnDefinition("active", ColumnType.BOOLEAN, false, false, false, nullable(Value.boolean(true)));
  assert(active.defaultValue.get == Value.boolean(true));
  assertThrown!SchemaException(ColumnDefinition("n", ColumnType.INTEGER, true, false, false, nullable(Value.text("x"))));
  assertThrown!SchemaException(ColumnDefinition("bad name", ColumnType.INTEGER));
}
