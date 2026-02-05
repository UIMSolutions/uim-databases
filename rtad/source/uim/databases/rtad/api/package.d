module uim.databases.rtad.api;

import vibe.http.router;
import vibe.http.server;
import vibe.core.log;
import vibe.data.json;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import uim.databases.rtad.storage;
import uim.databases.rtad.stream;
import uim.databases.rtad.query;

/// Real-time Analytics Database REST API
class RTADRestAPI {
    private {
        TimeSeriesStorage _storage;
        StreamProcessor _processor;
        QueryEngine _queryEngine;
        URLRouter _router;
    }
    
    this(TimeSeriesStorage storage, StreamProcessor processor, QueryEngine queryEngine) {
        _storage = storage;
        _processor = processor;
        _queryEngine = queryEngine;
        _router = new URLRouter();
        setupRoutes();
    }
    
    @property URLRouter router() {
        return _router;
    }
    
    private {
        void setupRoutes() {
            // Data ingestion
            _router.post("/rtad/metrics", &handlePushMetric);
            _router.post("/rtad/metrics/batch", &handlePushBatch);
            _router.post("/rtad/flush", &handleFlush);
            
            // Queries
            _router.get("/rtad/query/pattern/:pattern", &handleQueryPattern);
            _router.get("/rtad/query/latest/:pattern", &handleQueryLatest);
            _router.get("/rtad/query/window/:metric", &handleQueryWindow);
            
            // Metrics
            _router.get("/rtad/metrics", &handleGetMetrics);
            _router.get("/rtad/stats", &handleGetStats);
            _router.get("/rtad/health", &handleHealth);
        }
        
        void handlePushMetric(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto body_ = req.json;
                
                auto metric = "metric" in body_ ? body_["metric"].get!string : "";
                auto value = "value" in body_ ? body_["value"].get!double : 0.0;
                auto timestamp = "timestamp" in body_ ? 
                    SysTime.fromISOExtString(body_["timestamp"].get!string) : 
                    Clock.currTime();
                
                string[string] tags;
                // Tags handling - simplified to avoid vibe.d JSON API complexity
                
                auto point = DataPoint(timestamp, metric, value, tags);
                _processor.pushDataPoint(point);
                
                auto result = Json.emptyObject;
                result["message"] = "Metric ingested";
                result["metric"] = metric;
                result["timestamp"] = timestamp.toISOExtString();
                res.statusCode = 202;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handlePushBatch(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto body_ = req.json;
                
                if (!("metrics" in body_)) {
                    res.statusCode = 400;
                    res.writeJsonBody(["error": "Missing 'metrics' array"]);
                    return;
                }
                
                DataPoint[] points;
                foreach (metricJson; body_["metrics"].array) {
                    auto metric = "metric" in metricJson ? metricJson["metric"].get!string : "";
                    auto value = "value" in metricJson ? metricJson["value"].get!double : 0.0;
                    auto timestamp = "timestamp" in metricJson ? 
                        SysTime.fromISOExtString(metricJson["timestamp"].get!string) : 
                        Clock.currTime();
                    
                    string[string] tags;
                    // Tags handling - simplified
                    
                    points ~= DataPoint(timestamp, metric, value, tags);
                }
                
                _processor.pushDataPoints(points);
                
                auto result = Json.emptyObject;
                result["message"] = "Batch ingested";
                result["count"] = cast(long)points.length;
                res.statusCode = 202;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleFlush(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                _processor.flush();
                
                auto result = Json.emptyObject;
                result["message"] = "Flushed to storage";
                result["timestamp"] = Clock.currTime().toISOExtString();
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleQueryPattern(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto pattern = req.params.get("pattern", "*");
                auto start = req.query.get("start", "");
                auto end = req.query.get("end", "");
                
                SysTime startTime, endTime;
                if (start) {
                    startTime = SysTime.fromISOExtString(start);
                } else {
                    startTime = Clock.currTime() - dur!"hours"(1);
                }
                
                if (end) {
                    endTime = SysTime.fromISOExtString(end);
                } else {
                    endTime = Clock.currTime();
                }
                
                auto queryResult = _queryEngine.queryMetrics(pattern, startTime, endTime);
                res.writeJsonBody(queryResult.toJson());
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleQueryLatest(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto pattern = req.params.get("pattern", "*");
                auto queryResult = _queryEngine.queryLatest(pattern);
                res.writeJsonBody(queryResult.toJson());
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleQueryWindow(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto metric = req.params.get("metric", "");
                auto start = req.query.get("start", "");
                auto end = req.query.get("end", "");
                auto agg = req.query.get("aggregation", "mean");
                
                if (!start || !end) {
                    res.statusCode = 400;
                    res.writeJsonBody(["error": "start and end parameters required"]);
                    return;
                }
                
                auto startTime = SysTime.fromISOExtString(start);
                auto endTime = SysTime.fromISOExtString(end);
                
                string[string] tags;
                foreach (key; req.query.byKey()) {
                    if (key != "start" && key != "end" && key != "aggregation") {
                        tags[key] = req.query.get(key, "");
                    }
                }
                
                auto queryResult = _queryEngine.queryWindow(metric, tags, startTime, endTime, agg);
                res.writeJsonBody(queryResult.toJson());
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleGetMetrics(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto metrics = _queryEngine.getAvailableMetrics();
                
                auto result = Json.emptyObject;
                result["metrics"] = serializeToJson(metrics);
                result["count"] = cast(long)metrics.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleGetStats(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto stats = _queryEngine.getStorageStats();
                auto bufferSize = _processor.bufferLength;
                
                stats["bufferLength"] = cast(long)bufferSize;
                stats["timestamp"] = Clock.currTime().toISOExtString();
                
                res.writeJsonBody(stats);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJsonBody(["error": e.msg]);
            }
        }
        
        void handleHealth(HTTPServerRequest req, HTTPServerResponse res) {
            auto result = Json.emptyObject;
            result["status"] = "healthy";
            result["timestamp"] = Clock.currTime().toISOExtString();
            result["storage"] = _queryEngine.getStorageStats();
            res.writeJsonBody(result);
        }
    }
}

import vibe.http.router;
