module uim.databases.olap.storage.columnar;

import std.algorithm;
import std.array;
import std.variant;
import vibe.data.json;
import vibe.core.log;
import uim.databases.olap.storage.column;

/// Columnar table storage for OLAP
class ColumnarTable {
    private {
        string _name;
        Column[string] _columns;
        string[] _columnOrder;
        size_t _rowCount;
    }
    
    this(string name) {
        _name = name;
        _rowCount = 0;
    }
    
    /// Get table name
    @property string name() {
        return _name;
    }
    
    /// Get row count
    @property size_t rowCount() {
        return _rowCount;
    }
    
    /// Add a column
    void addColumn(string name, ColumnType type) {
        if (name in _columns) {
            throw new Exception("Column already exists: " ~ name);
        }
        
        auto col = new Column(name, type);
        
        // Fill with nulls if table already has rows
        for (size_t i = 0; i < _rowCount; i++) {
            col.appendNull();
        }
        
        _columns[name] = col;
        _columnOrder ~= name;
        
        logInfo("Added column %s to table %s", name, _name);
    }
    
    /// Get column
    Column getColumn(string name) {
        if (auto col = name in _columns) {
            return *col;
        }
        throw new Exception("Column not found: " ~ name);
    }
    
    /// Check if column exists
    bool hasColumn(string name) {
        return (name in _columns) !is null;
    }
    
    /// Get all column names
    string[] getColumnNames() {
        return _columnOrder.dup;
    }
    
    /// Insert a row
    void insertRow(Json data) {
        foreach (colName; _columnOrder) {
            auto col = _columns[colName];
            
            if (colName in data && data[colName].type != Json.Type.null_) {
                auto jsonVal = data[colName];
                
                final switch (col.type) {
                    case ColumnType.integer:
                        col.append(Variant(jsonVal.get!long));
                        break;
                    case ColumnType.float_:
                        col.append(Variant(jsonVal.get!double));
                        break;
                    case ColumnType.string_:
                        col.append(Variant(jsonVal.get!string));
                        break;
                    case ColumnType.date:
                        col.append(Variant(jsonVal.get!string));
                        break;
                    case ColumnType.boolean:
                        col.append(Variant(jsonVal.get!bool));
                        break;
                }
            } else {
                col.appendNull();
            }
        }
        
        _rowCount++;
    }
    
    /// Batch insert rows
    void insertRows(Json[] rows) {
        foreach (row; rows) {
            insertRow(row);
        }
        logInfo("Inserted %d rows into table %s", rows.length, _name);
    }
    
    /// Get row at index
    Json getRow(size_t index) {
        if (index >= _rowCount) {
            throw new Exception("Row index out of bounds");
        }
        
        auto result = Json.emptyObject;
        foreach (colName; _columnOrder) {
            auto col = _columns[colName];
            if (!col.isNull(index)) {
                auto val = col.get(index);
                
                final switch (col.type) {
                    case ColumnType.integer:
                        result[colName] = val.get!long;
                        break;
                    case ColumnType.float_:
                        result[colName] = val.get!double;
                        break;
                    case ColumnType.string_:
                        result[colName] = val.get!string;
                        break;
                    case ColumnType.date:
                        result[colName] = val.get!string;
                        break;
                    case ColumnType.boolean:
                        result[colName] = val.get!bool;
                        break;
                }
            } else {
                result[colName] = Json(null);
            }
        }
        
        return result;
    }
    
    /// Get all rows
    Json[] getAllRows() {
        Json[] results;
        for (size_t i = 0; i < _rowCount; i++) {
            results ~= getRow(i);
        }
        return results;
    }
    
    /// Scan column with filter
    Json[] scan(string columnName, bool delegate(Variant) filter) {
        auto col = getColumn(columnName);
        auto indices = col.filter(filter);
        
        Json[] results;
        foreach (idx; indices) {
            results ~= getRow(idx);
        }
        return results;
    }
    
    /// Get table statistics
    Json getStatistics() {
        auto stats = Json.emptyObject;
        stats["name"] = _name;
        stats["rowCount"] = _rowCount;
        stats["columnCount"] = _columns.length;
        
        auto colStats = Json.emptyArray;
        foreach (colName; _columnOrder) {
            auto col = _columns[colName];
            auto colStat = Json.emptyObject;
            colStat["name"] = colName;
            colStat["type"] = col.type.to!string;
            colStat["count"] = col.count();
            colStat["memoryUsage"] = col.memoryUsage();
            
            if (col.type == ColumnType.integer || col.type == ColumnType.float_) {
                colStat["sum"] = col.sum();
                colStat["avg"] = col.avg();
                colStat["min"] = col.min().toString();
                colStat["max"] = col.max().toString();
            }
            
            colStats ~= colStat;
        }
        stats["columns"] = colStats;
        
        return stats;
    }
    
    /// Get memory usage
    size_t memoryUsage() {
        size_t total = 0;
        foreach (col; _columns.values) {
            total += col.memoryUsage();
        }
        return total;
    }
}

import std.conv : to;
