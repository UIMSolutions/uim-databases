/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.tsdb.errors.exceptions;

@safe:

/// Base exception for time series operations
class TimeSeriesException : Exception {
  this(string message) {
    super(message);
  }
}

/// Thrown when a series is not found
class SeriesNotFoundException : TimeSeriesException {
  this(string name, string[string] tags) {
    super("Series not found: " ~ name ~ " " ~ tagsToString(tags));
  }

  private string tagsToString(string[string] tags) {
    if (tags.length == 0) {
      return "{}";
    }
    string result = "{";
    bool first = true;
    foreach (key, value; tags) {
      if (!first) result ~= ", ";
      result ~= key ~ "=" ~ value;
      first = false;
    }
    result ~= "}";
    return result;
  }
}

/// Thrown when a series already exists
class DuplicateSeriesException : TimeSeriesException {
  this(string name, string[string] tags) {
    super("Series already exists: " ~ name);
  }
}

/// Thrown when time ranges are invalid
class InvalidTimeRangeException : TimeSeriesException {
  this(string message) {
    super(message);
  }
}

/// Thrown when a point is invalid
class InvalidPointException : TimeSeriesException {
  this(string message) {
    super(message);
  }
}

/// Thrown when aggregation name is invalid
class InvalidAggregationException : TimeSeriesException {
  this(string name) {
    super("Invalid aggregation: " ~ name);
  }
}

/// Thrown for database-level errors
class TimeSeriesDatabaseException : TimeSeriesException {
  this(string message) {
    super(message);
  }
}
