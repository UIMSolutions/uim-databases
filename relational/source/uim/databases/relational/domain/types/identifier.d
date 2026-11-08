/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.identifier;

import uim.databases.relational.domain.exceptions;
import std.ascii : isAlpha, isAlphaNum;

@safe:

/// Table and column names: a letter or `_`, then letters, digits or `_`; at most 128 characters.
/// This keeps joined column names (`table.column`) unambiguous.
bool isIdentifier(string name) pure nothrow @nogc {
  if (name.length == 0 || name.length > 128 || !(isAlpha(name[0]) || name[0] == '_')) {
    return false;
  }
  foreach (c; name[1 .. $]) {
    if (!(isAlphaNum(c) || c == '_')) {
      return false;
    }
  }
  return true;
}

/// Throws: SchemaException naming `what` ("table", "column", ...) when `name` is not an identifier.
void requireIdentifier(string name, string what) {
  if (!isIdentifier(name)) {
    throw new SchemaException("Invalid " ~ what ~ " name '" ~ name
        ~ "': use letters, digits and '_' and start with a letter or '_'");
  }
}

unittest {
  assert(isIdentifier("user_id") && isIdentifier("_x1"));
  assert(!isIdentifier("") && !isIdentifier("1a") && !isIdentifier("a.b") && !isIdentifier("a b"));
}
