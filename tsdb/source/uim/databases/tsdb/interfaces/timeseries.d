/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.tsdb.interfaces.timeseries;

import std.datetime;

@safe:

/// Aggregation operations
enum Aggregation {
  MIN,
  MAX,
  AVG,
  SUM,
  COUNT
}

/// A single time series data point
struct TimePoint {
  SysTime timestamp;
  double value;
}

/// Aggregation result
struct AggregationResult {
  Aggregation aggregation;
  double value;
  ulong count;
  SysTime from;
  SysTime to;
}

/// Downsampled time bucket
struct DownsamplePoint {
  SysTime timestamp;
  double value;
  ulong count;
}

/// Time series interface
interface ITimeSeries {
  string name();
  string[string] tags();
  void addPoint(TimePoint point);
  void addPoints(TimePoint[] points);
  TimePoint[] queryRange(SysTime from, SysTime to);
  TimePoint latest();
  size_t count();
}

/// Time series database interface
interface ITimeSeriesDatabase {
  ITimeSeries createSeries(string name, string[string] tags);
  ITimeSeries getSeries(string name, string[string] tags);
  bool hasSeries(string name, string[string] tags);
  void deleteSeries(string name, string[string] tags);
  string[] listSeries();

  void writePoint(string name, string[string] tags, TimePoint point);
  void writePoints(string name, string[string] tags, TimePoint[] points);

  TimePoint[] query(string name, string[string] tags, SysTime from, SysTime to);
  AggregationResult aggregate(string name, string[string] tags, SysTime from, SysTime to, Aggregation aggregation);
  DownsamplePoint[] downsample(string name, string[string] tags, SysTime from, SysTime to, Duration interval, Aggregation aggregation);
}
