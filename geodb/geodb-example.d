/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module geodb_example;

import uim.databases.geodb;
import std.stdio;
import std.format;

void main() {
  writeln("=== Geospatial Database Examples ===\n");

  // Example 1: Create Database and Add Locations
  writeln("Example 1: Create Database and Add Locations");
  writeln("---------");
  auto db = new GeoDatabase("cities");

  auto paris = new GeoLocation("paris", "Paris, France", GeoPoint(48.8566, 2.3522), 
    Json(["country": Json("France"), "population": Json(2161000)]));
  auto london = new GeoLocation("london", "London, UK", GeoPoint(51.5074, -0.1278),
    Json(["country": Json("United Kingdom"), "population": Json(8900000)]));
  auto berlin = new GeoLocation("berlin", "Berlin, Germany", GeoPoint(52.5200, 13.4050),
    Json(["country": Json("Germany"), "population": Json(3645000)]));
  auto rome = new GeoLocation("rome", "Rome, Italy", GeoPoint(41.9028, 12.4964),
    Json(["country": Json("Italy"), "population": Json(2761000)]));
  auto amsterdam = new GeoLocation("amsterdam", "Amsterdam, Netherlands", 
    GeoPoint(52.3676, 4.9041),
    Json(["country": Json("Netherlands"), "population": Json(873000)]));

  db.addLocation(paris);
  db.addLocation(london);
  db.addLocation(berlin);
  db.addLocation(rome);
  db.addLocation(amsterdam);

  writeln("Added 5 European cities to database");
  writeln("Database size: ", db.count());
  writeln();

  // Example 2: Find Locations by ID
  writeln("Example 2: Retrieve Location Information");
  writeln("---------");
  auto loc = db.getLocation("paris");
  writeln(format("Location: %s", loc.name()));
  writeln(format("Coordinates: %.4f, %.4f", loc.point().latitude, loc.point().longitude));
  writeln(format("Country: %s", loc.metadata()["country"]));
  writeln();

  // Example 3: Calculate Distance
  writeln("Example 3: Calculate Distance Between Cities");
  writeln("---------");
  auto parisPoint = paris.point();
  auto londonPoint = london.point();
  double distance = parisPoint.distanceTo(londonPoint);
  writeln(format("Distance Paris to London: %.2f meters (%.2f km)", distance, distance/1000));
  writeln();

  // Example 4: Find Nearby Locations
  writeln("Example 4: Find Nearby Locations (1000 km radius)");
  writeln("---------");
  auto nearby = db.findNearby(parisPoint, 1000000);  // 1000 km in meters
  writeln(format("Found %d cities within 1000 km of Paris:", nearby.length));
  foreach (location; nearby) {
    double dist = location.distanceToPoint(parisPoint);
    writeln(format("  - %s: %.2f km", location.name(), dist/1000));
  }
  writeln();

  // Example 5: Find Nearest Locations
  writeln("Example 5: Find 3 Nearest Cities to Paris");
  writeln("---------");
  auto nearest = db.findNearest(parisPoint, 3);
  writeln(format("3 nearest cities to Paris:"));
  foreach (location; nearest) {
    double dist = location.distanceToPoint(parisPoint);
    writeln(format("  - %s: %.2f km", location.name(), dist/1000));
  }
  writeln();

  // Example 6: Bounding Box Query
  writeln("Example 6: Find Cities in Geographic Bounds");
  writeln("---------");
  // Define a bounding box around central Europe
  GeoBounds bounds = GeoBounds(48.0, 53.0, 2.0, 14.0);
  writeln(format("Bounding box: lat [%.2f, %.2f], lon [%.2f, %.2f]", 
    bounds.minLat, bounds.maxLat, bounds.minLon, bounds.maxLon));
  
  auto inBounds = db.findInBounds(bounds);
  writeln(format("Found %d cities in bounds:", inBounds.length));
  foreach (location; inBounds) {
    writeln(format("  - %s", location.name()));
  }
  writeln();

  // Example 7: All Locations
  writeln("Example 7: Get All Locations");
  writeln("---------");
  auto allLocations = db.getAllLocations();
  writeln(format("Total locations: %d", allLocations.length));
  foreach (location; allLocations) {
    writeln(format("  - %s: %.4f, %.4f", location.name(), location.point().latitude, location.point().longitude));
  }
  writeln();

  // Example 8: Database Statistics
  writeln("Example 8: Database Statistics");
  writeln("---------");
  auto stats = (cast(GeoDatabase)db).getStats();
  writeln(format("Database: %s", stats.databaseName));
  writeln(format("Locations: %d", stats.locationCount));
  writeln();

  // Example 9: Location Existence Check
  writeln("Example 9: Check Location Existence");
  writeln("---------");
  writeln("Has 'paris': ", db.hasLocation("paris"));
  writeln("Has 'tokyo': ", db.hasLocation("tokyo"));
  writeln();

  // Example 10: Remove Location
  writeln("Example 10: Remove Location");
  writeln("---------");
  writeln("Before removal - Database size: ", db.count());
  db.removeLocation("rome");
  writeln("After removing Rome - Database size: ", db.count());

  writeln();
  writeln("=== Examples Complete ===");
}
