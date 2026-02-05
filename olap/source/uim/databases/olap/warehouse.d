module uim.databases.olap.warehouse;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import vibe.data.json;
import vibe.core.log;
import uim.databases.olap.storage;
import uim.databases.olap.cube;
import uim.databases.olap.aggregation;

/// Data Warehouse for OLAP operations
class DataWarehouse {
    private {
        string _name;
        OLAPCube[string] _cubes;
        AggregationEngine[string] _engines;
        ReadWriteMutex _mutex;
    }
    
    this(string name) {
        _name = name;
        _mutex = new ReadWriteMutex();
        logInfo("Data Warehouse '%s' initialized", _name);
    }
    
    /// Get warehouse name
    @property string name() {
        return _name;
    }
    
    /// Create a new OLAP cube
    void createCube(string cubeName, string[] measures, string[] dimensionKeys) {
        synchronized(_mutex.writer) {
            if (cubeName in _cubes) {
                throw new Exception("Cube already exists: " ~ cubeName);
            }
            
            // Create fact table
            auto factTable = new FactTable(cubeName ~ "_fact", measures, dimensionKeys);
            
            // Add measure columns
            foreach (measure; measures) {
                factTable.addColumn(measure, ColumnType.float_);
            }
            
            // Add dimension key columns
            foreach (dimKey; dimensionKeys) {
                factTable.addColumn(dimKey, ColumnType.string_);
            }
            
            // Create cube
            auto cube = new OLAPCube(cubeName, factTable);
            
            // Add default measures
            foreach (measure; measures) {
                cube.addMeasure(new Measure(measure, measure, AggregationType.sum));
            }
            
            _cubes[cubeName] = cube;
            _engines[cubeName] = new AggregationEngine(cube);
            
            logInfo("Created cube: %s", cubeName);
        }
    }
    
    /// Add dimension to cube
    void addDimension(string cubeName, string dimensionName, string[] attributes, string primaryKey = "id") {
        synchronized(_mutex.writer) {
            auto cube = getCube(cubeName);
            
            // Create dimension table
            auto dimTable = new DimensionTable(dimensionName, primaryKey, attributes);
            
            // Add primary key column
            dimTable.addColumn(primaryKey, ColumnType.string_);
            
            // Add attribute columns
            foreach (attr; attributes) {
                dimTable.addColumn(attr, ColumnType.string_);
            }
            
            // Create dimension
            auto dimension = new Dimension(dimensionName, attributes);
            
            // Add to cube
            cube.addDimension(dimension, dimTable);
            
            logInfo("Added dimension %s to cube %s", dimensionName, cubeName);
        }
    }
    
    /// Load fact data
    void loadFactData(string cubeName, Json[] data) {
        synchronized(_mutex.writer) {
            auto cube = getCube(cubeName);
            cube.factTable.insertRows(data);
            logInfo("Loaded %d fact rows into cube %s", data.length, cubeName);
        }
    }
    
    /// Load dimension data
    void loadDimensionData(string cubeName, string dimensionName, Json[] data) {
        synchronized(_mutex.writer) {
            auto cube = getCube(cubeName);
            auto dimTable = cube.getDimensionTable(dimensionName);
            dimTable.insertRows(data);
            logInfo("Loaded %d dimension rows into %s.%s", data.length, cubeName, dimensionName);
        }
    }
    
    /// Get cube
    OLAPCube getCube(string cubeName) {
        synchronized(_mutex.reader) {
            if (auto cube = cubeName in _cubes) {
                return *cube;
            }
            throw new Exception("Cube not found: " ~ cubeName);
        }
    }
    
    /// Check if cube exists
    bool hasCube(string cubeName) {
        synchronized(_mutex.reader) {
            return (cubeName in _cubes) !is null;
        }
    }
    
    /// Get all cube names
    string[] getCubeNames() {
        synchronized(_mutex.reader) {
            return _cubes.keys;
        }
    }
    
    /// Delete cube
    void deleteCube(string cubeName) {
        synchronized(_mutex.writer) {
            _cubes.remove(cubeName);
            _engines.remove(cubeName);
            logInfo("Deleted cube: %s", cubeName);
        }
    }
    
    /// Aggregate query
    Json aggregate(string cubeName, string[] dimensions, string[] measures, Json filters = Json.emptyObject) {
        auto engine = getEngine(cubeName);
        return engine.aggregate(dimensions, measures, filters);
    }
    
    /// Slice operation
    Json slice(string cubeName, string dimension, string value, string[] measures) {
        auto engine = getEngine(cubeName);
        return engine.slice(dimension, value, measures);
    }
    
    /// Dice operation
    Json dice(string cubeName, Json filters, string[] dimensions, string[] measures) {
        auto engine = getEngine(cubeName);
        return engine.dice(filters, dimensions, measures);
    }
    
    /// Pivot operation
    Json pivot(string cubeName, string[] rowDimensions, string[] columnDimensions, string[] measures, Json filters = Json.emptyObject) {
        auto engine = getEngine(cubeName);
        return engine.pivot(rowDimensions, columnDimensions, measures, filters);
    }
    
    /// Drill down
    Json drillDown(string cubeName, string dimensionName, string hierarchyName, int toLevel, Json filters = Json.emptyObject) {
        auto engine = getEngine(cubeName);
        return engine.drillDown(dimensionName, hierarchyName, toLevel, filters);
    }
    
    /// Roll up
    Json rollUp(string cubeName, string dimensionName, string hierarchyName, int toLevel, Json filters = Json.emptyObject) {
        auto engine = getEngine(cubeName);
        return engine.rollUp(dimensionName, hierarchyName, toLevel, filters);
    }
    
    /// Get warehouse statistics
    Json getStatistics() {
        synchronized(_mutex.reader) {
            auto stats = Json.emptyObject;
            stats["name"] = _name;
            stats["cubeCount"] = _cubes.length;
            
            auto cubeStats = Json.emptyArray;
            foreach (cube; _cubes.values) {
                cubeStats ~= cube.getStatistics();
            }
            stats["cubes"] = cubeStats;
            
            return stats;
        }
    }
    
    private AggregationEngine getEngine(string cubeName) {
        synchronized(_mutex.reader) {
            if (auto engine = cubeName in _engines) {
                return *engine;
            }
            throw new Exception("Cube not found: " ~ cubeName);
        }
    }
}
