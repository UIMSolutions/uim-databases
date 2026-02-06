module uim.databases.oltp.storage.table;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import vibe.data.json;
import vibe.core.log;
import uim.databases.oltp.storage.row;
import uim.databases.oltp.storage.index;

/// Table structure with in-memory storage
class Table {
    private {
        string _name;
        Row[string] _rows; // rowId -> Row
        Index[string] _indices; // columnName -> Index
        ReadWriteMutex _mutex;
        string[] _columns;
        size_t _rowCount;
    }
    
    this(string name, string[] columns = []) {
        _name = name;
        _columns = columns.dup;
        _mutex = new ReadWriteMutex();
        _rowCount = 0;
    }
    
    /// Get table name
    @property string name() {
        return _name;
    }
    
    /// Get columns
    @property string[] columns() {
        return _columns;
    }
    
    /// Insert a new row
    string insert(Json data) {
        synchronized(_mutex.writer) {
            auto row = new Row(data);
            _rows[row.id] = row;
            _rowCount++;
            
            // Update indices
            foreach (columnName, index; _indices) {
                if (columnName in data) {
                    index.add(data[columnName].to!string, row.id);
                }
            }
            
            logInfo("Inserted row %s into table %s", row.id, _name);
            return row.id;
        }
    }
    
    /// Get row by ID
    Row getById(string rowId) {
        synchronized(_mutex.reader) {
            if (auto row = rowId in _rows) {
                return row.clone();
            }
            return null;
        }
    }
    
    /// Update row by ID
    bool update(string rowId, Json data) {
        synchronized(_mutex.writer) {
            if (auto row = rowId in _rows) {
                // Remove old index entries
                foreach (columnName, index; _indices) {
                    if (row.has(columnName)) {
                        index.remove(row.get(columnName).to!string, rowId);
                    }
                }
                
                // Update row data
                foreach (string key, value; data) {
                    row.set(key, value);
                }
                
                // Add new index entries
                foreach (columnName, index; _indices) {
                    if (row.has(columnName)) {
                        index.add(row.get(columnName).to!string, rowId);
                    }
                }
                
                logInfo("Updated row %s in table %s", rowId, _name);
                return true;
            }
            return false;
        }
    }
    
    /// Delete row by ID
    bool deleteById(string rowId, string transactionId = "") {
        synchronized(_mutex.writer) {
            if (auto row = rowId in _rows) {
                row.markDeleted(transactionId);
                
                // Remove from indices
                foreach (columnName, index; _indices) {
                    if (row.has(columnName)) {
                        index.remove(row.get(columnName).to!string, rowId);
                    }
                }
                
                _rowCount--;
                logInfo("Deleted row %s from table %s", rowId, _name);
                return true;
            }
            return false;
        }
    }
    
    /// Get all rows (excluding deleted)
    Row[] getAllRows() {
        synchronized(_mutex.reader) {
            return _rows.values
                .filter!(r => !r.isDeleted)
                .map!(r => r.clone())
                .array;
        }
    }
    
    /// Find rows by column value
    Row[] findByColumn(string column, string value) {
        synchronized(_mutex.reader) {
            if (auto index = column in _indices) {
                auto rowIds = index.find(value);
                return rowIds
                    .map!(id => _rows[id])
                    .filter!(r => !r.isDeleted)
                    .map!(r => r.clone())
                    .array;
            }
            
            // Fallback: scan all rows
            return _rows.values
                .filter!(r => !r.isDeleted && r.has(column) && r.get(column).to!string == value)
                .map!(r => r.clone())
                .array;
        }
    }
    
    /// Create index on column
    void createIndex(string columnName) {
        synchronized(_mutex.writer) {
            if (columnName in _indices) {
                logWarn("Index already exists on column %s", columnName);
                return;
            }
            
            auto index = new Index(columnName);
            
            // Build index from existing rows
            foreach (row; _rows.values) {
                if (!row.isDeleted && row.has(columnName)) {
                    index.add(row.get(columnName).to!string, row.id);
                }
            }
            
            _indices[columnName] = index;
            logInfo("Created index on column %s in table %s", columnName, _name);
        }
    }
    
    /// Drop index
    void dropIndex(string columnName) {
        synchronized(_mutex.writer) {
            _indices.remove(columnName);
            logInfo("Dropped index on column %s in table %s", columnName, _name);
        }
    }
    
    /// Get row count
    @property size_t rowCount() {
        synchronized(_mutex.reader) {
            return _rowCount;
        }
    }
    
    /// Get table statistics
    Json getStatistics() {
        synchronized(_mutex.reader) {
            auto stats = Json.emptyObject;
            stats["name"] = _name;
            stats["rowCount"] = _rowCount;
            stats["totalRows"] = _rows.length;
            stats["indices"] = _indices.length;
            stats["columns"] = Json(_columns);
            return stats;
        }
    }
}
