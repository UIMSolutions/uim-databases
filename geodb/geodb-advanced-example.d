/+ dub.sdl:
  name "geodb-advanced-example"
  dependency "geodb" path="."
+/
/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Restaurant search on top of the geodb use cases, plus a custom outbound adapter.
/// Run: dub run --single geodb-advanced-example.d
module geodb_advanced_example;

import uim.databases.geodb;
import std.algorithm : filter, map, sort;
import std.array : array;
import std.json : JSONValue;
import std.stdio : writefln, writeln;
import std.typecons : Nullable;

@safe:

/// The ports make adapters swappable: this decorator counts repository calls around any other adapter.
final class CountingRepository : ILocationRepository {
  private ILocationRepository _inner;
  size_t calls;

  this(ILocationRepository inner) {
    _inner = inner;
  }

  void save(GeoLocation l) { calls++; _inner.save(l); }
  Nullable!GeoLocation findById(string id) { calls++; return _inner.findById(id); }
  bool remove(string id) { calls++; return _inner.remove(id); }
  bool contains(string id) { calls++; return _inner.contains(id); }
  GeoLocation[] findAll() { calls++; return _inner.findAll(); }
  GeoLocation[] findInBounds(GeoBounds b) { calls++; return _inner.findInBounds(b); }
  size_t count() { calls++; return _inner.count(); }
}

double rating(LocationData l) {
  return l.metadata["rating"].floating;
}

void main() {
  writeln("=== Geospatial Database Advanced Examples ===\n");

  auto repository = new CountingRepository(new InMemoryLocationRepository(0.01)); // ~1 km cells for city data
  ILocationUseCase restaurants = new LocationService(repository);
  IGeoQueryUseCase search = new GeoQueryService(repository, "restaurants");

  void add(string id, string name, double lat, double lon, string cuisine, double stars) {
    restaurants.add(AddLocationCommand(id, name, lat, lon,
        JSONValue(["type": JSONValue(cuisine), "rating": JSONValue(stars)])));
  }
  add("rest_1", "Central Park Bistro", 40.7829, -73.9654, "French", 4.8);
  add("rest_2", "Times Square Diner", 40.7580, -73.9855, "American", 4.2);
  add("rest_3", "SoHo Italian", 40.7225, -73.9971, "Italian", 4.6);
  add("rest_4", "Brooklyn Korean", 40.6782, -73.9442, "Korean", 4.5);
  add("rest_5", "Chinatown Express", 40.7163, -73.9933, "Chinese", 4.3);
  writeln("Dataset: 5 NYC restaurants indexed\n");

  writeln("Example 1: Restaurants within 5 km of Times Square");
  foreach (m; search.nearby(NearbyQuery(40.7580, -73.9855, 5000))) {
    writefln("  - %s: %.2f km", m.location.name, m.distanceMeters / 1000);
  }
  writeln();

  writeln("Example 2: Filter by cuisine (metadata)");
  foreach (r; restaurants.list().filter!(r => r.metadata["type"].str == "Italian")) {
    writefln("  - %s (rating %.1f)", r.name, rating(r));
  }
  writeln();

  writeln("Example 3: Ranked by rating, with distance from (40.75, -73.99)");
  auto ranked = search.nearest(NearestQuery(40.7500, -73.9900, size_t.max));
  ranked.sort!((a, b) => rating(a.location) > rating(b.location));
  foreach (i, m; ranked) {
    writefln("  %d. %s - rating %.1f, %.2f km", i + 1, m.location.name, rating(m.location), m.distanceMeters / 1000);
  }
  writeln();

  writeln("Example 4: Lower Manhattan bounding box");
  foreach (r; search.inBounds(BoundsQuery(40.7000, 40.8000, -74.0200, -73.9000))) {
    writefln("  - %s: %.4f, %.4f", r.name, r.latitude, r.longitude);
  }
  writeln();

  writeln("Example 5: 2 nearest restaurants to (40.72, -73.985)");
  foreach (i, m; search.nearest(NearestQuery(40.7200, -73.9850, 2))) {
    writefln("  %d. %s: %.0f m", i + 1, m.location.name, m.distanceMeters);
  }
  writeln();

  writeln("Example 6: Service area of 2.5 km around (40.74, -73.99)");
  auto covered = search.nearby(NearbyQuery(40.7400, -73.9900, 2500));
  writefln("  covered %d/%d", covered.length, search.statistics().locationCount);
  foreach (m; covered) {
    writefln("  - %s: %.0f m", m.location.name, m.distanceMeters);
  }
  writeln();

  writeln("Example 7: Rating >= 4.5 within 5 km of (40.75, -73.99)");
  foreach (m; search.nearby(NearbyQuery(40.7500, -73.9900, 5000)).filter!(m => rating(m.location) >= 4.5)) {
    writefln("  * %s (rating %.1f, %.2f km)", m.location.name, rating(m.location), m.distanceMeters / 1000);
  }
  writeln();

  writefln("Repository calls made through the port: %d", repository.calls);
  writeln("\n=== Advanced Examples Complete ===");
}
