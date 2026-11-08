/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Plain data crossing the inbound ports. Commands and queries carry raw numbers; the application
/// turns them into domain values, so validation stays in one place.
module uim.databases.geodb.application.dtos;

import uim.databases.geodb.domain;
import std.json : JSONValue;

@safe:

// --- Commands ---

struct AddLocationCommand {
  string id;
  string name;
  double latitude;
  double longitude;
  JSONValue metadata;
}

struct UpdateLocationCommand {
  string name;
  double latitude;
  double longitude;
  JSONValue metadata;
}

// --- Queries ---

struct NearbyQuery {
  double latitude;
  double longitude;
  double radiusMeters;
}

struct BoundsQuery {
  double minLat;
  double maxLat;
  double minLon;
  double maxLon;
}

struct NearestQuery {
  double latitude;
  double longitude;
  size_t count;
}

struct DistanceQuery {
  double lat1;
  double lon1;
  double lat2;
  double lon2;
}

// --- Results ---

struct LocationData {
  string id;
  string name;
  double latitude;
  double longitude;
  JSONValue metadata;

  static LocationData from(const GeoLocation location) {
    return LocationData(location.id, location.name, location.point.latitude, location.point.longitude,
      location.metadata);
  }
}

/// A location together with its distance from the query point.
struct LocationMatch {
  LocationData location;
  double distanceMeters;
}

struct DistanceData {
  double meters;
  double kilometers;
  double miles;

  static DistanceData from(Distance distance) pure nothrow @nogc {
    return DistanceData(distance.meters, distance.kilometers, distance.miles);
  }
}

struct GeoStatistics {
  string databaseName;
  size_t locationCount;
}
