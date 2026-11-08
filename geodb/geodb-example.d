/+ dub.sdl:
  name "geodb-example"
  dependency "geodb" path="."
+/
/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Embedded use of the geodb core, without HTTP.  Run: dub run --single geodb-example.d
module geodb_example;

import uim.databases.geodb;
import std.json : JSONValue;
import std.stdio : writefln, writeln;

@safe:

void main() {
  writeln("=== Geospatial Database Examples ===\n");

  // Composition: one outbound adapter, two use cases sharing it.
  ILocationRepository repository = new InMemoryLocationRepository();
  ILocationUseCase locations = new LocationService(repository);
  IGeoQueryUseCase queries = new GeoQueryService(repository, "cities");

  writeln("Example 1: Add locations");
  JSONValue meta(string country, long population) {
    return JSONValue(["country": JSONValue(country), "population": JSONValue(population)]);
  }
  locations.add(AddLocationCommand("paris", "Paris, France", 48.8566, 2.3522, meta("France", 2_161_000)));
  locations.add(AddLocationCommand("london", "London, UK", 51.5074, -0.1278, meta("United Kingdom", 8_900_000)));
  locations.add(AddLocationCommand("berlin", "Berlin, Germany", 52.5200, 13.4050, meta("Germany", 3_645_000)));
  locations.add(AddLocationCommand("rome", "Rome, Italy", 41.9028, 12.4964, meta("Italy", 2_761_000)));
  locations.add(AddLocationCommand("amsterdam", "Amsterdam, Netherlands", 52.3676, 4.9041, meta("Netherlands", 873_000)));
  writefln("Database size: %d\n", queries.statistics().locationCount);

  writeln("Example 2: Retrieve a location");
  auto paris = locations.get("paris");
  writefln("%s at %.4f, %.4f in %s\n", paris.name, paris.latitude, paris.longitude, paris.metadata["country"].str);

  writeln("Example 3: Distance Paris - London");
  auto distance = queries.distance(DistanceQuery(48.8566, 2.3522, 51.5074, -0.1278));
  writefln("%.0f m = %.2f km = %.2f mi\n", distance.meters, distance.kilometers, distance.miles);

  writeln("Example 4: Cities within 1000 km of Paris (nearest first)");
  foreach (match; queries.nearby(NearbyQuery(48.8566, 2.3522, 1_000_000))) {
    writefln("  - %s: %.2f km", match.location.name, match.distanceMeters / 1000);
  }
  writeln();

  writeln("Example 5: 3 nearest cities to Paris");
  foreach (match; queries.nearest(NearestQuery(48.8566, 2.3522, 3))) {
    writefln("  - %s: %.2f km", match.location.name, match.distanceMeters / 1000);
  }
  writeln();

  writeln("Example 6: Cities in lat [48, 53], lon [2, 14]");
  foreach (location; queries.inBounds(BoundsQuery(48.0, 53.0, 2.0, 14.0))) {
    writefln("  - %s", location.name);
  }
  writeln();

  writeln("Example 7: All locations (ordered by id)");
  foreach (location; locations.list()) {
    writefln("  - %s: %.4f, %.4f", location.name, location.latitude, location.longitude);
  }
  writeln();

  writeln("Example 8: Update a location");
  auto moved = locations.update("amsterdam", UpdateLocationCommand("Amsterdam Centraal", 52.3791, 4.9003,
      meta("Netherlands", 931_000)));
  writefln("  %s now at %.4f, %.4f\n", moved.name, moved.latitude, moved.longitude);

  writeln("Example 9: Errors are typed");
  try {
    locations.get("tokyo");
  } catch (LocationNotFoundException e) {
    writeln("  ", e.msg);
  }
  try {
    locations.add(AddLocationCommand("nowhere", "Invalid", 123.0, 0.0));
  } catch (InvalidCoordinatesException e) {
    writeln("  ", e.msg);
  }
  writeln();

  writeln("Example 10: Remove a location");
  locations.remove("rome");
  auto stats = queries.statistics();
  writefln("Database '%s' now holds %d locations", stats.databaseName, stats.locationCount);

  writeln("\n=== Examples Complete ===");
}
