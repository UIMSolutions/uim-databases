module uim.databases.rtad.storage.timeseries;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import std.datetime;
import vibe.data.json;
import vibe.core.log;
import uim.databases.rtad.storage.datapoint;

/// Time-series storage engine
class TimeSeriesStorage {
    private {
        string _name;
        TimeSeries[string] _series;
        ReadWriteMutex _mutex;
        size_t _maxPoints;
    }
    
    this(string name, size_t maxPointsPerSeries = 1_000_000) {
        _name = name;
        _maxPoints = maxPointsPerSeries;
        _mutex = new ReadWriteMutex();
        logInfo("TimeSeriesStorage '%s' initialized with %d max points per series", _name, _maxPoints);
    }
    
    @property string name() { return _name; }
    
    /// Insert or update time series
    void upsertMetric(string metric, string[string] tags, DataPoint point) {
        synchronized(_mutex.writer) {
            auto key = metric ~ "|" ~ formatTags(tags);
            
            if (!(key in _series)) {
                _series[key] = new TimeSeries(metric, tags);
            }
            
            _series[key].addPoint(point);
            
            // Enforce max points per series
            if (_series[key].pointCount() > _maxPoints) {
                enforceRetention(_series[key]);
            }
        }
    }
    
    /// Get time series
    TimeSeries getTimeSeries(string metric, string[string] tags) {
        synchronized(_mutex.reader) {
            auto key = metric ~ "|" ~ formatTags(tags);
            if (auto ts = key in _series) {
                return *ts;
            }
            return null;
        }
    }
    
    /// Query metrics
    TimeSeries[] queryMetrics(string pattern, SysTime start, SysTime end) {
        synchronized(_mutex.reader) {
            TimeSeries[] result;
            foreach (ts; _series.values) {
                if (matchesPattern(ts.metric, pattern)) {
                    auto filtered = ts.pointsBetween(start, end);
                    if (!filtered.empty) {
                        result ~= ts;
                    }
                }
            }
            return result;
        }
    }
    
    /// Get all metrics
    string[] getAllMetrics() {
        synchronized(_mutex.reader) {
            string[] metrics;
            foreach (ts; _series.values) {
                auto m = ts.metric;
                if (!metrics.canFind(m)) {
                    metrics ~= m;
                }
            }
            return metrics;
        }
    }
    
    /// Get series count
    @property size_t seriesCount() {
        synchronized(_mutex.reader) {
            return _series.length;
        }
    }
    
    /// Get total point count
    @property size_t totalPointCount() {
        synchronized(_mutex.reader) {
            size_t total = 0;
            foreach (ts; _series.values) {
                total += ts.pointCount();
            }
            return total;
        }
    }
    
    /// Clear old data
    void purgeOlderThan(SysTime cutoff) {
        synchronized(_mutex.writer) {
            foreach (key, ts; _series) {
                auto points = ts.points;
                auto filtered = points.filter!(p => p.timestamp >= cutoff).array;
                
                if (filtered.empty) {
                    _series.remove(key);
                }
            }
        }
    }
    
    private {
        void enforceRetention(TimeSeries ts) {
            auto points = ts.points;
            if (points.length > _maxPoints) {
                auto keepPoints = points[$ - _maxPoints / 2 .. $];
                // Would need mutable reference to actually trim, for now just log
                logWarn("Series %s exceeds max points: %d", ts.metric, points.length);
            }
        }
        
        bool matchesPattern(string metric, string pattern) {
            if (pattern == "*") return true;
            if (pattern == metric) return true;
            
            import std.string : startsWith, endsWith;
            if (pattern.startsWith("*") && pattern.endsWith("*")) {
                return metric.canFind(pattern[1 .. $ - 1]);
            }
            if (pattern.startsWith("*")) {
                return metric.endsWith(pattern[1 .. $]);
            }
            if (pattern.endsWith("*")) {
                return metric.startsWith(pattern[0 .. $ - 1]);
            }
            
            return false;
        }
        
        string formatTags(string[string] tags) {
            if (!tags) return "";
            
            string[] pairs;
            foreach (k, v; tags) {
                pairs ~= k ~ "=" ~ v;
            }
            
            return pairs.sort().join("|");
        }
    }
}

import std.algorithm : canFind;
