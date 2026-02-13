/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.tsdb.classes.series;

import uim.databases.tsdb.interfaces;
import uim.databases.tsdb.errors;
import std.datetime;
import std.math;

@safe:

/// Time series implementation
class TimeSeries : ITimeSeries {
  private {
    string _name;
    string[string] _tags;
    TimePoint[] _points;
  }

  this(string name, string[string] tags) {
    _name = name;
    _tags = tags.dup;
    _points = [];
  }

  override string name() const {
    return _name;
  }

  override string[string] tags() const {
    return _tags.dup;
  }

  override void addPoint(TimePoint point) {
    if (isNaN(point.value) || isInfinity(point.value)) {
      throw new InvalidPointException("Point value must be finite");
    }

    if (_points.length == 0 || _points[$ - 1].timestamp <= point.timestamp) {
      _points ~= point;
      return;
    }

    size_t index = lowerBoundIndex(point.timestamp);
    _points = _points[0 .. index] ~ [point] ~ _points[index .. $];
  }

  override void addPoints(TimePoint[] points) {
    foreach (point; points) {
      addPoint(point);
    }
  }

  override TimePoint[] queryRange(SysTime from, SysTime to) {
    if (from > to) {
      throw new InvalidTimeRangeException("from must be <= to");
    }

    if (_points.length == 0) {
      return [];
    }

    size_t start = lowerBoundIndex(from);
    size_t end = upperBoundIndex(to);

    if (start >= end) {
      return [];
    }

    return _points[start .. end].dup;
  }

  override TimePoint latest() {
    if (_points.length == 0) {
      throw new InvalidPointException("Series has no points");
    }
    return _points[$ - 1];
  }

  override size_t count() const {
    return _points.length;
  }

  private size_t lowerBoundIndex(SysTime target) const {
    size_t left = 0;
    size_t right = _points.length;

    while (left < right) {
      size_t mid = (left + right) / 2;
      if (_points[mid].timestamp < target) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    return left;
  }

  private size_t upperBoundIndex(SysTime target) const {
    size_t left = 0;
    size_t right = _points.length;

    while (left < right) {
      size_t mid = (left + right) / 2;
      if (_points[mid].timestamp <= target) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }

    return left;
  }
}
