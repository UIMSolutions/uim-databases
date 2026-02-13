/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.errors.exceptions;

@safe:

/// Exception for invalid geographic locations
class GeoLocationException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Location error: " ~ message, file, line);
  }
}

/// Exception for invalid coordinates
class InvalidCoordinatesException : Exception {
  this(double lat, double lon, string file = __FILE__, size_t line = __LINE__) {
    import std.conv : to;
    super("Invalid coordinates: lat=" ~ lat.to!string ~ ", lon=" ~ lon.to!string, file, line);
  }
}

/// Exception for geographic operations
class GeoOperationException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Geo operation error: " ~ message, file, line);
  }
}

/// Exception for location not found
class LocationNotFoundException : Exception {
  this(string locationId, string file = __FILE__, size_t line = __LINE__) {
    super("Location not found: " ~ locationId, file, line);
  }
}

/// Exception for index operations
class GeoIndexException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Index error: " ~ message, file, line);
  }
}

/// Exception for database operations
class GeoDatabaseException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) {
    super("Database error: " ~ message, file, line);
  }
}
