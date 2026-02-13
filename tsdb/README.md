# Time Series Database Module

A time series database implementation in D language using the vibe.d framework. Provides ingestion, querying, aggregation, and downsampling for time-indexed metrics.

## Features

- Time-indexed storage for numeric metrics
- Tag-based series identification
- Range queries with inclusive time bounds
- Aggregations: MIN, MAX, AVG, SUM, COUNT
- Downsampling with configurable intervals
- REST API with JSON payloads
- In-memory storage for fast analytics
- Type-safe D implementation with @safe annotations

## Quick Start

### Build

```bash
cd tsdb
dub build
```

### Run

```bash
dub run
```

Server listens on http://localhost:8083

### D Usage Example

```d
import uim.databases.tsdb;
import std.datetime;

void main() {
  auto db = new TimeSeriesDatabase("metrics");
  string[string] tags = ["host": "api-01"];

  db.createSeries("cpu", tags);
  db.writePoint("cpu", tags, TimePoint(Clock.currTime(), 42.5));

  auto now = Clock.currTime();
  auto points = db.query("cpu", tags, now - dur!"minutes"(10), now);
}
```

## REST API Reference

### 1) Create Series

POST /tsdb/series

```json
{
  "name": "cpu_usage",
  "tags": {
    "host": "api-01",
    "region": "eu-west"
  }
}
```

### 2) Delete Series

DELETE /tsdb/series

```json
{
  "name": "cpu_usage",
  "tags": {
    "host": "api-01",
    "region": "eu-west"
  }
}
```

### 3) List Series

GET /tsdb/series

### 4) Write Point

POST /tsdb/write

```json
{
  "name": "cpu_usage",
  "tags": {"host": "api-01"},
  "timestamp": "2026-02-13T10:00:00Z",
  "value": 42.5
}
```

### 5) Write Batch

POST /tsdb/write-batch

```json
{
  "name": "cpu_usage",
  "tags": {"host": "api-01"},
  "points": [
    {"timestamp": "2026-02-13T10:00:00Z", "value": 42.5},
    {"timestamp": "2026-02-13T10:05:00Z", "value": 44.1}
  ]
}
```

### 6) Query Range

POST /tsdb/query

```json
{
  "name": "cpu_usage",
  "tags": {"host": "api-01"},
  "from": "2026-02-13T10:00:00Z",
  "to": "2026-02-13T11:00:00Z"
}
```

### 7) Aggregate Range

POST /tsdb/aggregate

```json
{
  "name": "cpu_usage",
  "tags": {"host": "api-01"},
  "from": "2026-02-13T10:00:00Z",
  "to": "2026-02-13T11:00:00Z",
  "aggregation": "AVG"
}
```

### 8) Downsample Range

POST /tsdb/downsample

```json
{
  "name": "cpu_usage",
  "tags": {"host": "api-01"},
  "from": "2026-02-13T10:00:00Z",
  "to": "2026-02-13T11:00:00Z",
  "intervalSeconds": 600,
  "aggregation": "AVG"
}
```

### 9) Stats

GET /tsdb/stats

## Timestamp Formats

- ISO 8601 (recommended): 2026-02-13T10:00:00Z
- Epoch milliseconds: 1766013600000

## Examples

- tsdb-example.d - Basic usage
- tsdb-advanced-example.d - Multi-series patterns

## Dependencies

- D language 2.101.0+
- vibe.d ~0.9.0
- uim-framework ~26.2.2

## License

Apache 2.0
