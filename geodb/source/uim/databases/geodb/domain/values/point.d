/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.values.point;

import uim.databases.geodb.domain.exceptions;
import std.format : format;
import std.math : isFinite;

@safe:

enum double minLatitude = -90.0;
enum double maxLatitude = 90.0;
enum double minLongitude = -180.0;
enum double maxLongitude = 180.0;

/// True when both values are finite and inside the WGS84 range.
bool isValidCoordinate(double latitude, double longitude) pure nothrow @nogc {
  return isFinite(latitude) && isFinite(longitude)
    && latitude >= minLatitude && latitude <= maxLatitude
    && longitude >= minLongitude && longitude <= maxLongitude;
}

/// Value object: a validated WGS84 coordinate in decimal degrees.
struct GeoPoint {
  private {
    double _latitude = 0.0;
    double _longitude = 0.0;
  }

  /// Throws: InvalidCoordinatesException when the coordinate is out of range or not finite.
  this(double latitude, double longitude) {
    if (!isValidCoordinate(latitude, longitude)) {
      throw new InvalidCoordinatesException(latitude, longitude);
    }
    _latitude = latitude;
    _longitude = longitude;
  }

  double latitude() const pure nothrow @nogc {
    return _latitude;
  }

  double longitude() const pure nothrow @nogc {
    return _longitude;
  }

  string toString() const {
    return format("(%s, %s)", _latitude, _longitude);
  }
}

unittest {
  import std.exception : assertThrown;

  auto p = GeoPoint(48.8566, 2.3522);
  assert(p.latitude == 48.8566 && p.longitude == 2.3522);
  assert(GeoPoint.init.latitude == 0 && GeoPoint.init.longitude == 0);

  assertThrown!InvalidCoordinatesException(GeoPoint(91, 0));
  assertThrown!InvalidCoordinatesException(GeoPoint(0, -180.5));
  assertThrown!InvalidCoordinatesException(GeoPoint(double.nan, 0));
  assertThrown!InvalidCoordinatesException(GeoPoint(0, double.infinity));
}
