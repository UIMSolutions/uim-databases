/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.domain.entities.document;

import uim.databases.object.domain.exceptions;
import uim.databases.object.domain.services.jsonvalues : deepCopy;
import uim.databases.object.domain.types.identifier : requireDocumentId;
import std.datetime.systime : SysTime;
import std.json : JSONType, JSONValue;

@safe:

/// Entity: a JSON object with an id and timestamps. Its data is copied on the way in and out,
/// so it changes only through its collection (which keeps the indexes in step).
struct Document {
  private {
    string _id;
    JSONValue _data;
    SysTime _createdAt;
    SysTime _updatedAt;
    ulong _sequence;
  }

  /// Throws: ValidationException for an invalid id or data that is not a JSON object.
  this(string id, JSONValue data, SysTime createdAt) {
    requireDocumentId(id);
    requireObject(data);
    _id = id;
    _data = deepCopy(data);
    _createdAt = createdAt;
    _updatedAt = createdAt;
  }

  string id() const pure nothrow @nogc {
    return _id;
  }

  JSONValue data() const {
    return deepCopy(_data);
  }

  SysTime createdAt() const pure nothrow {
    return _createdAt;
  }

  SysTime updatedAt() const pure nothrow {
    return _updatedAt;
  }

  /// Position in the collection's insertion order.
  ulong sequence() const pure nothrow @nogc {
    return _sequence;
  }

package(uim.databases.object.domain):
  /// Stored data without a copy, for matching and indexing inside the aggregate.
  JSONValue raw() {
    return _data;
  }

  void assignSequence(ulong sequence) pure nothrow @nogc {
    _sequence = sequence;
  }

  void replaceData(JSONValue data, SysTime updatedAt) {
    requireObject(data);
    _data = deepCopy(data);
    _updatedAt = updatedAt;
  }
}

/// Throws: ValidationException.
void requireObject(JSONValue data) {
  if (data.type != JSONType.object) {
    throw new ValidationException("A document must be a JSON object");
  }
}

unittest {
  import std.exception : assertThrown;
  import std.json : parseJSON;

  auto input = parseJSON(`{"a":[1]}`);
  auto doc = Document("x", input, SysTime(0));
  input["a"] = JSONValue(2);
  assert(doc.data == parseJSON(`{"a":[1]}`)); // copied in
  auto output = doc.data;
  output["a"] = JSONValue(3);
  assert(doc.data == parseJSON(`{"a":[1]}`)); // copied out

  assertThrown!ValidationException(Document("x", parseJSON("[1]"), SysTime(0)));
  assertThrown!ValidationException(Document("", parseJSON("{}"), SysTime(0)));
}
