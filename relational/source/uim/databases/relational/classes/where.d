/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes;

import uim.databases.relational;

@safe:

/// WHERE clause condition
struct WhereCondition {
  string column;
  string op; // =, !=, >, <, >=, <=, LIKE, IN, IS NULL, IS NOT NULL
  Json value;

  bool matches(Json row) {
    if (column !in row) {
      return op == "IS NULL";
    }

    auto cellValue = row[column];

    switch (op) {
    case "=":
      return jsonEquals(cellValue, value);
    case "!=":
      return !jsonEquals(cellValue, value);
    case ">":
      return jsonCompare(cellValue, value) > 0;
    case "<":
      return jsonCompare(cellValue, value) < 0;
    case ">=":
      return jsonCompare(cellValue, value) >= 0;
    case "<=":
      return jsonCompare(cellValue, value) <= 0;
    case "LIKE":
      if (cellValue.type == Json.Type.string && value.type == Json.Type.string) {
        string pattern = value.get!string;
        string str = cellValue.get!string;
        return matchesLike(str, pattern);
      }
      return false;
    case "IN":
      if (value.type == Json.Type.array) {
        foreach (v; value) {
          if (jsonEquals(cellValue, v))
            return true;
        }
      }
      return false;
    case "IS NULL":
      return cellValue.type == Json.Type.null_;
    case "IS NOT NULL":
      return cellValue.type != Json.Type.null_;
    default:
      return false;
    }
  }

  private bool matchesLike(string str, string pattern) {
    // Simple LIKE implementation: % = wildcard
    pattern = pattern.replace("%", ".*");
    import std.regex;

    auto re = regex("^" ~ pattern ~ "$");
    return !matchFirst(str, re).empty;
  }

  private bool jsonEquals(Json a, Json b) {
    if (a.type != b.type)
      return false;

    final switch (a.type) {
    case Json.Type.undefined:
    case Json.Type.null_:
      return true;
    case Json.Type.bool_:
      return a.get!bool == b.get!bool;
    case Json.Type.int_:
      return a.get!long == b.get!long;
    case Json.Type.float_:
      return a.get!double == b.get!double;
    case Json.Type.string:
      return a.get!string == b.get!string;
    case Json.Type.array:
    case Json.Type.object:
      return a.toString() == b.toString();
    }
  }

  private int jsonCompare(Json a, Json b) {
    if (a.type == Json.Type.int_ && b.type == Json.Type.int_) {
      long av = a.get!long;
      long bv = b.get!long;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    if ((a.type == Json.Type.float_ || a.type == Json.Type.int_) &&
      (b.type == Json.Type.float_ || b.type == Json.Type.int_)) {
      double av = a.type == Json.Type.float_ ? a.get!double : a.get!long;
      double bv = b.type == Json.Type.float_ ? b.get!double : b.get!long;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    if (a.type == Json.Type.string && b.type == Json.Type.string) {
      string av = a.get!string;
      string bv = b.get!string;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    return 0;
  }
}
