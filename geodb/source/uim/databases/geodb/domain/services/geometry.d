/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.services.geometry;

import uim.databases.geodb.domain.exceptions;
import uim.databases.geodb.domain.values;
import std.algorithm.comparison : max, min;
import std.math : asin, cos, isFinite, PI, sin, sqrt;

@safe:

/// Mean earth radius used by all distance calculations.
enum double earthRadiusMeters = 6_371_000.0;

private enum double degreesToRadians = PI / 180.0;
private enum double radiansToDegrees = 180.0 / PI;

/// Great-circle distance between two points (haversine formula).
Distance haversine(GeoPoint from, GeoPoint to) pure nothrow @nogc {
  immutable lat1 = from.latitude * degreesToRadians;
  immutable lat2 = to.latitude * degreesToRadians;
  immutable deltaLat = (to.latitude - from.latitude) * degreesToRadians;
  immutable deltaLon = (to.longitude - from.longitude) * degreesToRadians;

  immutable a = sin(deltaLat / 2) ^^ 2 + cos(lat1) * cos(lat2) * sin(deltaLon / 2) ^^ 2;
  // Rounding can push `a` marginally above 1 for antipodal points.
  return Distance(earthRadiusMeters * 2.0 * asin(sqrt(min(1.0, max(0.0, a)))));
}

/// Validates a search radius in meters.
void requireValidRadius(double radiusMeters) {
  if (!isFinite(radiusMeters) || radiusMeters < 0) {
    throw new GeoArgumentException("Radius must be a finite, non-negative number of meters");
  }
}

/// Smallest lat/lon box containing every point within `radiusMeters` of `center`.
/// Near the poles the box spans all longitudes; near ±180 it crosses the antimeridian.
GeoBounds boundsAround(GeoPoint center, double radiusMeters) {
  requireValidRadius(radiusMeters);

  immutable angular = radiusMeters / earthRadiusMeters;
  if (angular >= PI) {
    return GeoBounds.world;
  }

  immutable deltaLat = angular * radiansToDegrees;
  immutable minLat = center.latitude - deltaLat;
  immutable maxLat = center.latitude + deltaLat;
  if (minLat <= minLatitude || maxLat >= maxLatitude) {
    return GeoBounds(max(minLat, minLatitude), min(maxLat, maxLatitude), minLongitude, maxLongitude);
  }

  immutable ratio = sin(angular) / cos(center.latitude * degreesToRadians);
  if (ratio >= 1.0) {
    return GeoBounds(minLat, maxLat, minLongitude, maxLongitude);
  }

  immutable deltaLon = asin(ratio) * radiansToDegrees;
  double minLon = center.longitude - deltaLon;
  double maxLon = center.longitude + deltaLon;
  if (minLon < minLongitude) {
    minLon += 360.0;
  }
  if (maxLon > maxLongitude) {
    maxLon -= 360.0;
  }
  return GeoBounds(minLat, maxLat, minLon, maxLon);
}

unittest {
  import std.exception : assertThrown;
  import std.math : abs;

  auto paris = GeoPoint(48.8566, 2.3522);
  auto london = GeoPoint(51.5074, -0.1278);
  immutable d = haversine(paris, london).kilometers;
  assert(abs(d - 343.5) < 1.0);
  assert(haversine(paris, paris).meters == 0);

  // Every point within the radius must be inside the box.
  auto box = boundsAround(paris, 400_000);
  assert(box.contains(london));
  assert(!box.crossesAntimeridian);

  auto fiji = GeoPoint(-17.7, 179.9);
  auto wrapped = boundsAround(fiji, 100_000);
  assert(wrapped.crossesAntimeridian);
  assert(wrapped.contains(GeoPoint(-17.7, -179.9)));

  auto nearPole = boundsAround(GeoPoint(89.5, 0), 100_000);
  assert(nearPole.minLon == minLongitude && nearPole.maxLon == maxLongitude);

  assertThrown!GeoArgumentException(boundsAround(paris, -1));
  assertThrown!GeoArgumentException(boundsAround(paris, double.nan));
}
