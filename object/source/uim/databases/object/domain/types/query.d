module uim.databases.object.domain.types.query;

import uim.databases.object.domain.enumerations;
import uim.databases.object.domain.exceptions;
import uim.databases.object.domain.services.jsonvalues;
import uim.databases.object.domain.types.fieldpath;
import std.algorithm : all, any, canFind;
import std.json : JSONType, JSONValue;
import std.typecons : Nullable;

@safe:

/// Value object: one test of a field against a value.
struct Condition {
  private {
    FieldPath _field;
    QueryOperator _operator;
    JSONValue _value;
  }

  /// Throws: ValidationException when the value does not fit the operator
  /// (`in` needs an array, `exists` needs true, false or null).
  this(FieldPath field, QueryOperator operator, JSONValue value) {
    if (operator == QueryOperator.IN && value.type != JSONType.array) {
      throw new ValidationException("Operator 'in' on '" ~ field.toString ~ "' needs an array value");
    }
    if (operator == QueryOperator.EXISTS) {
      if (value.type == JSONType.null_) {
        value = JSONValue(true);
      } else if (value.type != JSONType.true_ && value.type != JSONType.false_) {
        throw new ValidationException("Operator 'exists' on '" ~ field.toString ~ "' needs true or false");
      }
    }
    _field = field;
    _operator = operator;
    _value = deepCopy(value);
  }

  FieldPath field() const pure nothrow @nogc {
    return _field;
  }

  QueryOperator operator() const pure nothrow @nogc {
    return _operator;
  }

  JSONValue value() const {
    return deepCopy(_value);
  }

  bool matches(JSONValue document) const {
    JSONValue actual;
    immutable present = _field.resolve(document, actual);
    // Read members through a mutable copy: std.json's accessors do not work on const in @safe code.
    auto expected = deepCopy(_value);

    final switch (_operator) {
      case QueryOperator.EXISTS:
        return present == (expected.type == JSONType.true_);
      case QueryOperator.NOT_EQUALS:
        return !present || !valuesEqual(actual, expected);
      case QueryOperator.EQUALS:
        return present && valuesEqual(actual, expected);
      case QueryOperator.GREATER:
        return present && isOrderable(actual, expected) && compareValues(actual, expected) > 0;
      case QueryOperator.LESS:
        return present && isOrderable(actual, expected) && compareValues(actual, expected) < 0;
      case QueryOperator.GREATER_EQ:
        return present && isOrderable(actual, expected) && compareValues(actual, expected) >= 0;
      case QueryOperator.LESS_EQ:
        return present && isOrderable(actual, expected) && compareValues(actual, expected) <= 0;
      case QueryOperator.CONTAINS:
        if (!present) {
          return false;
        }
        if (actual.type == JSONType.string && expected.type == JSONType.string) {
          return actual.str.canFind(expected.str);
        }
        if (actual.type == JSONType.array) {
          return actual.arrayNoRef.any!(element => valuesEqual(element, expected));
        }
        return false;
      case QueryOperator.IN:
        return present && expected.arrayNoRef.any!(candidate => valuesEqual(actual, candidate));
    }
  }
}

/// Value object: order of the result.
struct SortOrder {
  FieldPath field;
  SortDirection direction = SortDirection.ASCENDING;
}

/// Value object: conditions (all must hold), an optional sort order and paging.
/// Without a sort order, documents come in insertion order.
struct DocumentQuery {
  Condition[] conditions;
  Nullable!SortOrder sort;
  size_t skip;
  /// 0 means no limit.
  size_t limit;

  bool matches(JSONValue document) const {
    return conditions.all!(c => c.matches(document));
  }
}

unittest {
  import std.exception : assertThrown;
  import std.json : parseJSON;

  auto doc = parseJSON(`{"name":"Ada","age":36,"score":1.5,"tags":["math","code"],"address":{"city":"London"}}`);
  bool test(string field, QueryOperator op, string value) {
    return Condition(FieldPath(field), op, parseJSON(value)).matches(doc);
  }

  assert(test("age", QueryOperator.EQUALS, "36") && test("age", QueryOperator.EQUALS, "36.0"));
  assert(test("address.city", QueryOperator.EQUALS, `"London"`));
  assert(test("address", QueryOperator.EQUALS, `{"city":"London"}`));
  assert(test("age", QueryOperator.NOT_EQUALS, "35") && test("missing", QueryOperator.NOT_EQUALS, "1"));
  assert(test("age", QueryOperator.GREATER, "35.5") && !test("age", QueryOperator.GREATER, "36"));
  assert(test("age", QueryOperator.GREATER_EQ, "36") && test("score", QueryOperator.LESS, "2"));
  assert(!test("age", QueryOperator.GREATER_EQ, `"36"`)); // number vs string never orders
  assert(!test("name", QueryOperator.LESS_EQ, "1"));
  assert(test("name", QueryOperator.LESS, `"Bob"`));
  assert(test("name", QueryOperator.CONTAINS, `"d"`) && test("tags", QueryOperator.CONTAINS, `"code"`));
  assert(!test("age", QueryOperator.CONTAINS, "3"));
  assert(test("name", QueryOperator.IN, `["Bob","Ada"]`) && !test("missing", QueryOperator.IN, `[null]`));
  assert(test("name", QueryOperator.EXISTS, "true") && test("missing", QueryOperator.EXISTS, "false"));
  assert(test("name", QueryOperator.EXISTS, "null"));
  assert(!test("missing", QueryOperator.EQUALS, "null"));

  assertThrown!ValidationException(Condition(FieldPath("a"), QueryOperator.IN, parseJSON("1")));
  assertThrown!ValidationException(Condition(FieldPath("a"), QueryOperator.EXISTS, parseJSON("1")));

  auto query = DocumentQuery([
    Condition(FieldPath("age"), QueryOperator.GREATER, parseJSON("30")),
    Condition(FieldPath("tags"), QueryOperator.CONTAINS, parseJSON(`"math"`))
  ]);
  assert(query.matches(doc) && DocumentQuery().matches(doc));
}
