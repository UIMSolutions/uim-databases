module uim.databases.rtad.storage.datapoint;

import std.datetime;
import vibe.data.json;

/// Data point in time-series
struct DataPoint {
    SysTime timestamp;
    string metric;
    double value;
    string[string] tags;
    
    this(SysTime ts, string met, double val, string[string] tgs = null) {
        timestamp = ts;
        metric = met;
        value = val;
        tags = tgs;
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["timestamp"] = timestamp.toISOExtString();
        result["metric"] = metric;
        result["value"] = value;
        
        if (tags) {
            auto tagsObj = Json.emptyObject;
            foreach (k, v; tags) {
                tagsObj[k] = v;
            }
            result["tags"] = tagsObj;
        }
        
        return result;
    }
}

/// Time series
class TimeSeries {
    private {
        string _metric;
        string[string] _tags;
        DataPoint[] _points;
    }
    
    this(string metric, string[string] tags = null) {
        _metric = metric;
        _tags = tags ? tags.dup : null;
    }
    
    @property string metric() { return _metric; }
    @property string[string] tags() { return _tags.dup; }
    @property DataPoint[] points() { return _points.dup; }
    
    void addPoint(DataPoint point) {
        _points ~= point;
    }
    
    size_t pointCount() {
        return _points.length;
    }
    
    DataPoint[] pointsBetween(SysTime start, SysTime end) {
        DataPoint[] result;
        foreach (p; _points) {
            if (p.timestamp >= start && p.timestamp <= end) {
                result ~= p;
            }
        }
        return result;
    }
    
    double[] values() {
        double[] result;
        foreach (p; _points) {
            result ~= p.value;
        }
        return result;
    }
}
