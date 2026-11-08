/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Test doubles for the outbound ports, so application tests never depend on infrastructure.
module uim.databases.geodb.application.testing;

version (unittest):

import uim.databases.geodb.application.ports.outbound;
import uim.databases.geodb.domain;
import std.algorithm : filter;
import std.array : array;
import std.typecons : Nullable, nullable;

@safe:

/// Unindexed in-memory repository: the simplest correct implementation of the port.
final class FakeLocationRepository : ILocationRepository {
  private GeoLocation[string] _locations;

  void save(GeoLocation location) {
    _locations[location.id] = location;
  }

  Nullable!GeoLocation findById(string id) {
    if (auto found = id in _locations) {
      return nullable(*found);
    }
    return Nullable!GeoLocation.init;
  }

  bool remove(string id) {
    return _locations.remove(id);
  }

  bool contains(string id) {
    return (id in _locations) !is null;
  }

  GeoLocation[] findAll() {
    return _locations.values;
  }

  GeoLocation[] findInBounds(GeoBounds bounds) {
    return _locations.values.filter!(l => bounds.contains(l.point)).array;
  }

  size_t count() {
    return _locations.length;
  }
}
