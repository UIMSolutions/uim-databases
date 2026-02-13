/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.classes.location;

import uim.databases.geodb;
import std.math;
import std.json;
import std.conv;

@safe:

// Constants
private enum double EARTH_RADIUS_METERS = 6371000.0;  // Earth radius in meters
private enum double MIN_LAT = -90.0;
private enum double MAX_LAT = 90.0;
private enum double MIN_LON = -180.0;
private enum double MAX_LON = 180.0;

/// Geographic point implementation
double calculateDistance(GeoPoint p1, GeoPoint p2) pure {
  if (p1.latitude !in [MIN_LAT, MAX_LAT] || p1.longitude !in [MIN_LON, MAX_LON]) {
    throw new InvalidCoordinatesException(p1.latitude, p1.longitude);
  }
  if (p2.latitude !in [MIN_LAT, MAX_LAT] || p2.longitude !in [MIN_LON, MAX_LON]) {
    throw new InvalidCoordinatesException(p2.latitude, p2.longitude);
  }
  
  // Haversine formula
  double lat1 = p1.latitude * PI / 180.0;
  double lat2 = p2.latitude * PI / 180.0;
  double deltaLat = (p2.latitude - p1.latitude) * PI / 180.0;
  double deltaLon = (p2.longitude - p1.longitude) * PI / 180.0;
  
  double a = sin(deltaLat/2) * sin(deltaLat/2) +
    cos(lat1) * cos(lat2) * sin(deltaLon/2) * sin(deltaLon/2);
  double c = 2 * asin(sqrt(a));
  
  return EARTH_RADIUS_METERS * c;
}

/// Check valid coordinates
bool isValidCoordinates(double lat, double lon) pure {
  return lat >= MIN_LAT && lat <= MAX_LAT && lon >= MIN_LON && lon <= MAX_LON;
}

/// Bounding box operations
bool boundingBoxContains(GeoBounds bounds, GeoPoint point) pure {
  return point.latitude >= bounds.minLat && point.latitude <= bounds.maxLat &&
         point.longitude >= bounds.minLon && point.longitude <= bounds.maxLon;
}

GeoPoint boundingBoxCenter(GeoBounds bounds) pure {
  return GeoPoint(
    (bounds.minLat + bounds.maxLat) / 2.0,
    (bounds.minLon + bounds.maxLon) / 2.0
  );
}

/// Get bounding box for point + radius
GeoBounds boundingBoxForRadius(GeoPoint center, double radiusMeters) pure {
  double latChange = (radiusMeters / EARTH_RADIUS_METERS) * 180.0 / PI;
  double lonChange = (radiusMeters / EARTH_RADIUS_METERS) * 180.0 / PI / cos(center.latitude * PI / 180.0);
  
  return GeoBounds(
    center.latitude - latChange,
    center.latitude + latChange,
    center.longitude - lonChange,
    center.longitude + lonChange
  );
}

/// Geographic location implementation
class GeoLocation : IGeoLocation {
  private {
    string _id;
    string _name;
    GeoPoint _point;
    Json _metadata;
  }

  this(string id, string name, GeoPoint point, Json metadata = Json.emptyObject) {
    if (!isValidCoordinates(point.latitude, point.longitude)) {
      throw new InvalidCoordinatesException(point.latitude, point.longitude);
    }
    _id = id;
    _name = name;
    _point = point;
    _metadata = metadata;
  }

  override string id() const {
    return _id;
  }

  override string name() const {
    return _name;
  }

  override GeoPoint point() const {
    return _point;
  }

  override Json metadata() const {
    return _metadata;
  }

  override double distanceToPoint(GeoPoint point) const {
    return calculateDistance(_point, point);
  }

  /// Update metadata
  void setMetadata(Json metadata) {
    _metadata = metadata;
  }
}
