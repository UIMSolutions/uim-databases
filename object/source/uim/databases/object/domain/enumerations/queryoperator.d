module uim.databases.object.domain.enumerations.queryoperator;

import uim.databases.object.domain.exceptions;
import std.string : strip, toLower;

@safe:

/// Comparison applied by a query condition to the value at a field path.
enum QueryOperator {
  EQUALS, /// deep equality; 1 and 1.0 are equal
  NOT_EQUALS, /// also matches documents without the field
  GREATER, /// numbers with numbers, strings with strings
  LESS,
  GREATER_EQ,
  LESS_EQ,
  CONTAINS, /// substring of a string field, or element of an array field
  IN, /// field value equals one element of the given array
  EXISTS /// field present (value true or null) or absent (value false)
}

/// Accepts symbols (`==`, `!=`, `>`, `<`, `>=`, `<=`), short names (`eq`, `ne`, `gt`, `lt`, `gte`, `lte`)
/// and the enum names, case-insensitively, with `-` or `_`. Throws: ValidationException.
QueryOperator parseQueryOperator(string name) {
  import std.array : replace;

  switch (name.strip.toLower.replace("-", "_")) {
    case "==", "=", "eq", "equals":
      return QueryOperator.EQUALS;
    case "!=", "<>", "ne", "not_equals":
      return QueryOperator.NOT_EQUALS;
    case ">", "gt", "greater":
      return QueryOperator.GREATER;
    case "<", "lt", "less":
      return QueryOperator.LESS;
    case ">=", "gte", "greater_eq":
      return QueryOperator.GREATER_EQ;
    case "<=", "lte", "less_eq":
      return QueryOperator.LESS_EQ;
    case "contains":
      return QueryOperator.CONTAINS;
    case "in":
      return QueryOperator.IN;
    case "exists":
      return QueryOperator.EXISTS;
    default:
      throw new ValidationException("Unknown query operator '" ~ name
          ~ "'; use ==, !=, >, <, >=, <=, contains, in or exists");
  }
}

unittest {
  import std.exception : assertThrown;

  assert(parseQueryOperator(" GTE ") == QueryOperator.GREATER_EQ);
  assert(parseQueryOperator("not-equals") == QueryOperator.NOT_EQUALS);
  assert(parseQueryOperator("==") == QueryOperator.EQUALS);
  assertThrown!ValidationException(parseQueryOperator("~="));
  assertThrown!ValidationException(parseQueryOperator(""));
}
