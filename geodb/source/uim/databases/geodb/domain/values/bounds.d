/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.values.bounds;

import uim.databases.geodb.domain.exceptions;
import uim.databases.geodb.domain.values.point;

@safe:

/// Value object: a latitude/longitude box. When minLongitude > maxLongitude the box crosses the
/// antimeridian (e.g. minLongitude 170, maxLongitude -170 spans 20 degrees across ±180).
/// The default value covers the whole world.
struct GeoBounds {
  private {
    double _minLatitude = minLatitude;
    double _maxLatitude = maxLatitude;
    double _minLongitude = minLongitude;
    double _maxLongitude = maxLongitude;
  }

  /// Throws: InvalidBoundsException when a corner is invalid or minLatitude > maxLatitude.
  this(double minLat, double maxLat, double minLon, double maxLon) {
    if (!isValidCoordinate(minLat, minLon) || !isValidCoordinate(maxLat, maxLon)) {
      throw new InvalidBoundsException("corners must be finite WGS84 coordinates");
    }
    if (minLat > maxLat) {
      throw new InvalidBoundsException("minLat must not exceed maxLat");
    }
    _minLatitude = minLat;
    _maxLatitude = maxLat;
    _minLongitude = minLon;
    _maxLongitude = maxLon;
  }

  /// The box covering the whole globe.
  static GeoBounds world() pure nothrow @nogc {
    return GeoBounds.init;
  }

  double minLat() const pure nothrow @nogc {
    return _minLatitude;
  }

  double maxLat() const pure nothrow @nogc {
    return _maxLatitude;
  }

  double minLon() const pure nothrow @nogc {
    return _minLongitude;
  }

  double maxLon() const pure nothrow @nogc {
    return _maxLongitude;
  }

  bool crossesAntimeridian() const pure nothrow @nogc {
    return _minLongitude > _maxLongitude;
  }

  bool contains(GeoPoint point) const pure nothrow @nogc {
    if (point.latitude < _minLatitude || point.latitude > _maxLatitude) {
      return false;
    }
    return crossesAntimeridian
      ? point.longitude >= _minLongitude || point.longitude <= _maxLongitude
      : point.longitude >= _minLongitude && point.longitude <= _maxLongitude;
  }

  GeoPoint center() const {
    immutable latitude = (_minLatitude + _maxLatitude) / 2.0;
    if (!crossesAntimeridian) {
      return GeoPoint(latitude, (_minLongitude + _maxLongitude) / 2.0);
    }
    double longitude = _minLongitude + (_maxLongitude + 360.0 - _minLongitude) / 2.0;
    if (longitude > maxLongitude) {
      longitude -= 360.0;
    }
    return GeoPoint(latitude, longitude);
  }

  /// One box, or two when this box crosses the antimeridian; none of the results cross it.
  GeoBounds[] split() const {
    if (!crossesAntimeridian) {
      return [this];
    }
    return [
      GeoBounds(_minLatitude, _maxLatitude, _minLongitude, maxLongitude),
      GeoBounds(_minLatitude, _maxLatitude, minLongitude, _maxLongitude)
    ];
  }
}

unittest {
  import std.exception : assertThrown;

  auto europe = GeoBounds(35, 60, -10, 30);
  assert(europe.contains(GeoPoint(48.8566, 2.3522)));
  assert(!europe.contains(GeoPoint(40.7128, -74.0060)));
  assert(europe.center == GeoPoint(47.5, 10));
  assert(europe.split.length == 1);

  auto pacific = GeoBounds(-30, 30, 170, -170);
  assert(pacific.crossesAntimeridian);
  assert(pacific.contains(GeoPoint(0, 179)));
  assert(pacific.contains(GeoPoint(0, -175)));
  assert(!pacific.contains(GeoPoint(0, 0)));
  assert(pacific.center == GeoPoint(0, 180));
  assert(pacific.split.length == 2);

  assert(GeoBounds.world.contains(GeoPoint(-90, -180)));
  assertThrown!InvalidBoundsException(GeoBounds(10, 5, 0, 1));
  assertThrown!InvalidBoundsException(GeoBounds(0, 95, 0, 1));
}
