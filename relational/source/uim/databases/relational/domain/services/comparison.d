/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.services.comparison;

import uim.databases.relational.domain.types.value;
import std.algorithm.comparison : cmp;
import std.typecons : Nullable, nullable;

@safe:

/// Order of two comparable values (<0, 0, >0); null when they cannot be compared
/// (a NULL, different kinds, or JSON documents). Numbers compare across integer and floating.
Nullable!int compareValues(const Value a, const Value b) pure nothrow {
  if (a.isNumeric && b.isNumeric) {
    if (a.kind == ValueKind.integer && b.kind == ValueKind.integer) {
      return nullable(threeWay(a.asInteger, b.asInteger));
    }
    return nullable(threeWay(a.asFloating, b.asFloating));
  }
  if (a.kind != b.kind) {
    return Nullable!int.init;
  }
  switch (a.kind) {
    case ValueKind.text:
      return nullable(cmp(a.asText, b.asText));
    case ValueKind.boolean:
      return nullable(threeWay(a.asBoolean, b.asBoolean));
    default:
      return Nullable!int.init;
  }
}

/// Total order for ORDER BY: booleans, numbers, texts, JSON, then NULLs (NULLs last in both directions
/// is handled by the caller; here NULL is simply the largest).
int sortOrder(const Value a, const Value b) pure nothrow {
  immutable ra = rank(a), rb = rank(b);
  if (ra != rb) {
    return ra < rb ? -1 : 1;
  }
  if (a.kind == ValueKind.json && b.kind == ValueKind.json) {
    return cmp(a.asText, b.asText);
  }
  auto c = compareValues(a, b);
  return c.isNull ? 0 : c.get;
}

private int rank(const Value v) pure nothrow @nogc {
  final switch (v.kind) {
    case ValueKind.boolean:
      return 0;
    case ValueKind.integer, ValueKind.floating:
      return 1;
    case ValueKind.text:
      return 2;
    case ValueKind.json:
      return 3;
    case ValueKind.null_:
      return 4;
  }
}

private int threeWay(T)(T a, T b) pure nothrow @nogc {
  return a < b ? -1 : (a > b ? 1 : 0);
}

unittest {
  assert(compareValues(Value.integer(2), Value.floating(1.5)).get > 0);
  assert(compareValues(Value.text("a"), Value.text("b")).get < 0);
  assert(compareValues(Value.integer(1), Value.text("1")).isNull);
  assert(compareValues(Value.null_, Value.null_).isNull);
  assert(sortOrder(Value.null_, Value.integer(1)) > 0);
  assert(sortOrder(Value.integer(3), Value.integer(1)) > 0);
}
