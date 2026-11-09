/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.domain.types.identifier;

import uim.databases.object.domain.exceptions;
import std.algorithm : any;
import std.ascii : isAlpha, isAlphaNum;
import std.uni : isControl;

@safe:

enum size_t maxIdLength = 256;

/// Collection names: a letter or `_`, then letters, digits, `_` or `-`; at most 128 characters.
bool isCollectionName(string name) pure nothrow @nogc {
  if (name.length == 0 || name.length > 128 || !(isAlpha(name[0]) || name[0] == '_')) {
    return false;
  }
  foreach (c; name[1 .. $]) {
    if (!(isAlphaNum(c) || c == '_' || c == '-')) {
      return false;
    }
  }
  return true;
}

/// Throws: ValidationException.
void requireCollectionName(string name) {
  if (!isCollectionName(name)) {
    throw new ValidationException("Invalid collection name '" ~ name
        ~ "': use letters, digits, '_' or '-' and start with a letter or '_'");
  }
}

/// Document ids: any non-empty text up to 256 characters without control characters or '/'.
/// Throws: ValidationException.
void requireDocumentId(string id) {
  if (id.length == 0 || id.length > maxIdLength || id.any!(c => c == '/' || isControl(c))) {
    throw new ValidationException("Invalid document id '" ~ id
        ~ "': use 1 to 256 characters without '/' or control characters");
  }
}

unittest {
  import std.exception : assertThrown;

  assert(isCollectionName("users-2026") && isCollectionName("_x"));
  assert(!isCollectionName("1users") && !isCollectionName("a b") && !isCollectionName(""));
  requireDocumentId("user:42 (Ä)");
  assertThrown!ValidationException(requireDocumentId(""));
  assertThrown!ValidationException(requireDocumentId("a/b"));
  assertThrown!ValidationException(requireDocumentId("a\nb"));
}
