/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Outbound (driven) ports: what the application needs from infrastructure. Adapters implement them.
module uim.databases.geodb.application.ports.outbound;

import uim.databases.geodb.domain;
import std.typecons : Nullable;

/// Storage of locations, optionally backed by a spatial index.
interface ILocationRepository {
@safe:
  /// Inserts the location or replaces the one with the same id.
  void save(GeoLocation location);

  Nullable!GeoLocation findById(string id);

  /// False if there was nothing to remove.
  bool remove(string id);

  bool contains(string id);

  GeoLocation[] findAll();

  /// Locations whose point lies inside `bounds` (which may cross the antimeridian), in any order.
  /// This is where adapters use their spatial index; the application filters radii on top of it.
  GeoLocation[] findInBounds(GeoBounds bounds);

  size_t count();
}
