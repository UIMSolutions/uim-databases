/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.classes.index;

import uim.databases.geodb;
import std.algorithm;
import std.array;

@safe:

/// Spatial index for geographic locations
class GeoIndex : IGeoIndex {
  private {
    IGeoLocation[string] _locations;
  }

  override void index(IGeoLocation location) {
    _locations[location.id()] = location;
  }

  override void remove(string locationId) {
    if (locationId !in _locations) {
      throw new LocationNotFoundException(locationId);
    }
    _locations.remove(locationId);
  }

  override string[] nearbyLocations(GeoPoint center, double radiusMeters) {
    string[] results;
    
    foreach (id, location; _locations) {
      double distance = location.distanceToPoint(center);
      if (distance <= radiusMeters) {
        results ~= id;
      }
    }
    
    return results;
  }

  override string[] locationsInBounds(GeoBounds bounds) {
    string[] results;
    
    foreach (id, location; _locations) {
      if (boundingBoxContains(bounds, location.point())) {
        results ~= id;
      }
    }
    
    return results;
  }

  override string[] nearestLocations(GeoPoint center, size_t count) {
    if (_locations.length == 0) {
      return [];
    }

    // Calculate distances for all locations
    struct LocationDistance {
      string id;
      double distance;
    }

    LocationDistance[] distances;
    foreach (id, location; _locations) {
      distances ~= LocationDistance(id, location.distanceToPoint(center));
    }

    // Sort by distance
    distances.sort!((a, b) => a.distance < b.distance);

    // Return top N IDs
    size_t limit = count > distances.length ? distances.length : count;
    string[] results;
    for (size_t i = 0; i < limit; i++) {
      results ~= distances[i].id;
    }
    
    return results;
  }

  override IGeoLocation getLocation(string id) {
    if (id !in _locations) {
      throw new LocationNotFoundException(id);
    }
    return _locations[id];
  }

  override IGeoLocation[] getAllLocations() {
    return _locations.values;
  }

  override void clear() {
    _locations.clear();
  }

  override ulong size() const {
    return _locations.length;
  }
}
