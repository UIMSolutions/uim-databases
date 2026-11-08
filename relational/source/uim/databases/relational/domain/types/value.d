/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.value;

import std.conv : to;

@safe:

/// What a Value holds.
enum ValueKind : ubyte {
  null_,
  boolean,
  integer,
  floating,
  text,
  json /// a JSON array or object, kept as its serialized text
}

/// Value object: the content of one cell. Framework-free, so the domain never sees a JSON library.
///
/// Equality is numeric across integer and floating (1 == 1.0) and consistent with toHash,
/// so values can key associative arrays (unique indexes, hash joins).
struct Value {
  private {
    ValueKind _kind = ValueKind.null_;
    bool _boolean;
    long _integer;
    double _floating = 0.0;
    string _text;
  }

  static Value null_() pure nothrow @nogc {
    return Value.init;
  }

  static Value boolean(bool value) pure nothrow @nogc {
    Value v;
    v._kind = ValueKind.boolean;
    v._boolean = value;
    return v;
  }

  static Value integer(long value) pure nothrow @nogc {
    Value v;
    v._kind = ValueKind.integer;
    v._integer = value;
    return v;
  }

  static Value floating(double value) pure nothrow @nogc {
    Value v;
    v._kind = ValueKind.floating;
    v._floating = value;
    return v;
  }

  static Value text(string value) pure nothrow @nogc {
    Value v;
    v._kind = ValueKind.text;
    v._text = value;
    return v;
  }

  /// A JSON array or object in serialized form.
  static Value json(string document) pure nothrow @nogc {
    Value v;
    v._kind = ValueKind.json;
    v._text = document;
    return v;
  }

  ValueKind kind() const pure nothrow @nogc {
    return _kind;
  }

  bool isNull() const pure nothrow @nogc {
    return _kind == ValueKind.null_;
  }

  bool isNumeric() const pure nothrow @nogc {
    return _kind == ValueKind.integer || _kind == ValueKind.floating;
  }

  bool asBoolean() const pure nothrow @nogc
  in (_kind == ValueKind.boolean) {
    return _boolean;
  }

  long asInteger() const pure nothrow @nogc
  in (_kind == ValueKind.integer) {
    return _integer;
  }

  /// Integers are widened.
  double asFloating() const pure nothrow @nogc
  in (isNumeric) {
    return _kind == ValueKind.integer ? cast(double) _integer : _floating;
  }

  /// The text, or the serialized document for ValueKind.json.
  string asText() const pure nothrow @nogc
  in (_kind == ValueKind.text || _kind == ValueKind.json) {
    return _text;
  }

  bool opEquals(const Value other) const pure nothrow @nogc {
    if (isNumeric && other.isNumeric) {
      if (_kind == ValueKind.integer && other._kind == ValueKind.integer) {
        return _integer == other._integer;
      }
      if (_kind == ValueKind.floating && other._kind == ValueKind.floating) {
        return _floating == other._floating;
      }
      // Mixed: equal only if the floating value is exactly that integer (keeps toHash consistent).
      immutable i = _kind == ValueKind.integer ? _integer : other._integer;
      immutable f = _kind == ValueKind.floating ? _floating : other._floating;
      return isIntegral(f) && cast(long) f == i;
    }
    if (_kind != other._kind) {
      return false;
    }
    final switch (_kind) {
      case ValueKind.null_:
        return true;
      case ValueKind.boolean:
        return _boolean == other._boolean;
      case ValueKind.integer, ValueKind.floating:
        assert(0); // handled above
      case ValueKind.text, ValueKind.json:
        return _text == other._text;
    }
  }

  size_t toHash() const nothrow @nogc {
    final switch (_kind) {
      case ValueKind.null_:
        return 0;
      case ValueKind.boolean:
        return _boolean ? 1 : 2;
      case ValueKind.integer:
        return hashOf(_integer);
      case ValueKind.floating:
        return isIntegral(_floating) ? hashOf(cast(long) _floating) : hashOf(_floating);
      case ValueKind.text:
        return hashOf(_text);
      case ValueKind.json:
        return hashOf(_text) ^ 0x9E37_79B9;
    }
  }

  /// SQL-like rendering for messages: NULL, true, 42, 1.5, 'text', {"a":1}.
  string toString() const {
    final switch (_kind) {
      case ValueKind.null_:
        return "NULL";
      case ValueKind.boolean:
        return _boolean ? "true" : "false";
      case ValueKind.integer:
        return _integer.to!string;
      case ValueKind.floating:
        return _floating.to!string;
      case ValueKind.text:
        return "'" ~ _text ~ "'";
      case ValueKind.json:
        return _text;
    }
  }
}

/// A row: column name -> value.
alias RowData = Value[string];

/// Copies a row so callers never share storage with a table.
RowData copyRow(const RowData row) pure nothrow {
  RowData copy;
  foreach (column, value; row) {
    copy[column] = value;
  }
  return copy;
}

private bool isIntegral(double f) pure nothrow @nogc {
  return f >= -0x1p63 && f < 0x1p63 && f == cast(double) cast(long) f;
}

unittest {
  assert(Value.integer(1) == Value.floating(1.0));
  assert(Value.integer(1).toHash == Value.floating(1.0).toHash);
  assert(Value.integer(1) != Value.floating(1.5));
  assert(Value.integer(1) != Value.text("1"));
  assert(Value.null_ == Value.init);
  assert(Value.json(`[1]`) != Value.text(`[1]`));
  assert(Value.text("it's").toString == "'it's'");

  int[Value] index;
  index[Value.integer(7)] = 1;
  assert(Value.floating(7.0) in index);
  assert(Value.text("7") !in index);

  RowData row = ["a": Value.integer(1)];
  auto copy = copyRow(row);
  copy["a"] = Value.integer(2);
  assert(row["a"] == Value.integer(1));
}
