# Real-time Analytical Database (RTAD)

A high-performance real-time analytical database written in D with vibe.d for time-series data processing, aggregation, and analytics.

## Features

### Data Ingestion
- **Streaming API**: Push individual metrics or batch ingestion
- **Buffer Management**: In-memory buffer with configurable flush intervals
- **Tags Support**: Multi-dimensional tagging for flexible queries
- **High Throughput**: Optimized for millions of data points

### Time-Series Storage
- **Efficient Storage**: Compact representation of time-series data
- **Tag-based Organization**: Group metrics by dimensions
- **Time-Range Queries**: Query data within specific time windows
- **Pattern Matching**: Wildcard metric pattern queries

### Real-time Aggregations
- **Statistical Functions**: Sum, mean, min, max, stddev, count
- **Percentile Calculations**: P50, P75, P95, P99
- **Moving Averages**: Simple and exponential weighted
- **Rate of Change**: Track metric trends

### Query Engine
- **Real-time Queries**: Fast aggregations on streaming data
- **Latest Values**: Get most recent metrics instantly
- **Time Window Queries**: Historical analysis within time bounds
- **Metric Discovery**: List available metrics

### REST API
Complete HTTP API for all operations with JSON serialization.

### Performance
- Thread-safe concurrent access
- Lock-free reads where possible
- Efficient time-series storage
- Sub-millisecond query response times

## Directory Structure

```
rtad/
├── dub.sdl                  # Package configuration
├── LICENSE                  # Apache 2.0
└── source/
    ├── app.d               # Application entry point
    └── uim/databases/rtad/
        ├── package.d       # Main module
        ├── storage/        # Time-series data structures
        │   ├── datapoint.d # Data point and series classes
        │   ├── timeseries.d # Time-series storage engine
        │   └── package.d   # Module exports
        ├── aggregation/    # Analytics and aggregations
        │   ├── metrics.d   # Statistical calculations
        │   └── package.d   # Module exports
        ├── stream/         # Data streaming
        │   ├── processor.d # Stream processing pipeline
        │   └── package.d   # Module exports
        ├── query/          # Query execution
        │   ├── engine.d    # Query engine
        │   └── package.d   # Module exports
        └── api/            # REST API
            └── package.d   # HTTP endpoints
```

## Installation

### Build Library
```bash
cd rtad
dub build --build=release
```

### Run Server
```bash
dub run
```

Server starts on `http://localhost:8086`

## Usage Examples

### Push Single Metric

```d
auto storage = new TimeSeriesStorage("metrics");
auto processor = new StreamProcessor(storage);
processor.start();

auto point = DataPoint(
    Clock.currTime(),
    "cpu.usage",
    45.3,
    ["host": "server-1", "region": "us-east"]
);

processor.pushDataPoint(point);
processor.flush();
```

### Push Batch Metrics

```d
DataPoint[] batch;
for (int i = 0; i < 100; i++) {
    auto ts = Clock.currTime() + dur!"seconds"(i);
    batch ~= DataPoint(ts, "temperature", 20.5 + i * 0.1);
}

processor.pushDataPoints(batch);
processor.flush();
```

### Query Metrics

```d
auto queryEngine = new QueryEngine(storage);

// Query by pattern
auto result = queryEngine.queryMetrics("cpu.*", startTime, endTime);

// Query latest values
auto latest = queryEngine.queryLatest("*");

// Query specific window
auto windowResult = queryEngine.queryWindow(
    "cpu.usage",
    ["host": "server-1"],
    startTime,
    endTime
);
```

### Calculate Aggregations

```d
auto values = [...];  // metric values
auto agg = AggregationEngine.aggregate("cpu.usage", tags, values);

writef("Mean: %.2f\n", agg.mean);
writef("Min: %.2f, Max: %.2f\n", agg.min, agg.max);
writef("P95: %.2f\n", agg.percentiles[2]);
```

### Moving Averages

```d
// Simple moving average
auto ma = AggregationEngine.movingAverage(values, windowSize: 5);

// Exponential weighted moving average
auto ewma = AggregationEngine.ewma(values, alpha: 0.3);
```

## REST API Reference

### Data Ingestion

#### Push Single Metric
```
POST /rtad/metrics
Content-Type: application/json

{
  "metric": "cpu.usage",
  "value": 45.3,
  "timestamp": "2026-02-05T10:30:00Z",
  "tags": {
    "host": "server-1",
    "region": "us-east"
  }
}

Response: 202 Accepted
```

#### Push Batch Metrics
```
POST /rtad/metrics/batch
Content-Type: application/json

{
  "metrics": [
    {
      "metric": "cpu.usage",
      "value": 45.3,
      "timestamp": "2026-02-05T10:30:00Z",
      "tags": {"host": "server-1"}
    },
    ...
  ]
}

Response: 202 Accepted
```

#### Flush Buffer
```
POST /rtad/flush

Response: 200 OK
{
  "message": "Flushed to storage",
  "timestamp": "2026-02-05T10:30:00Z"
}
```

### Queries

