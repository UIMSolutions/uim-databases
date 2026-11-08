/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.condition;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types.value;

@safe:

/// Value object: one WHERE condition. A list of conditions is combined with AND.
struct Condition {
  private {
    string _column;
    ComparisonOperator _op;
    Value _operand;
    Value[] _candidates;
  }

  /// `operand` is used by comparisons and LIKE, `candidates` by IN; IS [NOT] NULL uses neither.
  /// Throws: InvalidQueryException when the operand does not fit the operator.
  this(string column, ComparisonOperator op, Value operand = Value.null_, Value[] candidates = null) {
    if (column.length == 0) {
      throw new InvalidQueryException("Condition without column");
    }
    switch (op) {
      case ComparisonOperator.equal, ComparisonOperator.notEqual, ComparisonOperator.greater,
        ComparisonOperator.less, ComparisonOperator.greaterOrEqual, ComparisonOperator.lessOrEqual:
        if (operand.isNull) {
          throw new InvalidQueryException("Operator " ~ symbolOf(op) ~ " on '" ~ column
              ~ "' needs a value; use IS NULL / IS NOT NULL to test for NULL");
        }
        break;
      case ComparisonOperator.like:
        if (operand.kind != ValueKind.text) {
          throw new InvalidQueryException("LIKE on '" ~ column ~ "' needs a text pattern");
        }
        break;
      default:
        break;
    }
    _column = column;
    _op = op;
    _operand = operand;
    _candidates = candidates.dup;
  }

  string column() const pure nothrow @nogc {
    return _column;
  }

  ComparisonOperator op() const pure nothrow @nogc {
    return _op;
  }

  Value operand() const pure nothrow @nogc {
    return _operand;
  }

  const(Value)[] candidates() const pure nothrow @nogc {
    return _candidates;
  }
}

unittest {
  import std.exception : assertThrown;

  assertThrown!InvalidQueryException(Condition("age", ComparisonOperator.greater));
  assertThrown!InvalidQueryException(Condition("name", ComparisonOperator.like, Value.integer(1)));
  assertThrown!InvalidQueryException(Condition("", ComparisonOperator.isNull));
  Condition("age", ComparisonOperator.isNull);
}
