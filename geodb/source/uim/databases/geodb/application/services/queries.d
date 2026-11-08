/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.application.services.queries;

import uim.databases.geodb.application.dtos;
import uim.databases.geodb.application.ports;
import uim.databases.geodb.domain;
import std.algorithm : filter, map, sort;
import std.array : array;
import std.range : take;

@safe:

/// Implements the spatial query use cases on top of any ILocationRepository.
final class GeoQueryService : IGeoQueryUseCase {
  private {
    ILocationRepository _repository;
    string _databaseName;
  }

  this(ILocationRepository repository, string databaseName) {
    assert(repository !is null, "GeoQueryService needs a repository");
    _repository = repository;
    _databaseName = databaseName;
  }

  LocationMatch[] nearby(NearbyQuery query) {
    auto center = GeoPoint(query.latitude, query.longitude);
    // The box pre-selects candidates through the repository's index; the exact radius check follows.
    auto candidates = _repository.findInBounds(boundsAround(center, query.radiusMeters));
    return byDistance(center, candidates)
      .filter!(m => m.distanceMeters <= query.radiusMeters)
      .array;
  }

  LocationData[] inBounds(BoundsQuery query) {
    auto found = _repository.findInBounds(GeoBounds(query.minLat, query.maxLat, query.minLon, query.maxLon));
    found.sort!((a, b) => a.id < b.id);
    return found.map!(l => LocationData.from(l)).array;
  }

  LocationMatch[] nearest(NearestQuery query) {
    auto center = GeoPoint(query.latitude, query.longitude);
    if (query.count == 0) {
      return [];
    }
    return byDistance(center, _repository.findAll()).take(query.count).array;
  }

  DistanceData distance(DistanceQuery query) {
    return DistanceData.from(haversine(GeoPoint(query.lat1, query.lon1), GeoPoint(query.lat2, query.lon2)));
  }

  GeoStatistics statistics() {
    return GeoStatistics(_databaseName, _repository.count());
  }

  /// Matches ordered by distance, ties broken by id so results are stable.
  private static LocationMatch[] byDistance(GeoPoint center, GeoLocation[] locations) {
    auto matches = locations
      .map!(l => LocationMatch(LocationData.from(l), l.distanceTo(center).meters))
      .array;
    matches.sort!((a, b) => a.distanceMeters < b.distanceMeters
        || (a.distanceMeters == b.distanceMeters && a.location.id < b.location.id));
    return matches;
  }
}

unittest {
  import uim.databases.geodb.application.testing : FakeLocationRepository;
  import std.exception : assertThrown;
  import std.math : abs;

  auto repository = new FakeLocationRepository;
  foreach (city; [
      GeoLocation("paris", "Paris", GeoPoint(48.8566, 2.3522)),
      GeoLocation("london", "London", GeoPoint(51.5074, -0.1278)),
      GeoLocation("berlin", "Berlin", GeoPoint(52.5200, 13.4050)),
      GeoLocation("rome", "Rome", GeoPoint(41.9028, 12.4964)),
      GeoLocation("suva", "Suva", GeoPoint(-18.1416, 178.4419)),
      GeoLocation("apia", "Apia", GeoPoint(-13.8333, -171.7667)),
    ]) {
    repository.save(city);
  }
  auto service = new GeoQueryService(repository, "cities");

  auto near = service.nearby(NearbyQuery(48.8566, 2.3522, 500_000));
  assert(near.map!(m => m.location.id).array == ["paris", "london"]);
  assert(near[0].distanceMeters == 0);

  auto europe = service.inBounds(BoundsQuery(40, 55, -5, 15));
  assert(europe.map!(l => l.id).array == ["berlin", "london", "paris", "rome"]);

  auto pacific = service.inBounds(BoundsQuery(-20, -10, 175, -170));
  assert(pacific.map!(l => l.id).array == ["apia", "suva"]);

  // Radius search across the antimeridian finds Apia from Suva (~1150 km).
  assert(service.nearby(NearbyQuery(-18.1416, 178.4419, 1_300_000)).map!(m => m.location.id).array
      == ["suva", "apia"]);

  auto two = service.nearest(NearestQuery(50.0, 5.0, 2));
  assert(two.map!(m => m.location.id).array == ["paris", "london"]);
  assert(service.nearest(NearestQuery(50.0, 5.0, 100)).length == 6);
  assert(service.nearest(NearestQuery(50.0, 5.0, 0)).length == 0);

  auto d = service.distance(DistanceQuery(48.8566, 2.3522, 51.5074, -0.1278));
  assert(abs(d.kilometers - 343.5) < 1.0 && abs(d.meters / 1000 - d.kilometers) < 1e-9);

  assert(service.statistics() == GeoStatistics("cities", 6));

  assertThrown!GeoArgumentException(service.nearby(NearbyQuery(0, 0, -5)));
  assertThrown!InvalidBoundsException(service.inBounds(BoundsQuery(10, 0, 0, 10)));
  assertThrown!InvalidCoordinatesException(service.nearest(NearestQuery(0, 200, 1)));
}
