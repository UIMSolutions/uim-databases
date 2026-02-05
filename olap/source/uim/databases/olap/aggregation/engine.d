module uim.databases.olap.aggregation.engine;

import std.algorithm;
import std.array;
import std.variant;
import vibe.data.json;
import vibe.core.log;
import uim.databases.olap.cube.olapcube;
import uim.databases.olap.cube.measure;
import uim.databases.olap.storage.column;
import uim.databases.olap.aggregation.groupby;

/// Aggregation engine for OLAP queries
class AggregationEngine {
    private {
        OLAPCube _cube;
    }
    
    this(OLAPCube cube) {
        _cube = cube;
    }
    
    /// Perform aggregation query
    Json aggregate(string[] dimensions, string[] measures, Json filters = Json.emptyObject) {
        auto factTable = _cube.factTable;
        auto groupBy = new GroupBy(dimensions);
        
        logInfo("Aggregating: dimensions=%s, measures=%s", dimensions, measures);
        
        // Iterate through fact table rows
        for (size_t i = 0; i < factTable.rowCount; i++) {
            auto row = factTable.getRow(i);
            
            // Apply filters
            if (!matchesFilters(row, filters)) {
                continue;
            }
            
            // Build group key
            auto key = Json.emptyObject;
            foreach (dim; dimensions) {
                if (dim in row) {
                    key[dim] = row[dim];
                }
            }
            
            // Calculate measures
            foreach (measureName; measures) {
                auto measure = _cube.getMeasure(measureName);
                double value = extractValue(row, measure.column);
                
                final switch (measure.aggregation) {
                    case AggregationType.sum:
                        groupBy.add(key, measureName, value);
                        break;
                    case AggregationType.avg:
                        groupBy.add(key, measureName, value);
                        break;
                    case AggregationType.count:
                        groupBy.add(key, measureName, 1);
                        break;
                    case AggregationType.min:
                        // TODO: Implement proper min/max
                        groupBy.add(key, measureName, value);
                        break;
                    case AggregationType.max:
                        groupBy.add(key, measureName, value);
                        break;
                    case AggregationType.countDistinct:
                        groupBy.add(key, measureName, 1);
                        break;
                }
            }
        }
        
        // Post-process for averages
        auto results = groupBy.getResults();
        foreach (ref result; results) {
            foreach (measureName; measures) {
                auto measure = _cube.getMeasure(measureName);
                if (measure.aggregation == AggregationType.avg && result.count > 0) {
                    result.aggregates[measureName] /= result.count;
                }
            }
        }
        
        // Convert to JSON
        auto response = Json.emptyObject;
        response["dimensions"] = serializeToJson(dimensions);
        response["measures"] = serializeToJson(measures);
        response["resultCount"] = results.length;
        
        auto data = Json.emptyArray;
        foreach (result; results) {
            auto item = result.key.clone();
            item["_count"] = result.count;
            
            foreach (name, value; result.aggregates) {
                item[name] = value;
            }
            data ~= item;
        }
        response["data"] = data;
        
        return response;
    }
    
    /// Drill down in hierarchy
    Json drillDown(string dimensionName, string hierarchyName, int toLevel, Json filters = Json.emptyObject) {
        // TODO: Implement drill-down
        auto response = Json.emptyObject;
        response["dimension"] = dimensionName;
        response["hierarchy"] = hierarchyName;
        response["level"] = toLevel;
        return response;
    }
    
    /// Roll up in hierarchy
    Json rollUp(string dimensionName, string hierarchyName, int toLevel, Json filters = Json.emptyObject) {
        // TODO: Implement roll-up
        auto response = Json.emptyObject;
        response["dimension"] = dimensionName;
        response["hierarchy"] = hierarchyName;
        response["level"] = toLevel;
        return response;
    }
    
    /// Slice cube (fix one dimension)
    Json slice(string dimensionName, string value, string[] measures) {
        auto filters = Json.emptyObject;
        filters[dimensionName] = value;
        
        auto allDimensions = _cube.getDimensionNames();
        auto otherDimensions = allDimensions.filter!(d => d != dimensionName).array;
        
        return aggregate(otherDimensions, measures, filters);
    }
    
    /// Dice cube (filter multiple dimensions)
    Json dice(Json filters, string[] dimensions, string[] measures) {
        return aggregate(dimensions, measures, filters);
    }
    
    /// Pivot table
    Json pivot(string[] rowDimensions, string[] columnDimensions, string[] measures, Json filters = Json.emptyObject) {
        // Aggregate by all dimensions
        auto allDimensions = rowDimensions ~ columnDimensions;
        auto aggResult = aggregate(allDimensions, measures, filters);
        
        // Restructure into pivot format
        auto response = Json.emptyObject;
        response["rowDimensions"] = serializeToJson(rowDimensions);
        response["columnDimensions"] = serializeToJson(columnDimensions);
        response["measures"] = serializeToJson(measures);
        response["data"] = aggResult["data"];
        
        return response;
    }
    
    private bool matchesFilters(Json row, Json filters) {
        if (filters.type != Json.Type.object) {
            return true;
        }
        
        foreach (string key, value; filters) {
            if (key !in row) {
                return false;
            }
            if (row[key] != value) {
                return false;
            }
        }
        
        return true;
    }
    
    private double extractValue(Json row, string column) {
        if (column !in row || row[column].type == Json.Type.null_) {
            return 0.0;
        }
        
        auto val = row[column];
        if (val.type == Json.Type.int_) {
            return val.get!long.to!double;
        } else if (val.type == Json.Type.float_) {
            return val.get!double;
        }
        
        return 0.0;
    }
}

import std.conv : to;
