/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module geodb.geodb-advanced-example;

import uim.databases.geodb;
import std.stdio;
import std.format;

void main() {
  writeln("=== Geospatial Database Advanced Examples ===\n");

  // Setup: Create restaurant database with locations
  auto db = new GeoDatabase("restaurants");

  // Add restaurants in NYC
  db.addLocation(new GeoLocation(
    "rest_1", "Central Park Bistro", 
    GeoPoint(40.7829, -73.9654),
    Json(["type": Json("French"), "rating": Json(4.8)])
  ));

  db.addLocation(new GeoLocation(
    "rest_2", "Times Square Diner",
    GeoPoint(40.7580, -73.9855),
    Json(["type": Json("American"), "rating": Json(4.2)])
  ));

  db.addLocation(new GeoLocation(
    "rest_3", "SoHo Italian",
    GeoPoint(40.7225, -73.9971),
    Json(["type": Json("Italian"), "rating": Json(4.6)])
  ));

  db.addLocation(new GeoLocation(
    "rest_4", "Brooklyn Korean",
    GeoPoint(40.6782, -73.9442),
    Json(["type": Json("Korean"), "rating": Json(4.5)])
  ));

  db.addLocation(new GeoLocation(
    "rest_5", "Chinatown Express",
    GeoPoint(40.7163, -73.9933),
    Json(["type": Json("Chinese"), "rating": Json(4.3)])
  ));

  writeln("Dataset: 5 NYC restaurants indexed\n");

  // Example 1: Radius-Based Restaurant Search
  writeln("Example 1: Find Restaurants Nearby (5 km radius)");
  writeln("---------");
  auto timeSquare = GeoPoint(40.7580, -73.9855);
  auto nearby = db.findNearby(timeSquare, 5000);  // 5 km
  
  writeln(format("Restaurants within 5 km of Times Square (%d found):", nearby.length));
  foreach (rest; nearby) {
    double distance = rest.distanceToPoint(timeSquare);
    writeln(format("  - %s: %.2f km", rest.name(), distance/1000));
  }
  writeln();

  // Example 2: Cuisine Type Filtering
  writeln("Example 2: Filter Restaurants by Cuisine Type");
  writeln("---------");
  string targetCuisine = "Italian";
  writeln(format("Finding %s restaurants:", targetCuisine));
  
  auto allLocations = db.getAllLocations();
  int count = 0;
  foreach (rest; allLocations) {
    string cuisineType = rest.metadata()["type"].get!string;
    if (cuisineType == targetCuisine) {
      writeln(format("  - %s (Rating: %.1f)", rest.name(), rest.metadata()["rating"].get!double));
      count++;
    }
  }
  writeln(format("Found %d %s restaurants", count, targetCuisine));
  writeln();

  // Example 3: Highest Rated Restaurants
  writeln("Example 3: Find Highest Rated Restaurants");
  writeln("---------");
  struct RatedRest {
    string name;
    double rating;
    double distance;
  }

  RatedRest[] ratedRests;
  auto searchPoint = GeoPoint(40.7500, -73.9900);
  
  foreach (rest; allLocations) {
    double rating = rest.metadata()["rating"].get!double;
    double distance = rest.distanceToPoint(searchPoint);
    ratedRests ~= RatedRest(rest.name(), rating, distance);
  }

  // Sort by rating (descending)
  import std.algorithm : sort;
  ratedRests.sort!((a, b) => a.rating > b.rating);

  writeln("Top restaurants by rating:");
  foreach (i, rest; ratedRests[0..$]) {
    writeln(format("  %d. %s - Rating: %.1f, Distance: %.2f km", 
      i+1, rest.name, rest.rating, rest.distance/1000));
  }
  writeln();

  // Example 4: Geographical Region Query
  writeln("Example 4: Find Restaurants in Geographic Region");
  writeln("---------");
  // Lower Manhattan bounds
  GeoBounds manhattanBounds = GeoBounds(40.7000, 40.8000, -74.0200, -73.9000);
  writeln("Searching in Lower Manhattan bounds:");
  writeln(format("  Lat: [%.4f, %.4f], Lon: [%.4f, %.4f]",
    manhattanBounds.minLat, manhattanBounds.maxLat,
    manhattanBounds.minLon, manhattanBounds.maxLon));
  
  auto inBounds = db.findInBounds(manhattanBounds);
  writeln(format("Found %d restaurants in region:", inBounds.length));
  foreach (rest; inBounds) {
    writeln(format("  - %s: %.4f, %.4f", rest.name(), rest.point().latitude, rest.point().longitude));
  }
  writeln();

  // Example 5: Nearest N Locations
  writeln("Example 5: Find 2 Nearest Restaurants to Point");
  writeln("---------");
  auto searchLoc = GeoPoint(40.7200, -73.9850);
  auto nearest = db.findNearest(searchLoc, 2);
  
  writeln(format("2 nearest restaurants to (%.4f, %.4f):", searchLoc.latitude, searchLoc.longitude));
  foreach (i, rest; nearest) {
    double dist = rest.distanceToPoint(searchLoc);
    writeln(format("  %d. %s: %.2f meters", i+1, rest.name(), dist));
  }
  writeln();

  // Example 6: Service Area Analysis
  writeln("Example 6: Service Area Coverage Analysis");
  writeln("---------");
  double serviceRadius = 2000;  // 2 km
  auto basePoint = GeoPoint(40.7400, -73.9900);
  
  auto covered = db.findNearby(basePoint, serviceRadius);
  writeln(format("Service area: %.2f km radius from (%.4f, %.4f)", 
    serviceRadius/1000, basePoint.latitude, basePoint.longitude));
  writeln(format("Restaurants in service area: %d/%d", covered.length, db.count()));
  
  writeln("Coverage details:");
  foreach (rest; covered) {
    double dist = rest.distanceToPoint(basePoint);
    writeln(format("  - %s: %.2f meters from center", rest.name(), dist));
  }
  writeln();

  // Example 7: Multi-Criteria Search
  writeln("Example 7: Multi-Criteria Search");
  writeln("---------");
  // Find highly-rated restaurants within 3 km
  double minRating = 4.5;
  double maxDistance = 3000;  // 3 km
  auto criteria = GeoPoint(40.7500, -73.9900);
  
  writeln(format("Criteria: Rating >= %.1f, Distance <= %.2f km", minRating, maxDistance/1000));
  
  int matches = 0;
  foreach (rest; allLocations) {
    double rating = rest.metadata()["rating"].get!double;
    double distance = rest.distanceToPoint(criteria);
    
    if (rating >= minRating && distance <= maxDistance) {
      writeln(format("  ✓ %s (Rating: %.1f, Distance: %.2f km)", 
        rest.name(), rating, distance/1000));
      matches++;
    }
  }
  writeln(format("Matching restaurants: %d", matches));
  writeln();

  // Example 8: Distance Matrix
  writeln("Example 8: Create Distance Matrix");
  writeln("---------");
  writeln("Distance matrix (in km) between restaurants:");
  writeln();
  
  auto locs = db.getAllLocations();
  
  // Print header
  write("       ");
  foreach (loc; locs) {
    write(format("%-15s", loc.name().length > 12 ? loc.name()[0..12] : loc.name()));
  }
  writeln();
  
  // Print matrix
  foreach (i, loc1; locs) {
    write(format("%-6s", loc1.name().length > 5 ? loc1.name()[0..5] : loc1.name()));
    foreach (j, loc2; locs) {
      double dist = loc1.distanceToPoint(loc2.point());
      write(format("%-15.2f", dist/1000));
    }
    writeln();
  }
  writeln();

  // Example 9: Database Statistics
  writeln("Example 9: Database Statistics");
  writeln("---------");
  auto stats = (cast(GeoDatabase)db).getStats();
  writeln(format("Database Name: %s", stats.databaseName));
  writeln(format("Total Locations: %d", stats.locationCount));
  
  double avgRating = 0;
  foreach (rest; allLocations) {
    avgRating += rest.metadata()["rating"].get!double;
  }
  avgRating /= allLocations.length;
  writeln(format("Average Rating: %.2f", avgRating));
  writeln();

  // Example 10: Proximity Notifications
  writeln("Example 10: Proximity Alerts");
  writeln("---------");
  double alertRadius = 1000;  // 1 km
  auto userLocation = GeoPoint(40.7150, -73.9900);
  
  writeln(format("User is at: %.4f, %.4f", userLocation.latitude, userLocation.longitude));
  writeln(format("Proximity alert radius: %.2f km\n", alertRadius/1000));
  
  auto nearby_alerts = db.findNearby(userLocation, alertRadius);
  if (nearby_alerts.length > 0) {
    writeln("⚠️ Nearby restaurants:");
    foreach (rest; nearby_alerts) {
      double dist = rest.distanceToPoint(userLocation);
      writeln(format("  🍴 %s - %.0f meters away", rest.name(), dist));
    }
  } else {
    writeln("No restaurants within alert radius");
  }

  writeln();
  writeln("=== Advanced Examples Complete ===");
}
