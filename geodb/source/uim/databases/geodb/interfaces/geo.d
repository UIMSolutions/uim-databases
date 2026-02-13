/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.interfaces.geo;

@safe:

/// Geographic point
struct GeoPoint {
  double latitude;
  double longitude;
  
  /// Calculate distance to another point (in meters, using Haversine formula)
  double distanceTo(GeoPoint other) const;
}

/// Geographic bounding box
struct GeoBounds {
  double minLat;
  double maxLat;
  double minLon;
  double maxLon;
  
  /// Check if point is within bounds
  bool contains(GeoPoint point) const;
  
  /// Get center point
  GeoPoint center() const;
}

/// Geographic location with metadata
interface IGeoLocation {
  /// Location ID
  string id();
  
  /// Get location name
  string name();
  
  /// Get geographic point
  GeoPoint point();
  
  /// Get location metadata
  Json metadata();
  
  /// Calculate distance to point (meters)
  double distanceToPoint(GeoPoint point) const;
}

/// Geographic spatial index
interface IGeoIndex {
  /// Index a location
  void index(IGeoLocation location);
  
  /// Remove location from index
  void remove(string locationId);
  
  /// Find locations within radius (meters) of a point
  string[] nearbyLocations(GeoPoint center, double radiusMeters);
  
  /// Find locations within bounding box
  string[] locationsInBounds(GeoBounds bounds);
  
  /// Find nearest N locations to a point
  string[] nearestLocations(GeoPoint center, size_t count);
  
  /// Get location by ID
  IGeoLocation getLocation(string id);
  
  /// Get all locations
  IGeoLocation[] getAllLocations();
  
  /// Clear index
  void clear();
  
  /// Get size
  ulong size() const;
}

/// Geographic database
interface IGeoDatabase {
  /// Add location
  void addLocation(IGeoLocation location);
  
  /// Get location
  IGeoLocation getLocation(string id);
  
  /// Remove location
  void removeLocation(string id);
  
  /// Check if location exists
  bool hasLocation(string id);
  
  /// Get all locations
  IGeoLocation[] getAllLocations();
  
  /// Find nearby locations
  IGeoLocation[] findNearby(GeoPoint center, double radiusMeters);
  
  /// Find in bounds
  IGeoLocation[] findInBounds(GeoBounds bounds);
  
  /// Find nearest
  IGeoLocation[] findNearest(GeoPoint center, size_t count);
  
  /// Get location count
  ulong count() const;
}
