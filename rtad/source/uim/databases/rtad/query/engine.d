module uim.databases.rtad.query.engine;

import std.datetime;
import std.algorithm;
import std.array;
import vibe.data.json;
import uim.databases.rtad.storage;
import uim.databases.rtad.aggregation;

/// Query result
struct QueryResult {
    AggregationResult[] results;
    SysTime queryStart;
    SysTime queryEnd;
    long executionTimeMs;
    bool success;
    
    Json toJson() {
        auto result = Json.emptyObject;
        
        auto resultsArr = Json.emptyArray;
        foreach (r; results) {
            resultsArr ~= r.toJson();
        }
        result["results"] = resultsArr;
        
        result["queryStart"] = queryStart.toISOExtString();
        result["queryEnd"] = queryEnd.toISOExtString();
        result["executionTimeMs"] = executionTimeMs;
        result["success"] = success;
        result["resultCount"] = cast(long)results.length;
        
        return result;
    }
}

/// Real-time analytics query engine
class QueryEngine {
    private {
        TimeSeriesStorage _storage;
    }
    
    this(TimeSeriesStorage storage) {
        _storage = storage;
    }
    
    /// Query metrics with aggregations
    QueryResult queryMetrics(string pattern, SysTime start, SysTime end) {
        auto startTime = SysTime.fromUnixTime(Clock.currTime().toUnixTime());
        
        auto series = _storage.queryMetrics(pattern, start, end);
        
        AggregationResult[] results;
        foreach (ts; series) {
            auto values = ts.values();
            if (!values.empty) {
                auto agg = AggregationEngine.aggregate(ts.metric, ts.tags, values);
                results ~= agg;
            }
        }
        
        auto endTime = Clock.currTime();
        long execTime = (endTime - startTime).total!"msecs";
        
        return QueryResult(results, start, end, execTime, true);
    }
    
    /// Query latest values
    QueryResult queryLatest(string pattern) {
        auto now = Clock.currTime();
        auto oneHourAgo = now - dur!"hours"(1);
        
        return queryMetrics(pattern, oneHourAgo, now);
    }
    
    /// Query by time window and aggregation
    QueryResult queryWindow(string metric, string[string] tags, SysTime start, SysTime end, string aggregation = "mean") {
        auto ts = _storage.getTimeSeries(metric, tags);
        if (!ts) {
            return QueryResult([], start, end, 0, false);
        }
        
        auto startTime = Clock.currTime();
        
        auto points = ts.pointsBetween(start, end);
        auto values = points.map!(p => p.value).array;
        
        AggregationResult[] results;
        if (!values.empty) {
            auto agg = AggregationEngine.aggregate(metric, tags, values);
            results ~= agg;
        }
        
        auto endTime = Clock.currTime();
        long execTime = (endTime - startTime).total!"msecs";
        
        return QueryResult(results, start, end, execTime, !results.empty);
    }
    
    /// Get available metrics
    string[] getAvailableMetrics() {
        return _storage.getAllMetrics();
    }
    
    /// Get storage statistics
    Json getStorageStats() {
        auto result = Json.emptyObject;
        result["name"] = _storage.name;
        result["seriesCount"] = cast(long)_storage.seriesCount;
        result["totalPoints"] = cast(long)_storage.totalPointCount;
        return result;
    }
}

import std.datetime.systime;
