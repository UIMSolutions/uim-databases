/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.entities.location;

import uim.databases.geodb.domain.exceptions;
import uim.databases.geodb.domain.services.geometry : haversine;
import uim.databases.geodb.domain.values;
import std.json : JSONType, JSONValue;
import std.string : strip;

@safe:

/// Entity: a named place identified by `id`, with free-form JSON object metadata.
/// It is a struct, so repositories hold copies and a change only takes effect once it is saved.
struct GeoLocation {
  private {
    string _id;
    string _name;
    GeoPoint _point;
    JSONValue _metadata;
  }

  /// Throws: GeoArgumentException for an empty id or metadata that is not a JSON object.
  this(string id, string name, GeoPoint point, JSONValue metadata = JSONValue.emptyObject) {
    if (id.strip.length == 0) {
      throw new GeoArgumentException("Location id must not be empty");
    }
    _id = id;
    _name = name;
    _point = point;
    setMetadata(metadata);
  }

  string id() const pure nothrow @nogc {
    return _id;
  }

  string name() const pure nothrow @nogc {
    return _name;
  }

  GeoPoint point() const pure nothrow @nogc {
    return _point;
  }

  inout(JSONValue) metadata() inout pure nothrow @nogc {
    return _metadata;
  }

  void rename(string name) pure nothrow @nogc {
    _name = name;
  }

  void moveTo(GeoPoint point) pure nothrow @nogc {
    _point = point;
  }

  /// `null` (or an uninitialised value) clears the metadata to an empty object.
  void setMetadata(JSONValue metadata) {
    switch (metadata.type) {
      case JSONType.null_:
        _metadata = JSONValue.emptyObject;
        break;
      case JSONType.object:
        _metadata = metadata;
        break;
      default:
        throw new GeoArgumentException("Location metadata must be a JSON object");
    }
  }

  Distance distanceTo(GeoPoint point) const pure nothrow @nogc {
    return haversine(_point, point);
  }
}

unittest {
  import std.exception : assertThrown;

  auto paris = GeoLocation("paris", "Paris", GeoPoint(48.8566, 2.3522), JSONValue(["country": "France"]));
  assert(paris.id == "paris");
  assert(paris.metadata["country"].str == "France");

  paris.setMetadata(JSONValue(null));
  assert(paris.metadata == JSONValue.emptyObject);

  assertThrown!GeoArgumentException(GeoLocation(" ", "x", GeoPoint(0, 0)));
  assertThrown!GeoArgumentException(GeoLocation("x", "x", GeoPoint(0, 0), JSONValue(42)));
}
