# Time Series Database Implementation

## Overview

The Time Series Database (TSDB) module provides in-memory storage and querying for time-indexed metrics. It supports tag-based series identification, range queries, aggregation, and downsampling. The module is built with D language and integrates with vibe.d for REST APIs.

## Architecture

```
TimeSeriesDatabase
  ├── TimeSeries
  │   ├── TimePoint[] (sorted by timestamp)
  │   └── Range query via binary search
  ├── Aggregation engine (MIN/MAX/AVG/SUM/COUNT)
  └── REST API (vibe.d)
```

## Core Types

### TimePoint

```d
struct TimePoint {
  SysTime timestamp;
  double value;
}
```

### Aggregation

```d
enum Aggregation {
  MIN,
  MAX,
  AVG,
  SUM,
  COUNT
}
```

### DownsamplePoint

```d
struct DownsamplePoint {
  SysTime timestamp;
  double value;
  ulong count;
}
```

## Interfaces

### ITimeSeries

```d
interface ITimeSeries {
  string name();
  string[string] tags();
  void addPoint(TimePoint point);
  void addPoints(TimePoint[] points);
  TimePoint[] queryRange(SysTime from, SysTime to);
  TimePoint latest();
  size_t count();
}
```

### ITimeSeriesDatabase

```d
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
```

## Query Strategy

- Points are kept sorted by timestamp
- Binary search identifies query range boundaries
- Range queries return slices of the underlying array

## Aggregation

Aggregation is computed over a range query:

- MIN: smallest value
- MAX: largest value
- SUM: total value
- COUNT: number of points
- AVG: average value

## Downsampling

Downsampling groups data into fixed-size buckets based on timestamp:

- Compute bucket start using interval
- Aggregate points per bucket
- Return buckets in chronological order

## REST API

The REST API uses JSON payloads and provides:

- Series creation and deletion
- Writing points (single and batch)
- Range queries
- Aggregations
- Downsampling
- Database statistics

## Performance

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Write point | O(n) | Inserts keep sorted order |
| Range query | O(log n + k) | Binary search + slice |
| Aggregate | O(k) | Iterates range results |
| Downsample | O(k) | Linear scan of range |

## Limitations

- In-memory only (no persistence)
- Single-process storage
- Numeric values only (double)

## Extension Ideas

- Add persistence (WAL or file-based)
- Support multiple numeric fields per point
- Compression and segment storage
- Index by tags for faster lookups
