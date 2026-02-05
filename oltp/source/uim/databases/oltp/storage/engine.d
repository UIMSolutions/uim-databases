module uim.databases.oltp.storage.engine;

import core.sync.rwmutex;
import std.file;
import std.path;
import std.algorithm;
import std.array;
import vibe.data.json;
import vibe.core.log;
import uim.databases.oltp.storage.table;
import uim.databases.oltp.storage.row;

/// Main storage engine managing tables and persistence
class StorageEngine {
    private {
        Table[string] _tables;
        ReadWriteMutex _mutex;
        string _dataDirectory;
        bool _persistenceEnabled;
    }
    
    this(string dataDirectory = "./data", bool enablePersistence = true) {
        _dataDirectory = dataDirectory;
        _persistenceEnabled = enablePersistence;
        _mutex = new ReadWriteMutex();
        
        if (_persistenceEnabled) {
            ensureDataDirectory();
            loadTables();
        }
    }
    
    private void ensureDataDirectory() {
        if (!exists(_dataDirectory)) {
            mkdirRecurse(_dataDirectory);
            logInfo("Created data directory: %s", _dataDirectory);
        }
    }
    
    private void loadTables() {
        // TODO: Implement loading tables from disk
        logInfo("Storage engine initialized with persistence at %s", _dataDirectory);
    }
    
    /// Create a new table
    void createTable(string tableName, string[] columns = []) {
        synchronized(_mutex.writer) {
            if (tableName in _tables) {
                throw new Exception("Table already exists: " ~ tableName);
            }
            
            _tables[tableName] = new Table(tableName, columns);
            logInfo("Created table: %s", tableName);
            
            if (_persistenceEnabled) {
                persistTableMetadata(tableName);
            }
        }
    }
    
    /// Drop a table
    void dropTable(string tableName) {
        synchronized(_mutex.writer) {
            if (tableName !in _tables) {
                throw new Exception("Table does not exist: " ~ tableName);
            }
            
            _tables.remove(tableName);
            logInfo("Dropped table: %s", tableName);
            
            if (_persistenceEnabled) {
                removeTableData(tableName);
            }
        }
    }
    
    /// Get table by name
    Table getTable(string tableName) {
        synchronized(_mutex.reader) {
            if (auto table = tableName in _tables) {
                return *table;
            }
            throw new Exception("Table does not exist: " ~ tableName);
        }
    }
    
    /// Check if table exists
    bool hasTable(string tableName) {
        synchronized(_mutex.reader) {
            return (tableName in _tables) !is null;
        }
    }
    
    /// Get all table names
    string[] getTableNames() {
        synchronized(_mutex.reader) {
            return _tables.keys;
        }
    }
    
    /// Insert row into table
    string insert(string tableName, Json data) {
        auto table = getTable(tableName);
        auto rowId = table.insert(data);
        
        if (_persistenceEnabled) {
            persistRow(tableName, rowId, data);
        }
        
        return rowId;
    }
    
    /// Update row in table
    bool update(string tableName, string rowId, Json data) {
        auto table = getTable(tableName);
        auto success = table.update(rowId, data);
        
        if (success && _persistenceEnabled) {
            persistRow(tableName, rowId, data);
        }
        
        return success;
    }
    
    /// Delete row from table
    bool deleteRow(string tableName, string rowId) {
        auto table = getTable(tableName);
        auto success = table.deleteById(rowId);
        
        if (success && _persistenceEnabled) {
            markRowDeleted(tableName, rowId);
        }
        
        return success;
    }
    
    /// Get row by ID
    Row getRow(string tableName, string rowId) {
        auto table = getTable(tableName);
        return table.getById(rowId);
    }
    
    /// Query rows from table
    Row[] query(string tableName, string columnName = "", string value = "") {
        auto table = getTable(tableName);
        
        if (columnName.length > 0 && value.length > 0) {
            return table.findByColumn(columnName, value);
        }
        
        return table.getAllRows();
    }
    
    /// Get database statistics
    Json getStatistics() {
        synchronized(_mutex.reader) {
            auto stats = Json.emptyObject;
            stats["tableCount"] = _tables.length;
            stats["dataDirectory"] = _dataDirectory;
            stats["persistenceEnabled"] = _persistenceEnabled;
            
            auto tableStats = Json.emptyArray;
            foreach (table; _tables.values) {
                tableStats ~= table.getStatistics();
            }
            stats["tables"] = tableStats;
            
            return stats;
        }
    }
    
    private void persistTableMetadata(string tableName) {
        // TODO: Implement table metadata persistence
    }
    
    private void removeTableData(string tableName) {
        // TODO: Implement table data removal
    }
    
    private void persistRow(string tableName, string rowId, Json data) {
        // TODO: Implement row persistence
    }
    
    private void markRowDeleted(string tableName, string rowId) {
        // TODO: Implement deleted row marking
    }
    
    /// Checkpoint - flush all data to disk
    void checkpoint() {
        if (!_persistenceEnabled) {
            return;
        }
        
        synchronized(_mutex.reader) {
            logInfo("Starting checkpoint...");
            // TODO: Implement full checkpoint
            logInfo("Checkpoint completed");
        }
    }
}
