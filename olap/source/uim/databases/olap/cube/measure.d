module uim.databases.olap.cube.measure;

import vibe.data.json;

/// Aggregation function types
enum AggregationType {
    sum,
    avg,
    count,
    min,
    max,
    countDistinct
}

/// OLAP measure
class Measure {
    private {
        string _name;
        string _column;
        AggregationType _aggregation;
        string _format;
    }
    
    this(string name, string column, AggregationType aggregation = AggregationType.sum) {
        _name = name;
        _column = column;
        _aggregation = aggregation;
        _format = "%.2f";
    }
    
    /// Get measure name
    @property string name() {
        return _name;
    }
    
    /// Get source column
    @property string column() {
        return _column;
    }
    
    /// Get aggregation type
    @property AggregationType aggregation() {
        return _aggregation;
    }
    
    /// Set format string
    @property void format(string fmt) {
        _format = fmt;
    }
    
    /// Get format string
    @property string format() {
        return _format;
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["name"] = _name;
        result["column"] = _column;
        result["aggregation"] = _aggregation.to!string;
        result["format"] = _format;
        return result;
    }
}

import std.conv : to;
