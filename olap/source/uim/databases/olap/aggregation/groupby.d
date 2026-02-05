module uim.databases.olap.aggregation.groupby;

import std.variant;
import std.algorithm;
import std.array;
import vibe.data.json;
import uim.databases.olap.storage.column;
import uim.databases.olap.cube.measure;

/// Group-by result
struct GroupByResult {
    Json key;
    double[string] aggregates;
    size_t count;
}

/// Group-by aggregation
class GroupBy {
    private {
        string[] _groupByColumns;
        GroupByResult[string] _groups;
    }
    
    this(string[] groupByColumns) {
        _groupByColumns = groupByColumns.dup;
    }
    
    /// Add value to group
    void add(Json key, string measureName, double value) {
        string keyStr = key.toString();
        
        if (keyStr !in _groups) {
            _groups[keyStr] = GroupByResult(key, null, 0);
        }
        
        auto group = &_groups[keyStr];
        
        if (measureName !in group.aggregates) {
            group.aggregates[measureName] = 0;
        }
        
        group.aggregates[measureName] += value;
        group.count++;
    }
    
    /// Get results
    GroupByResult[] getResults() {
        return _groups.values.array;
    }
    
    /// Get results as JSON
    Json[] getResultsJson() {
        Json[] results;
        foreach (group; _groups.values) {
            auto result = Json.emptyObject;
            result["key"] = group.key;
            result["count"] = group.count;
            
            auto aggs = Json.emptyObject;
            foreach (name, value; group.aggregates) {
                aggs[name] = value;
            }
            result["aggregates"] = aggs;
            
            results ~= result;
        }
        return results;
    }
    
    /// Clear results
    void clear() {
        _groups.clear();
    }
}
