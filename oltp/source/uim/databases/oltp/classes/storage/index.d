module uim.databases.oltp.storage.index;

import std.algorithm;
import std.array;

/// Simple index structure for fast lookups
class Index {
    private {
        string _columnName;
        string[][string] _index; // value -> [rowIds]
    }
    
    this(string columnName) {
        _columnName = columnName;
    }
    
    /// Get column name
    @property string columnName() {
        return _columnName;
    }
    
    /// Add entry to index
    void add(string value, string rowId) {
        if (value !in _index) {
            _index[value] = [];
        }
        _index[value] ~= rowId;
    }
    
    /// Remove entry from index
    void remove(string value, string rowId) {
        if (value in _index) {
            _index[value] = _index[value].filter!(id => id != rowId).array;
            if (_index[value].length == 0) {
                _index.remove(value);
            }
        }
    }
    
    /// Find row IDs by value
    string[] find(string value) {
        if (auto ids = value in _index) {
            return (*ids).dup;
        }
        return [];
    }
    
    /// Get all indexed values
    string[] getValues() {
        return _index.keys;
    }
    
    /// Get index size
    @property size_t size() {
        return _index.length;
    }
    
    /// Clear index
    void clear() {
        _index.clear();
    }
}
