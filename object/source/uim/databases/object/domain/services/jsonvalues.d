/// Equality, ordering, index keys and copies of JSON values, as the database defines them.
///
/// - Numbers compare by value, whatever their JSON representation: 1, 1.0 and 1e0 are equal.
/// - Objects are equal when they have the same members with equal values, in any order.
/// - Total order across types (used for sorting): null < numbers < strings < objects < arrays < booleans.
module uim.databases.object.domain.services.jsonvalues;

import std.algorithm : cmp, map, sort;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import std.json : JSONType, JSONValue;
import std.math : floor, isFinite;

@safe:

/// Canonical text of a value: equal values have equal keys, so it serves as an index key.
string canonicalKey(JSONValue value) {
  final switch (value.type) {
    case JSONType.null_:
      return "null";
    case JSONType.true_:
      return "true";
    case JSONType.false_:
      return "false";
    case JSONType.integer:
      return value.integer.to!string;
    case JSONType.uinteger:
      return value.uinteger.to!string;
    case JSONType.float_:
      return floatKey(value.floating);
    case JSONType.string:
      return JSONValue(value.str).toString();
    case JSONType.array:
      return "[" ~ value.arrayNoRef.map!(v => canonicalKey(v)).join(",") ~ "]";
    case JSONType.object:
      auto members = value.objectNoRef;
      return "{" ~ members.keys.sort.map!(k => JSONValue(k).toString() ~ ":" ~ canonicalKey(members[k])).join(",") ~ "}";
  }
}

/// Deep equality as defined above.
bool valuesEqual(JSONValue a, JSONValue b) {
  return canonicalKey(a) == canonicalKey(b);
}

/// True when both values are numbers or both are strings, the only pairs that range operators compare.
bool isOrderable(JSONValue a, JSONValue b) {
  return (isNumber(a) && isNumber(b)) || (a.type == JSONType.string && b.type == JSONType.string);
}

/// Total order: negative, zero or positive.
int compareValues(JSONValue a, JSONValue b) {
  immutable ra = rank(a), rb = rank(b);
  if (ra != rb) {
    return ra < rb ? -1 : 1;
  }
  switch (ra) {
    case 1:
      return compareNumbers(a, b);
    case 2:
      return cmp(a.str, b.str);
    case 5:
      return (a.type == JSONType.true_) - (b.type == JSONType.true_);
    case 0:
      return 0;
    default:
      return cmp(canonicalKey(a), canonicalKey(b));
  }
}

/// Deep copy, so that stored documents cannot be changed from outside the aggregate.
JSONValue deepCopy(const JSONValue value) {
  final switch (value.type) {
    case JSONType.null_:
      return JSONValue(null);
    case JSONType.true_:
      return JSONValue(true);
    case JSONType.false_:
      return JSONValue(false);
    case JSONType.integer:
      return JSONValue(value.integer);
    case JSONType.uinteger:
      return JSONValue(value.uinteger);
    case JSONType.float_:
      return JSONValue(value.floating);
    case JSONType.string:
      return JSONValue(value.str);
    case JSONType.array:
      return JSONValue(value.arrayNoRef.map!(v => deepCopy(v)).array);
    case JSONType.object:
      JSONValue[string] members;
      foreach (key, ref member; value.objectNoRef) {
        members[key] = deepCopy(member);
      }
      return JSONValue(members);
  }
}

bool isNumber(JSONValue value) pure nothrow @nogc {
  return value.type == JSONType.integer || value.type == JSONType.uinteger || value.type == JSONType.float_;
}

private int rank(JSONValue value) {
  final switch (value.type) {
    case JSONType.null_:
      return 0;
    case JSONType.integer, JSONType.uinteger, JSONType.float_:
      return 1;
    case JSONType.string:
      return 2;
    case JSONType.object:
      return 3;
    case JSONType.array:
      return 4;
    case JSONType.true_, JSONType.false_:
      return 5;
  }
}

private int compareNumbers(JSONValue a, JSONValue b) {
  // Exact for integers of either sign; floating point otherwise.
  if (a.type != JSONType.float_ && b.type != JSONType.float_) {
    immutable aNegative = a.type == JSONType.integer && a.integer < 0;
    immutable bNegative = b.type == JSONType.integer && b.integer < 0;
    if (aNegative != bNegative) {
      return aNegative ? -1 : 1;
    }
    if (aNegative) {
      return a.integer < b.integer ? -1 : (a.integer > b.integer ? 1 : 0);
    }
    immutable ua = a.type == JSONType.integer ? cast(ulong) a.integer : a.uinteger;
    immutable ub = b.type == JSONType.integer ? cast(ulong) b.integer : b.uinteger;
    return ua < ub ? -1 : (ua > ub ? 1 : 0);
  }
  immutable da = toDouble(a), db = toDouble(b);
  return da < db ? -1 : (da > db ? 1 : 0);
}

private double toDouble(JSONValue value) {
  switch (value.type) {
    case JSONType.integer:
      return value.integer;
    case JSONType.uinteger:
      return value.uinteger;
    default:
      return value.floating;
  }
}

/// Integral floats get the key of the equal integer.
private string floatKey(double value) {
  if (isFinite(value) && floor(value) == value) {
    if (value >= -9.223372036854775808e18 && value < 9.223372036854775808e18) {
      return (cast(long) value).to!string;
    }
    if (value >= 0 && value < 1.8446744073709551616e19) {
      return (cast(ulong) value).to!string;
    }
  }
  return format("%.17g", value);
}

unittest {
  import std.json : parseJSON;

  auto j = (string s) => parseJSON(s);
  assert(valuesEqual(j("1"), j("1.0")) && valuesEqual(j("-0.0"), j("0")));
  assert(valuesEqual(j(`{"a":1,"b":[1,"x"]}`), j(`{"b":[1.0,"x"],"a":1}`)));
  assert(!valuesEqual(j(`"1"`), j("1")) && !valuesEqual(j("[1,2]"), j("[2,1]")));
  assert(valuesEqual(JSONValue(ulong.max), JSONValue(ulong.max)));

  assert(compareValues(j("2"), j("10")) < 0 && compareValues(j("-1"), JSONValue(ulong.max)) < 0);
  assert(compareValues(j("1.5"), j("1")) > 0 && compareValues(j(`"a"`), j(`"b"`)) < 0);
  assert(compareValues(j("null"), j("0")) < 0 && compareValues(j("0"), j(`""`)) < 0);
  assert(compareValues(j("false"), j("true")) < 0 && compareValues(j("[]"), j("true")) < 0);
  assert(isOrderable(j("1"), j("2.5")) && !isOrderable(j("1"), j(`"1"`)) && !isOrderable(j("true"), j("false")));

  auto original = j(`{"a":{"b":[1]}}`);
  auto copy = deepCopy(original);
  copy["a"]["b"] = JSONValue(2);
  assert(canonicalKey(original) == `{"a":{"b":[1]}}`);
}
