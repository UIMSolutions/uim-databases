/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.infrastructure.persistence.memory;

import uim.databases.geodb.application.ports.outbound : ILocationRepository;
import uim.databases.geodb.domain;
import std.algorithm.comparison : min;
import std.exception : enforce;
import std.math : ceil, floor, isFinite;
import std.typecons : Nullable, nullable;

@safe:

/// Outbound adapter: keeps locations in memory, indexed by a fixed lat/lon grid.
///
/// A bounds query visits only the grid cells overlapping the box, unless the box covers more cells
/// than are occupied, in which case a plain scan is cheaper. No method yields to the vibe.d event
/// loop, so calls are atomic for fibers on the same thread; share an instance across threads only
/// behind a lock.
final class InMemoryLocationRepository : ILocationRepository {
  private {
    GeoLocation[string] _locations;
    bool[string][long] _cells; // cell key -> ids in that cell
    long[string] _cellOf; // id -> cell key
    double _cellDegrees;
    long _latCells;
    long _lonCells;
  }

  /// `cellDegrees`: edge length of a grid cell. Smaller cells speed up small-area queries on dense data.
  this(double cellDegrees = 1.0) {
    enforce(isFinite(cellDegrees) && cellDegrees > 0 && cellDegrees <= 180,
      "Grid cell size must be in (0, 180] degrees");
    _cellDegrees = cellDegrees;
    _latCells = cast(long) ceil(180.0 / cellDegrees);
    _lonCells = cast(long) ceil(360.0 / cellDegrees);
  }

  void save(GeoLocation location) {
    unindex(location.id);
    _locations[location.id] = location;
    long key = cellKey(latIndex(location.point.latitude), lonIndex(location.point.longitude));
    _cells[key][location.id] = true;
    _cellOf[location.id] = key;
  }

  Nullable!GeoLocation findById(string id) {
    if (auto found = id in _locations) {
      return nullable(*found);
    }
    return Nullable!GeoLocation.init;
  }

  bool remove(string id) {
    unindex(id);
    return _locations.remove(id);
  }

  bool contains(string id) {
    return (id in _locations) !is null;
  }

  GeoLocation[] findAll() {
    return _locations.values;
  }

  GeoLocation[] findInBounds(GeoBounds bounds) {
    GeoLocation[] result;
    foreach (box; bounds.split()) {
      collect(box, result);
    }
    return result;
  }

  size_t count() {
    return _locations.length;
  }

  /// Number of non-empty grid cells (for diagnostics and tests).
  size_t occupiedCells() const {
    return _cells.length;
  }

  private void collect(GeoBounds box, ref GeoLocation[] result) {
    immutable latFrom = latIndex(box.minLat), latTo = latIndex(box.maxLat);
    immutable lonFrom = lonIndex(box.minLon), lonTo = lonIndex(box.maxLon);

    if ((latTo - latFrom + 1) * (lonTo - lonFrom + 1) >= _cells.length) {
      foreach (location; _locations.byValue) {
        if (box.contains(location.point)) {
          result ~= location;
        }
      }
      return;
    }

    foreach (lat; latFrom .. latTo + 1) {
      foreach (lon; lonFrom .. lonTo + 1) {
        if (auto ids = cellKey(lat, lon) in _cells) {
          foreach (id; (*ids).byKey) {
            auto location = _locations[id];
            if (box.contains(location.point)) {
              result ~= location;
            }
          }
        }
      }
    }
  }

  private void unindex(string id) {
    if (auto key = id in _cellOf) {
      if (auto ids = *key in _cells) {
        (*ids).remove(id);
        if ((*ids).length == 0) {
          _cells.remove(*key);
        }
      }
      _cellOf.remove(id);
    }
  }

  private long latIndex(double latitude) const pure nothrow @nogc {
    return min(cast(long) floor((latitude - minLatitude) / _cellDegrees), _latCells - 1);
  }

  private long lonIndex(double longitude) const pure nothrow @nogc {
    return min(cast(long) floor((longitude - minLongitude) / _cellDegrees), _lonCells - 1);
  }

  private long cellKey(long latIdx, long lonIdx) const pure nothrow @nogc {
    return latIdx * _lonCells + lonIdx;
  }
}

unittest {
  import std.algorithm : map, sort;
  import std.array : array;
  import std.exception : assertThrown;

  auto repository = new InMemoryLocationRepository(1.0);
  repository.save(GeoLocation("paris", "Paris", GeoPoint(48.8566, 2.3522)));
  repository.save(GeoLocation("london", "London", GeoPoint(51.5074, -0.1278)));
  repository.save(GeoLocation("suva", "Suva", GeoPoint(-18.1416, 178.4419)));
  repository.save(GeoLocation("apia", "Apia", GeoPoint(-13.8333, -171.7667)));
  repository.save(GeoLocation("pole", "North Pole", GeoPoint(90, 180)));
  assert(repository.count == 5 && repository.occupiedCells == 5);

  string[] ids(GeoLocation[] found) {
    return found.map!(l => l.id).array.sort.release;
  }

  // Small box: cell lookup.
  assert(ids(repository.findInBounds(GeoBounds(48, 49, 2, 3))) == ["paris"]);
  // Box crossing the antimeridian.
  assert(ids(repository.findInBounds(GeoBounds(-20, -10, 175, -170))) == ["apia", "suva"]);
  // Edge of the grid.
  assert(ids(repository.findInBounds(GeoBounds(89, 90, 179, 180))) == ["pole"]);
  // Large box: full scan.
  assert(repository.findInBounds(GeoBounds.world).length == 5);

  // Moving a location re-indexes it.
  auto paris = repository.findById("paris").get;
  paris.moveTo(GeoPoint(10, 10));
  repository.save(paris);
  assert(repository.findInBounds(GeoBounds(48, 49, 2, 3)).length == 0);
  assert(ids(repository.findInBounds(GeoBounds(9.5, 10.5, 9.5, 10.5))) == ["paris"]);
  assert(repository.occupiedCells == 5);

  // A copy obtained from the repository does not change the stored entity until it is saved.
  auto london = repository.findById("london").get;
  london.rename("changed");
  assert(repository.findById("london").get.name == "London");

  assert(repository.remove("paris") && !repository.remove("paris"));
  assert(repository.findById("paris").isNull && !repository.contains("paris"));
  assert(repository.occupiedCells == 4);

  assertThrown(new InMemoryLocationRepository(0));
}
