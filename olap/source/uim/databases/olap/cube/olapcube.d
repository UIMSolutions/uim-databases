module uim.databases.olap.cube.olapcube;

import std.algorithm;
import std.array;
import vibe.data.json;
import vibe.core.log;
import uim.databases.olap.cube.dimension;
import uim.databases.olap.cube.measure;
import uim.databases.olap.cube.hierarchy;
import uim.databases.olap.storage.fact;
import uim.databases.olap.storage.dimension;

/// OLAP Cube for multidimensional analysis
class OLAPCube {
    private {
        string _name;
        FactTable _factTable;
        DimensionTable[string] _dimensionTables;
        Dimension[string] _dimensions;
        Measure[string] _measures;
        Hierarchy[string] _hierarchies;
    }
    
    this(string name, FactTable factTable) {
        _name = name;
        _factTable = factTable;
    }
    
    /// Get cube name
    @property string name() {
        return _name;
    }
    
    /// Get fact table
    @property FactTable factTable() {
        return _factTable;
    }
    
    /// Add dimension
    void addDimension(Dimension dimension, DimensionTable table) {
        _dimensions[dimension.name] = dimension;
        _dimensionTables[dimension.name] = table;
        logInfo("Added dimension %s to cube %s", dimension.name, _name);
    }
    
    /// Add measure
    void addMeasure(Measure measure) {
        _measures[measure.name] = measure;
        logInfo("Added measure %s to cube %s", measure.name, _name);
    }
    
    /// Add hierarchy
    void addHierarchy(string dimensionName, Hierarchy hierarchy) {
        _hierarchies[dimensionName ~ ":" ~ hierarchy.name] = hierarchy;
        logInfo("Added hierarchy %s for dimension %s", hierarchy.name, dimensionName);
    }
    
    /// Get dimension
    Dimension getDimension(string name) {
        if (auto dim = name in _dimensions) {
            return *dim;
        }
        throw new Exception("Dimension not found: " ~ name);
    }
    
    /// Get dimension table
    DimensionTable getDimensionTable(string name) {
        if (auto table = name in _dimensionTables) {
            return *table;
        }
        throw new Exception("Dimension table not found: " ~ name);
    }
    
    /// Get measure
    Measure getMeasure(string name) {
        if (auto measure = name in _measures) {
            return *measure;
        }
        throw new Exception("Measure not found: " ~ name);
    }
    
    /// Get all dimensions
    string[] getDimensionNames() {
        return _dimensions.keys;
    }
    
    /// Get all measures
    string[] getMeasureNames() {
        return _measures.keys;
    }
    
    /// Get cube metadata
    Json getMetadata() {
        auto metadata = Json.emptyObject;
        metadata["name"] = _name;
        metadata["factTable"] = _factTable.name;
        
        auto dims = Json.emptyArray;
        foreach (dim; _dimensions.values) {
            dims ~= dim.toJson();
        }
        metadata["dimensions"] = dims;
        
        auto meas = Json.emptyArray;
        foreach (measure; _measures.values) {
            meas ~= measure.toJson();
        }
        metadata["measures"] = meas;
        
        auto hierJson = Json.emptyArray;
        foreach (hier; _hierarchies.values) {
            hierJson ~= hier.toJson();
        }
        metadata["hierarchies"] = hierJson;
        
        return metadata;
    }
    
    /// Get cube statistics
    Json getStatistics() {
        auto stats = Json.emptyObject;
        stats["name"] = _name;
        stats["dimensionCount"] = _dimensions.length;
        stats["measureCount"] = _measures.length;
        stats["factRowCount"] = _factTable.rowCount;
        
        auto dimStats = Json.emptyObject;
        foreach (name, table; _dimensionTables) {
            dimStats[name] = table.rowCount;
        }
        stats["dimensionRowCounts"] = dimStats;
        
        return stats;
    }
}
