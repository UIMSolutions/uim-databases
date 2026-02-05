module uim.databases.rtad.aggregation.metrics;

import std.algorithm;
import std.array;
import std.math;
import vibe.data.json;

/// Aggregation result
struct AggregationResult {
    string metric;
    string[string] tags;
    
    // Aggregations
    double sum;
    double mean;
    double min;
    double max;
    double stddev;
    long count;
    double[] percentiles; // p50, p75, p95, p99
    
    Json toJson() {
        auto result = Json.emptyObject;
        result["metric"] = metric;
        
        if (tags) {
            auto tagsObj = Json.emptyObject;
            foreach (k, v; tags) {
                tagsObj[k] = v;
            }
            result["tags"] = tagsObj;
        }
        
        result["sum"] = sum;
        result["mean"] = mean;
        result["min"] = min;
        result["max"] = max;
        result["stddev"] = stddev;
        result["count"] = count;
        
        auto p = Json.emptyArray;
        foreach (pct; percentiles) {
            p ~= pct;
        }
        result["percentiles"] = p;
        
        return result;
    }
}

/// Aggregation engine
class AggregationEngine {
    /// Calculate aggregations
    static AggregationResult aggregate(string metric, string[string] tags, double[] values) {
        AggregationResult result;
        result.metric = metric;
        result.tags = tags;
        result.count = cast(long)values.length;
        
        if (values.empty) {
            return result;
        }
        
        // Sum and mean
        result.sum = 0;
        foreach (v; values) {
            result.sum += v;
        }
        result.mean = result.sum / values.length;
        
        // Min and max
        result.min = values.minElement();
        result.max = values.maxElement();
        
        // Standard deviation
        double variance = 0;
        foreach (v; values) {
            variance += (v - result.mean) * (v - result.mean);
        }
        variance /= values.length;
        result.stddev = sqrt(variance);
        
        // Percentiles
        auto sorted = values.dup.sort().array;
        result.percentiles = [
            percentile(sorted, 50),
            percentile(sorted, 75),
            percentile(sorted, 95),
            percentile(sorted, 99)
        ];
        
        return result;
    }
    
    /// Calculate rate of change
    static double[] calculateRate(double[] values) {
        double[] rates;
        for (size_t i = 1; i < values.length; i++) {
            rates ~= values[i] - values[i - 1];
        }
        return rates;
    }
    
    /// Moving average
    static double[] movingAverage(double[] values, size_t window) {
        double[] result;
        if (window > values.length) window = values.length;
        
        for (size_t i = 0; i < values.length - window + 1; i++) {
            double sum = 0;
            for (size_t j = i; j < i + window; j++) {
                sum += values[j];
            }
            result ~= sum / window;
        }
        return result;
    }
    
    /// Exponential weighted moving average
    static double[] ewma(double[] values, double alpha) {
        double[] result;
        if (values.empty) return result;
        
        result ~= values[0];
        for (size_t i = 1; i < values.length; i++) {
            result ~= alpha * values[i] + (1 - alpha) * result[i - 1];
        }
        return result;
    }
    
    private {
        static double percentile(double[] sorted, int p) {
            if (sorted.empty) return 0;
            int idx = (p * cast(int)sorted.length) / 100;
            if (idx >= sorted.length) idx = cast(int)sorted.length - 1;
            return sorted[idx];
        }
    }
}

import std.algorithm : minElement, maxElement, sort;
import std.array : array;
