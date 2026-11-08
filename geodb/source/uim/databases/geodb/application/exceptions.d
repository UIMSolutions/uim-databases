/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.application.exceptions;

@safe:

/// Base class of use-case failures that are not domain rule violations.
class GeoApplicationException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}

/// No location with the requested id. Inbound adapters map it to "not found".
class LocationNotFoundException : GeoApplicationException {
  this(string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Location not found: " ~ id, file, line);
  }
}

/// A location with this id exists already. Inbound adapters map it to "conflict".
class LocationAlreadyExistsException : GeoApplicationException {
  this(string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super("Location already exists: " ~ id, file, line);
  }
}
