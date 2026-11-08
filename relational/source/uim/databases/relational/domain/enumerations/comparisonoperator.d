/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.enumerations.comparisonoperator;

import uim.databases.relational.domain.exceptions;
import std.string : strip, toUpper;

@safe:

/// Operator of a WHERE condition.
enum ComparisonOperator {
  equal,
  notEqual,
  greater,
  less,
  greaterOrEqual,
  lessOrEqual,
  like,
  in_,
  isNull,
  isNotNull
}

/// Parses the SQL spelling (`=`, `!=`/`<>`, `>`, `<`, `>=`, `<=`, `LIKE`, `IN`, `IS NULL`, `IS NOT NULL`).
/// Throws: InvalidQueryException for anything else.
ComparisonOperator parseComparisonOperator(string symbol) {
  switch (symbol.strip.toUpper) {
    case "=", "==":
      return ComparisonOperator.equal;
    case "!=", "<>":
      return ComparisonOperator.notEqual;
    case ">":
      return ComparisonOperator.greater;
    case "<":
      return ComparisonOperator.less;
    case ">=":
      return ComparisonOperator.greaterOrEqual;
    case "<=":
      return ComparisonOperator.lessOrEqual;
    case "LIKE":
      return ComparisonOperator.like;
    case "IN":
      return ComparisonOperator.in_;
    case "IS NULL":
      return ComparisonOperator.isNull;
    case "IS NOT NULL":
      return ComparisonOperator.isNotNull;
    default:
      throw new InvalidQueryException("Unknown operator '" ~ symbol ~ "'");
  }
}

/// SQL spelling of an operator.
string symbolOf(ComparisonOperator op) pure nothrow @nogc {
  final switch (op) {
    case ComparisonOperator.equal:
      return "=";
    case ComparisonOperator.notEqual:
      return "!=";
    case ComparisonOperator.greater:
      return ">";
    case ComparisonOperator.less:
      return "<";
    case ComparisonOperator.greaterOrEqual:
      return ">=";
    case ComparisonOperator.lessOrEqual:
      return "<=";
    case ComparisonOperator.like:
      return "LIKE";
    case ComparisonOperator.in_:
      return "IN";
    case ComparisonOperator.isNull:
      return "IS NULL";
    case ComparisonOperator.isNotNull:
      return "IS NOT NULL";
  }
}

unittest {
  import std.exception : assertThrown;

  assert(parseComparisonOperator("<>") == ComparisonOperator.notEqual);
  assert(parseComparisonOperator("is not null") == ComparisonOperator.isNotNull);
  assert(symbolOf(ComparisonOperator.in_) == "IN");
  assertThrown!InvalidQueryException(parseComparisonOperator("~"));
}
