/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.api.rest;

import uim.databases.geodb;
import vibe.d;
import std.conv;

@safe:

/// Request/Response structs
struct AddLocationRequest {
  string id;
  string name;
  double latitude;
  double longitude;
  Json metadata;
}

struct LocationResponse {
  bool success;
  string id;
  string name;
  double latitude;
  double longitude;
  Json metadata;
  string error;
}

struct NearbyRequest {
  double latitude;
  double longitude;
  double radiusMeters;
}

struct NearbyResponse {
  bool success;
  double latitude;
  double longitude;
  double radiusMeters;
  LocationResponse[] locations;
  ulong count;
  string error;
}

struct BoundsRequest {
  double minLat;
  double maxLat;
  double minLon;
  double maxLon;
}

struct BoundsResponse {
  bool success;
  BoundsRequest bounds;
  LocationResponse[] locations;
  ulong count;
  string error;
}

struct NearestRequest {
  double latitude;
  double longitude;
  ulong count;
}

struct NearestResponse {
  bool success;
  double latitude;
  double longitude;
  ulong requested;
  LocationResponse[] locations;
  ulong found;
  string error;
}

struct DistanceRequest {
  double lat1;
  double lon1;
  double lat2;
  double lon2;
}

struct DistanceResponse {
  bool success;
  double distanceMeters;
  double distanceKilometers;
  double distanceMiles;
  string error;
}

struct DatabaseStatsResponse {
  string databaseName;
  ulong locationCount;
}

/// REST API for Geographic Database
class GeoDatabaseAPI {
  private IGeoDatabase db;

  this(IGeoDatabase database) {
    this.db = database;
  }

  // POST /geo/location - Add location
  @method(HTTPMethod.POST)
  @path("/geo/location")
  Json addLocation(AddLocationRequest req) {
    Json response = Json.emptyObject;
    try {
      auto location = new GeoLocation(req.id, req.name, GeoPoint(req.latitude, req.longitude), req.metadata);
      db.addLocation(location);
      
      response["success"] = true;
      response["id"] = req.id;
      response["message"] = "Location added successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // GET /geo/location/:id - Get location
  @method(HTTPMethod.GET)
  @path("/geo/location/:id")
  LocationResponse getLocation(string _id) {
    LocationResponse response;
    response.id = _id;
    response.success = false;
    
    try {
      auto location = db.getLocation(_id);
      response.success = true;
      response.name = location.name();
      response.latitude = location.point().latitude;
      response.longitude = location.point().longitude;
      response.metadata = location.metadata();
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // GET /geo/location - Get all locations
  @method(HTTPMethod.GET)
  @path("/geo/location")
  Json getAllLocations() {
    Json response = Json.emptyObject;
    Json locationArray = Json.emptyArray;
    
    try {
      auto locations = db.getAllLocations();
      
      foreach (location; locations) {
        Json locJson = Json.emptyObject;
        locJson["id"] = location.id();
        locJson["name"] = location.name();
        locJson["latitude"] = location.point().latitude;
        locJson["longitude"] = location.point().longitude;
        locJson["metadata"] = location.metadata();
        locationArray ~= locJson;
      }
      
      response["success"] = true;
      response["locations"] = locationArray;
      response["count"] = locations.length;
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    
    return response;
  }

  // DELETE /geo/location/:id - Remove location
  @method(HTTPMethod.DELETE)
  @path("/geo/location/:id")
  Json removeLocation(string _id) {
    Json response = Json.emptyObject;
    try {
      db.removeLocation(_id);
      response["success"] = true;
      response["id"] = _id;
      response["message"] = "Location removed successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /geo/nearby - Find nearby locations
  @method(HTTPMethod.POST)
  @path("/geo/nearby")
  NearbyResponse findNearby(NearbyRequest req) {
    NearbyResponse response;
    response.latitude = req.latitude;
    response.longitude = req.longitude;
    response.radiusMeters = req.radiusMeters;
    response.success = false;
    
    try {
      auto locations = db.findNearby(GeoPoint(req.latitude, req.longitude), req.radiusMeters);
      response.count = locations.length;
      
      foreach (location; locations) {
        LocationResponse locResp;
        locResp.success = true;
        locResp.id = location.id();
        locResp.name = location.name();
        locResp.latitude = location.point().latitude;
        locResp.longitude = location.point().longitude;
        locResp.metadata = location.metadata();
        response.locations ~= locResp;
      }
      
      response.success = true;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // POST /geo/bounds - Find locations in bounds
  @method(HTTPMethod.POST)
  @path("/geo/bounds")
  BoundsResponse findInBounds(BoundsRequest req) {
    BoundsResponse response;
    response.bounds = req;
    response.success = false;
    
    try {
      GeoBounds bounds = GeoBounds(req.minLat, req.maxLat, req.minLon, req.maxLon);
      auto locations = db.findInBounds(bounds);
      response.count = locations.length;
      
      foreach (location; locations) {
        LocationResponse locResp;
        locResp.success = true;
        locResp.id = location.id();
        locResp.name = location.name();
        locResp.latitude = location.point().latitude;
        locResp.longitude = location.point().longitude;
        locResp.metadata = location.metadata();
        response.locations ~= locResp;
      }
      
      response.success = true;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // POST /geo/nearest - Find nearest locations
  @method(HTTPMethod.POST)
  @path("/geo/nearest")
  NearestResponse findNearest(NearestRequest req) {
    NearestResponse response;
    response.latitude = req.latitude;
    response.longitude = req.longitude;
    response.requested = req.count;
    response.success = false;
    
    try {
      auto locations = db.findNearest(GeoPoint(req.latitude, req.longitude), req.count);
      response.found = locations.length;
      
      foreach (location; locations) {
        LocationResponse locResp;
        locResp.success = true;
        locResp.id = location.id();
        locResp.name = location.name();
        locResp.latitude = location.point().latitude;
        locResp.longitude = location.point().longitude;
        locResp.metadata = location.metadata();
        response.locations ~= locResp;
      }
      
      response.success = true;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // POST /geo/distance - Calculate distance
  @method(HTTPMethod.POST)
  @path("/geo/distance")
  DistanceResponse calculateDistance(DistanceRequest req) {
    DistanceResponse response;
    response.success = false;
    
    try {
      GeoPoint p1 = GeoPoint(req.lat1, req.lon1);
      GeoPoint p2 = GeoPoint(req.lat2, req.lon2);
      double distance = calculateDistance(p1, p2);
      
      response.success = true;
      response.distanceMeters = distance;
      response.distanceKilometers = distance / 1000.0;
      response.distanceMiles = distance / 1609.344;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // GET /geo/stats - Get database statistics
  @method(HTTPMethod.GET)
  @path("/geo/stats")
  DatabaseStatsResponse getStats() {
    DatabaseStatsResponse response;
    auto db_cast = cast(GeoDatabase)db;
    if (db_cast !is null) {
      auto stats = db_cast.getStats();
      response.databaseName = stats.databaseName;
      response.locationCount = stats.locationCount;
    }
    return response;
  }
}
