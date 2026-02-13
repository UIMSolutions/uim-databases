/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.tsdb.classes.database;

import uim.databases.tsdb.interfaces;
import uim.databases.tsdb.errors;
import uim.databases.tsdb.classes.series;
import std.algorithm;
import std.array;
import std.datetime;

@safe:

/// Time series database implementation
class TimeSeriesDatabase : ITimeSeriesDatabase {
  private {
    string _name;
    TimeSeries[string] _series;
  }

  private struct AggState {
    double min;
    double max;
    double sum;
    ulong count;
    bool initialized;
  }

  this(string name = "tsdb") {
    _name = name;
  }

  string name() const {
    return _name;
  }

  override ITimeSeries createSeries(string name, string[string] tags) {
    auto key = buildSeriesKey(name, tags);
    if (key in _series) {
      throw new DuplicateSeriesException(name, tags);
    }
    auto series = new TimeSeries(name, tags);
    _series[key] = series;
    return series;
  }

  override ITimeSeries getSeries(string name, string[string] tags) {
    auto key = buildSeriesKey(name, tags);
    if (key !in _series) {
      throw new SeriesNotFoundException(name, tags);
    }
    return _series[key];
  }

  override bool hasSeries(string name, string[string] tags) const {
    auto key = buildSeriesKey(name, tags);
    return (key in _series) !is null;
  }

  override void deleteSeries(string name, string[string] tags) {
    auto key = buildSeriesKey(name, tags);
    if (key !in _series) {
      throw new SeriesNotFoundException(name, tags);
    }
    _series.remove(key);
  }

  override string[] listSeries() const {
    auto keys = _series.keys.dup;
    keys.sort();
    return keys;
  }

  override void writePoint(string name, string[string] tags, TimePoint point) {
    auto series = ensureSeries(name, tags);
    series.addPoint(point);
  }

  override void writePoints(string name, string[string] tags, TimePoint[] points) {
    auto series = ensureSeries(name, tags);
    series.addPoints(points);
  }

  override TimePoint[] query(string name, string[string] tags, SysTime from, SysTime to) {
    auto series = getSeries(name, tags);
    return series.queryRange(from, to);
  }

  override AggregationResult aggregate(string name, string[string] tags, SysTime from, SysTime to, Aggregation aggregation) {
    auto points = query(name, tags, from, to);
    return computeAggregation(points, aggregation, from, to);
  }

  override DownsamplePoint[] downsample(string name, string[string] tags, SysTime from, SysTime to, Duration interval, Aggregation aggregation) {
    if (interval.total!"msecs" <= 0) {
      throw new InvalidTimeRangeException("interval must be greater than zero");
    }

    auto points = query(name, tags, from, to);
    if (points.length == 0) {
      return [];
    }

    long fromMs = toMillis(from);
    long intervalMs = cast(long)interval.total!"msecs";

    AggState[long] buckets;

    foreach (point; points) {
      long pointMs = toMillis(point.timestamp);
      long bucket = fromMs + ((pointMs - fromMs) / intervalMs) * intervalMs;

      auto state = bucket in buckets ? buckets[bucket] : AggState(0, 0, 0, 0, false);

      if (!state.initialized) {
        state.min = point.value;
        state.max = point.value;
        state.sum = point.value;
        state.count = 1;
        state.initialized = true;
      } else {
        state.min = state.min < point.value ? state.min : point.value;
        state.max = state.max > point.value ? state.max : point.value;
        state.sum += point.value;
        state.count++;
      }

      buckets[bucket] = state;
    }

    long[] bucketKeys;
    foreach (key; buckets.keys) {
      bucketKeys ~= key;
    }
    bucketKeys.sort();

    DownsamplePoint[] result;
    foreach (key; bucketKeys) {
      auto state = buckets[key];
      double value = finalizeAggregation(state, aggregation);
      result ~= DownsamplePoint(fromMillis(key), value, state.count);
    }

    return result;
  }

  size_t seriesCount() const {
    return _series.length;
  }

  size_t totalPoints() const {
    size_t total = 0;
    foreach (series; _series) {
      total += series.count();
    }
    return total;
  }

  private TimeSeries ensureSeries(string name, string[string] tags) {
    auto key = buildSeriesKey(name, tags);
    if (key !in _series) {
      auto series = new TimeSeries(name, tags);
      _series[key] = series;
    }
    return _series[key];
  }

  private string buildSeriesKey(string name, string[string] tags) const {
    if (tags.length == 0) {
      return name;
    }

    auto keys = tags.keys.dup;
    keys.sort();

    string result = name ~ "|";
    bool first = true;

    foreach (key; keys) {
      if (!first) result ~= ";";
      result ~= key ~ "=" ~ tags[key];
      first = false;
    }

    return result;
  }

  private AggregationResult computeAggregation(TimePoint[] points, Aggregation aggregation, SysTime from, SysTime to) {
    AggregationResult result;
    result.aggregation = aggregation;
    result.from = from;
    result.to = to;
    result.count = cast(ulong)points.length;

    if (points.length == 0) {
      result.value = 0.0;
      return result;
    }

    double min = double.max;
    double max = -double.max;
    double sum = 0.0;

    foreach (point; points) {
      min = min < point.value ? min : point.value;
      max = max > point.value ? max : point.value;
      sum += point.value;
    }

    final switch (aggregation) {
      case Aggregation.MIN:
        result.value = min;
        break;
      case Aggregation.MAX:
        result.value = max;
        break;
      case Aggregation.SUM:
        result.value = sum;
        break;
      case Aggregation.COUNT:
        result.value = cast(double)points.length;
        break;
      case Aggregation.AVG:
        result.value = sum / points.length;
        break;
    }

    return result;
  }

  private double finalizeAggregation(AggState state, Aggregation aggregation) const {
    final switch (aggregation) {
      case Aggregation.MIN:
        return state.min;
      case Aggregation.MAX:
        return state.max;
      case Aggregation.SUM:
        return state.sum;
      case Aggregation.COUNT:
        return cast(double)state.count;
      case Aggregation.AVG:
        return state.sum / state.count;
    }
  }

  private long toMillis(SysTime time) const {
    return cast(long)time.toUnixTime.total!"msecs";
  }

  private SysTime fromMillis(long ms) const {
    return SysTime.fromUnixTime(dur!"msecs"(ms));
  }
}
