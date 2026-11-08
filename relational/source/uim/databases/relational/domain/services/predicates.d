/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.services.predicates;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.services.comparison;
import uim.databases.relational.domain.types;
import std.algorithm : all, canFind;
import std.conv : to;

@safe:

/// SQL semantics: a comparison with NULL is never true; use IS NULL / IS NOT NULL.
bool matches(const Condition condition, const RowData row) {
  auto found = condition.column in row;
  const Value cell = found is null ? Value.null_ : *found;

  final switch (condition.op) {
    case ComparisonOperator.isNull:
      return cell.isNull;
    case ComparisonOperator.isNotNull:
      return !cell.isNull;
    case ComparisonOperator.equal:
      return !cell.isNull && cell == condition.operand;
    case ComparisonOperator.notEqual:
      return !cell.isNull && cell != condition.operand;
    case ComparisonOperator.greater:
      return ordered(cell, condition.operand, (int c) => c > 0);
    case ComparisonOperator.less:
      return ordered(cell, condition.operand, (int c) => c < 0);
    case ComparisonOperator.greaterOrEqual:
      return ordered(cell, condition.operand, (int c) => c >= 0);
    case ComparisonOperator.lessOrEqual:
      return ordered(cell, condition.operand, (int c) => c <= 0);
    case ComparisonOperator.like:
      return cell.kind == ValueKind.text && likeMatch(cell.asText, condition.operand.asText);
    case ComparisonOperator.in_:
      return !cell.isNull && condition.candidates.canFind(cell);
  }
}

/// True when every condition matches (an empty list matches every row).
bool matchesAll(const Condition[] conditions, const RowData row) {
  return conditions.all!(c => matches(c, row));
}

/// SQL LIKE: `%` matches any sequence, `_` exactly one character; everything else is literal.
/// Case-sensitive. Runs in O(text × pattern) without building regular expressions from user input.
bool likeMatch(string text, string pattern) {
  immutable t = text.to!dstring, p = pattern.to!dstring;
  size_t ti, pi;
  ptrdiff_t star = -1;
  size_t mark;
  while (ti < t.length) {
    if (pi < p.length && (p[pi] == '_' || p[pi] == t[ti])) {
      ti++;
      pi++;
    } else if (pi < p.length && p[pi] == '%') {
      star = pi++;
      mark = ti;
    } else if (star >= 0) {
      pi = star + 1;
      ti = ++mark;
    } else {
      return false;
    }
  }
  while (pi < p.length && p[pi] == '%') {
    pi++;
  }
  return pi == p.length;
}

private bool ordered(const Value cell, const Value operand, scope bool delegate(int) @safe accept) {
  auto c = compareValues(cell, operand);
  return !c.isNull && accept(c.get);
}

unittest {
  RowData row = ["name": Value.text("Ada Lovelace"), "age": Value.integer(36), "nick": Value.null_];
  alias Op = ComparisonOperator;

  assert(matches(Condition("age", Op.greater, Value.integer(30)), row));
  assert(matches(Condition("age", Op.equal, Value.floating(36.0)), row));
  assert(!matches(Condition("age", Op.greater, Value.text("30")), row)); // incomparable
  assert(matches(Condition("nick", Op.isNull), row));
  assert(matches(Condition("missing", Op.isNull), row));
  assert(!matches(Condition("nick", Op.notEqual, Value.text("x")), row)); // NULL never compares
  assert(matches(Condition("age", Op.in_, Value.null_, [Value.integer(1), Value.integer(36)]), row));
  assert(matches(Condition("name", Op.like, Value.text("Ada%")), row));
  assert(matchesAll([], row));

  assert(likeMatch("abc", "a_c") && likeMatch("abc", "%") && likeMatch("", "%"));
  assert(likeMatch("a.c", "a.c") && !likeMatch("abc", "a.c")); // '.' is literal, not a regex
  assert(likeMatch("Müller", "M_ller"));
  assert(!likeMatch("abc", "ab") && likeMatch("aXbYc", "a%b%c"));
}
