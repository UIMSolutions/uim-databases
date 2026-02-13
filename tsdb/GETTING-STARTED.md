# Time Series Database - Getting Started

This guide helps you build, run, and test the time series database module.

## Build and Run

```bash
cd tsdb
dub build
```

```bash
dub run
```

Server starts on http://localhost:8083

## Quick API Test

### Create a series

```bash
curl -X POST http://localhost:8083/tsdb/series \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu_usage",
    "tags": {"host": "api-01"}
  }'
```

### Write a point

```bash
curl -X POST http://localhost:8083/tsdb/write \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu_usage",
    "tags": {"host": "api-01"},
    "timestamp": "2026-02-13T10:00:00Z",
    "value": 42.5
  }'
```

### Query a range

```bash
curl -X POST http://localhost:8083/tsdb/query \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu_usage",
    "tags": {"host": "api-01"},
    "from": "2026-02-13T10:00:00Z",
    "to": "2026-02-13T11:00:00Z"
  }'
```

### Aggregate

```bash
curl -X POST http://localhost:8083/tsdb/aggregate \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu_usage",
    "tags": {"host": "api-01"},
    "from": "2026-02-13T10:00:00Z",
    "to": "2026-02-13T11:00:00Z",
    "aggregation": "AVG"
  }'
```

### Downsample

```bash
curl -X POST http://localhost:8083/tsdb/downsample \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cpu_usage",
    "tags": {"host": "api-01"},
    "from": "2026-02-13T10:00:00Z",
    "to": "2026-02-13T11:00:00Z",
    "intervalSeconds": 600,
    "aggregation": "AVG"
  }'
```

### Stats

```bash
curl http://localhost:8083/tsdb/stats
```

## Run Examples

```bash
# Basic examples
dub run :tsdb-example

# Advanced examples
dub run :tsdb-advanced-example
```

## Troubleshooting

### Port in use

Change the port in source/app.d:

```d
settings.port = 8083;
```

### Invalid timestamps

Use ISO 8601 timestamps (recommended) or epoch milliseconds.

Valid: 2026-02-13T10:00:00Z
Valid: 1766013600000

## Next Steps

- Read the full API documentation in README.md
- Explore advanced examples in tsdb-advanced-example.d
- Integrate with other UIM modules
