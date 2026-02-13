/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.tsdb.api.rest;

import uim.databases.tsdb;
import vibe.d;
import std.algorithm;
import std.conv;
import std.datetime;
import std.string;

@safe:

/// Request/Response structs
struct CreateSeriesRequest {
  string name;
  string[string] tags;
}

struct DeleteSeriesRequest {
  string name;
  string[string] tags;
}

struct WritePointRequest {
  string name;
  string[string] tags;
  string timestamp; // ISO 8601 or epoch millis
  double value;
}

struct PointRequest {
  string timestamp; // ISO 8601 or epoch millis
  double value;
}

struct WriteBatchRequest {
  string name;
  string[string] tags;
  PointRequest[] points;
}

struct QueryRequest {
  string name;
  string[string] tags;
  string from;
  string to;
}

struct AggregateRequest {
  string name;
  string[string] tags;
  string from;
  string to;
  string aggregation;
}

struct DownsampleRequest {
  string name;
  string[string] tags;
  string from;
  string to;
  ulong intervalSeconds;
  string aggregation;
}

struct SeriesListResponse {
  string[] series;
  size_t count;
}

/// REST API handler
class TimeSeriesAPI {
  private TimeSeriesDatabase db;

  this(TimeSeriesDatabase database) {
    this.db = database;
  }

  // POST /tsdb/series - Create series
  @method(HTTPMethod.POST)
  @path("/tsdb/series")
  Json createSeries(CreateSeriesRequest req) {
    Json response = Json.emptyObject;
    try {
      db.createSeries(req.name, req.tags);
      response["success"] = true;
      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // DELETE /tsdb/series - Delete series
  @method(HTTPMethod.DELETE)
  @path("/tsdb/series")
  Json deleteSeries(DeleteSeriesRequest req) {
    Json response = Json.emptyObject;
    try {
      db.deleteSeries(req.name, req.tags);
      response["success"] = true;
      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // GET /tsdb/series - List series
  @method(HTTPMethod.GET)
  @path("/tsdb/series")
  SeriesListResponse listSeries() {
    SeriesListResponse response;
    response.series = db.listSeries();
    response.count = response.series.length;
    return response;
  }

  // POST /tsdb/write - Write a single point
  @method(HTTPMethod.POST)
  @path("/tsdb/write")
  Json writePoint(WritePointRequest req) {
    Json response = Json.emptyObject;
    try {
      auto point = TimePoint(parseTimestamp(req.timestamp), req.value);
      db.writePoint(req.name, req.tags, point);
      response["success"] = true;
      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /tsdb/write-batch - Write multiple points
  @method(HTTPMethod.POST)
  @path("/tsdb/write-batch")
  Json writeBatch(WriteBatchRequest req) {
    Json response = Json.emptyObject;
    try {
      TimePoint[] points;
      foreach (p; req.points) {
        points ~= TimePoint(parseTimestamp(p.timestamp), p.value);
      }
      db.writePoints(req.name, req.tags, points);
      response["success"] = true;
      response["count"] = req.points.length;
      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /tsdb/query - Query range
  @method(HTTPMethod.POST)
  @path("/tsdb/query")
  Json queryRange(QueryRequest req) {
    Json response = Json.emptyObject;
    try {
      auto from = parseTimestamp(req.from);
      auto to = parseTimestamp(req.to);
      auto points = db.query(req.name, req.tags, from, to);

      Json[] pointJson;
      foreach (point; points) {
        auto item = Json.emptyObject;
        item["timestamp"] = point.timestamp.toISOExtString();
        item["value"] = point.value;
        pointJson ~= item;
      }

      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
      response["count"] = points.length;
      response["points"] = pointJson;
      response["success"] = true;
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /tsdb/aggregate - Aggregate range
  @method(HTTPMethod.POST)
  @path("/tsdb/aggregate")
  Json aggregateRange(AggregateRequest req) {
    Json response = Json.emptyObject;
    try {
      auto from = parseTimestamp(req.from);
      auto to = parseTimestamp(req.to);
      auto agg = parseAggregation(req.aggregation);
      auto result = db.aggregate(req.name, req.tags, from, to, agg);

      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
      response["aggregation"] = req.aggregation;
      response["count"] = result.count;
      response["value"] = result.value;
      response["from"] = result.from.toISOExtString();
      response["to"] = result.to.toISOExtString();
      response["success"] = true;
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /tsdb/downsample - Downsample range
  @method(HTTPMethod.POST)
  @path("/tsdb/downsample")
  Json downsampleRange(DownsampleRequest req) {
    Json response = Json.emptyObject;
    try {
      auto from = parseTimestamp(req.from);
      auto to = parseTimestamp(req.to);
      auto agg = parseAggregation(req.aggregation);
      auto interval = dur!"seconds"(req.intervalSeconds);
      auto buckets = db.downsample(req.name, req.tags, from, to, interval, agg);

      Json[] bucketJson;
      foreach (bucket; buckets) {
        auto item = Json.emptyObject;
        item["timestamp"] = bucket.timestamp.toISOExtString();
        item["value"] = bucket.value;
        item["count"] = bucket.count;
        bucketJson ~= item;
      }

      response["seriesKey"] = buildSeriesKey(req.name, req.tags);
      response["count"] = buckets.length;
      response["buckets"] = bucketJson;
      response["success"] = true;
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // GET /tsdb/stats - Database stats
  @method(HTTPMethod.GET)
  @path("/tsdb/stats")
  Json getStats() {
    Json response = Json.emptyObject;
    response["databaseName"] = db.name();
    response["seriesCount"] = db.seriesCount();
    response["totalPoints"] = db.totalPoints();
    return response;
  }

  private SysTime parseTimestamp(string value) {
    if (value.length == 0) {
      return Clock.currTime();
    }

    try {
      return SysTime.fromISOExtString(value);
    } catch (Exception) {
      // Fall back to epoch milliseconds
    }

    long ms = to!long(value);
    return SysTime.fromUnixTime(dur!"msecs"(ms));
  }

  private Aggregation parseAggregation(string value) {
    auto upper = value.strip.toUpper();
    final switch (upper) {
      case "MIN": return Aggregation.MIN;
      case "MAX": return Aggregation.MAX;
      case "AVG": return Aggregation.AVG;
      case "SUM": return Aggregation.SUM;
      case "COUNT": return Aggregation.COUNT;
      default: throw new InvalidAggregationException(value);
    }
  }

  private string buildSeriesKey(string name, string[string] tags) {
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
}