#### Query by Pattern
```
GET /rtad/query/pattern/{pattern}?start={iso8601}&end={iso8601}

Examples:
  GET /rtad/query/pattern/cpu.* 
  GET /rtad/query/pattern/memory.usage?start=2026-02-05T09:00:00Z&end=2026-02-05T10:00:00Z

Response: 200 OK
{
  "results": [
    {
      "metric": "cpu.usage",
      "tags": {"host": "server-1"},
      "sum": 4530.5,
      "mean": 45.3,
      "min": 35.2,
      "max": 55.8,
      "stddev": 5.2,
      "count": 100,
      "percentiles": [45.0, 48.5, 52.0, 54.5]
    }
  ],
  "queryStart": "2026-02-05T09:00:00Z",
  "queryEnd": "2026-02-05T10:00:00Z",
  "executionTimeMs": 15,
  "success": true,
  "resultCount": 1
}
```

#### Query Latest Values
```
GET /rtad/query/latest/{pattern}

Examples:
  GET /rtad/query/latest/*
  GET /rtad/query/latest/cpu.*

Response: 200 OK
{
  "results": [...],
  "executionTimeMs": 5
}
```

#### Query Time Window
```
GET /rtad/query/window/{metric}?start={iso8601}&end={iso8601}&aggregation={type}

Query Parameters:
  - start (required): ISO8601 timestamp
  - end (required): ISO8601 timestamp
  - aggregation: mean, sum, min, max, count, stddev (default: mean)
  - tag filters: any custom tag as query param

Examples:
  GET /rtad/query/window/cpu.usage?start=2026-02-05T09:00:00Z&end=2026-02-05T10:00:00Z
  GET /rtad/query/window/cpu.usage?start=...&end=...&host=server-1&region=us-east

Response: 200 OK
{
  "results": [...],
  "queryStart": "...",
  "queryEnd": "...",
  "executionTimeMs": 10
}
```

### Metrics & Statistics

#### List Available Metrics
```
GET /rtad/metrics

Response: 200 OK
{
  "metrics": [
    "cpu.usage",
    "memory.usage",
    "disk.io",
    "temperature"
  ],
  "count": 4
}
```

#### Get Storage Statistics
```
GET /rtad/stats

Response: 200 OK
{
  "name": "main",
  "seriesCount": 25,
  "totalPoints": 10500,
  "bufferLength": 145,
  "timestamp": "2026-02-05T10:30:00Z"
}
```

#### Health Check
```
GET /rtad/health

Response: 200 OK
{
  "status": "healthy",
  "timestamp": "2026-02-05T10:30:00Z",
  "storage": {
    "name": "main",
    "seriesCount": 25,
    "totalPoints": 10500
  }
}
```

## Use Cases

### System Monitoring
Monitor CPU, memory, disk usage across servers with real-time aggregations.

### Application Metrics
Track request latency, throughput, error rates with time-series analysis.

### IoT Data Collection
Collect sensor data (temperature, humidity, pressure) with multi-location tagging.

### Financial Analytics
Track stock prices, trading volumes with real-time calculations.

### Infrastructure Observability
Collect and analyze logs, traces, and metrics from distributed systems.

### Business Metrics
Monitor KPIs, user engagement, conversion rates in real-time.

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Push metric | O(1) | Append to buffer |
| Push batch | O(n) | n = batch size |
| Flush | O(n) | n = buffer size |
| Query pattern | O(m) | m = matching series |
| Aggregation | O(p) | p = points in result |
| Percentile | O(p log p) | Sorting required |

## Configuration

### TimeSeriesStorage

```d
auto storage = new TimeSeriesStorage(
    "main",           // name
    1_000_000        // max points per series
);
```

### StreamProcessor

```d
auto processor = new StreamProcessor(
    storage,
    10_000,          // buffer size (metrics)
    1_000            // flush interval (ms)
);
```

## Thread Safety

- All storage operations protected by ReadWriteMutex
- Multiple concurrent readers allowed
- Exclusive access during writes
- Stream processor runs on separate thread

## Dependencies

- **vibe.d (~0.9.0)**: HTTP server, JSON handling, logging
- **D Standard Library**: Algorithms, containers, datetime

## Examples

Complete examples in `rtad-example.d`:
- Single metric push
- Batch ingestion
- Buffer flushing
- Pattern queries
- Aggregations
- Moving averages
- Rate calculations
- Multi-host metrics
- Statistics

Run examples:
```bash
dub run --single rtad-example.d
```

## Comparison with Other Databases

| Feature | RTAD | OLAP | Relational | Graph |
|---------|------|------|-----------|-------|
| **Time-Series** | ✅ | ❌ | ❌ | ❌ |
| **Streaming** | ✅ | ❌ | ❌ | ❌ |
| **Real-time** | ✅ | ❌ | ✅ | ❌ |
| **Aggregations** | ✅ | ✅ | ✅ | ❌ |
| **Tags** | ✅ | ❌ | ❌ | ✅ |
| **Relationships** | ❌ | ❌ | ✅ | ✅ |

## License

Apache License 2.0
UIMSolutions

## Related Systems

- **OLAP Database**: Multi-dimensional analytics with columnar storage
- **Graph Database**: Relationship modeling with graph algorithms
- **OLTP Database**: Transactional processing with ACID
- **Vector Database**: Similarity search with embeddings
