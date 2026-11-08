/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Wire format of the REST API. Separate from the application DTOs so the HTTP contract can evolve on its own.
module uim.databases.geodb.presentation.rest.models;

import vibe.data.json : Json;
import vibe.data.serialization : optional;

@safe:

// --- Requests ---

struct RestLocationRequest {
  string id;
  string name;
  double latitude;
  double longitude;
  @optional Json metadata;
}

struct RestLocationUpdateRequest {
  string name;
  double latitude;
  double longitude;
  @optional Json metadata;
}

struct RestNearbyRequest {
  double latitude;
  double longitude;
  double radiusMeters;
}

struct RestBoundsRequest {
  double minLat;
  double maxLat;
  double minLon;
  double maxLon;
}

struct RestNearestRequest {
  double latitude;
  double longitude;
  ulong count;
}

struct RestDistanceRequest {
  double lat1;
  double lon1;
  double lat2;
  double lon2;
}

// --- Responses ---

struct RestLocation {
  string id;
  string name;
  double latitude;
  double longitude;
  Json metadata;
}

struct RestLocationMatch {
  string id;
  string name;
  double latitude;
  double longitude;
  Json metadata;
  double distanceMeters;
}

struct RestLocationList {
  RestLocation[] locations;
  ulong count;
}

struct RestNearbyResponse {
  double latitude;
  double longitude;
  double radiusMeters;
  RestLocationMatch[] locations;
  ulong count;
}

struct RestBoundsResponse {
  RestBoundsRequest bounds;
  RestLocation[] locations;
  ulong count;
}

struct RestNearestResponse {
  double latitude;
  double longitude;
  ulong requested;
  RestLocationMatch[] locations;
  ulong found;
}

struct RestDistanceResponse {
  double distanceMeters;
  double distanceKilometers;
  double distanceMiles;
}

struct RestStatsResponse {
  string databaseName;
  ulong locationCount;
}

struct RestStatus {
  string status;
}

struct RestRemoved {
  string id;
  string message;
}
