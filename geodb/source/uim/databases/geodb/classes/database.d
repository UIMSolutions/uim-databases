/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.classes.database;

import uim.databases.geodb;

@safe:

/// Geospatial database
class GeoDatabase : IGeoDatabase {
  private {
    string _name;
    IGeoIndex _index;
  }

  this(string name = "geodb") {
    _name = name;
    _index = new GeoIndex();
  }

  override void addLocation(IGeoLocation location) {
    if (hasLocation(location.id())) {
      throw new GeoDatabaseException("Location already exists: " ~ location.id());
    }
    _index.index(location);
  }

  override IGeoLocation getLocation(string id) {
    return _index.getLocation(id);
  }

  override void removeLocation(string id) {
    _index.remove(id);
  }

  override bool hasLocation(string id) {
    try {
      _index.getLocation(id);
      return true;
    } catch (LocationNotFoundException) {
      return false;
    }
  }

  override IGeoLocation[] getAllLocations() {
    return _index.getAllLocations();
  }

  override IGeoLocation[] findNearby(GeoPoint center, double radiusMeters) {
    if (radiusMeters < 0) {
      throw new GeoOperationException("Radius must be positive");
    }
    
    auto ids = _index.nearbyLocations(center, radiusMeters);
    IGeoLocation[] results;
    
    foreach (id; ids) {
      results ~= _index.getLocation(id);
    }
    
    return results;
  }

  override IGeoLocation[] findInBounds(GeoBounds bounds) {
    auto ids = _index.locationsInBounds(bounds);
    IGeoLocation[] results;
    
    foreach (id; ids) {
      results ~= _index.getLocation(id);
    }
    
    return results;
  }

  override IGeoLocation[] findNearest(GeoPoint center, size_t count) {
    auto ids = _index.nearestLocations(center, count);
    IGeoLocation[] results;
    
    foreach (id; ids) {
      results ~= _index.getLocation(id);
    }
    
    return results;
  }

  override ulong count() const {
    return _index.size();
  }

  /// Get database name
  string name() const {
    return _name;
  }

  /// Get database statistics
  GeoStats getStats() const {
    GeoStats stats;
    stats.databaseName = _name;
    stats.locationCount = _index.size();
    return stats;
  }
}

/// Database statistics
struct GeoStats {
  string databaseName;
  ulong locationCount;
}
