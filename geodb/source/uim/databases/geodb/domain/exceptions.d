/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.exceptions;

import std.conv : to;

@safe:

/// Base class of every violated domain rule. Inbound adapters map it to "bad request".
class GeoDomainException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// A latitude/longitude pair outside the WGS84 range or not a finite number.
class InvalidCoordinatesException : GeoDomainException {
  this(double latitude, double longitude, string file = __FILE__, size_t line = __LINE__) {
    super("Invalid coordinates: lat=" ~ latitude.to!string ~ ", lon=" ~ longitude.to!string, file, line);
  }
}

/// A bounding box whose corners are invalid or in the wrong order.
class InvalidBoundsException : GeoDomainException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Invalid bounds: " ~ message, file, line);
  }
}

/// Any other invalid argument (empty id, negative radius, metadata that is not an object, ...).
class GeoArgumentException : GeoDomainException {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}
