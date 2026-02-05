module uim.databases.olap.storage.column;

import std.variant;
import std.algorithm;
import std.array;
import std.conv;
import vibe.data.json;

/// Column data types
enum ColumnType {
    integer,
    float_,
    string_,
    date,
    boolean
}

/// Columnar storage for a single column
class Column {
    private {
        string _name;
        ColumnType _type;
        Variant[] _data;
        bool[] _nulls;
        size_t _rowCount;
    }
    
    this(string name, ColumnType type) {
        _name = name;
        _type = type;
        _rowCount = 0;
    }
    
    /// Get column name
    @property string name() {
        return _name;
    }
    
    /// Get column type
    @property ColumnType type() {
        return _type;
    }
    
    /// Get row count
    @property size_t rowCount() {
        return _rowCount;
    }
    
    /// Append a value
    void append(Variant value) {
        _data ~= value;
        _nulls ~= false;
        _rowCount++;
    }
    
    /// Append a null value
    void appendNull() {
        _data ~= Variant(null);
        _nulls ~= true;
        _rowCount++;
    }
    
    /// Get value at index
    Variant get(size_t index) {
        if (index >= _rowCount) {
            throw new Exception("Index out of bounds");
        }
        return _data[index];
    }
    
    /// Check if value at index is null
    bool isNull(size_t index) {
        if (index >= _rowCount) {
            throw new Exception("Index out of bounds");
        }
        return _nulls[index];
    }
    
    /// Get all values
    Variant[] getAllValues() {
        return _data.dup;
    }
    
    /// Calculate sum (for numeric columns)
    double sum() {
        double result = 0;
        foreach (i, val; _data) {
            if (!_nulls[i]) {
                if (_type == ColumnType.integer) {
                    result += val.get!long;
                } else if (_type == ColumnType.float_) {
                    result += val.get!double;
                }
            }
        }
        return result;
    }
    
    /// Calculate average (for numeric columns)
    double avg() {
        if (_rowCount == 0) return 0;
        return sum() / _rowCount;
    }
    
    /// Calculate minimum
    Variant min() {
        if (_rowCount == 0) return Variant(null);
        
        Variant minVal = _data[0];
        foreach (i, val; _data) {
            if (!_nulls[i]) {
                if (_type == ColumnType.integer) {
                    if (val.get!long < minVal.get!long) minVal = val;
                } else if (_type == ColumnType.float_) {
                    if (val.get!double < minVal.get!double) minVal = val;
                }
            }
        }
        return minVal;
    }
    
    /// Calculate maximum
    Variant max() {
        if (_rowCount == 0) return Variant(null);
        
        Variant maxVal = _data[0];
        foreach (i, val; _data) {
            if (!_nulls[i]) {
                if (_type == ColumnType.integer) {
                    if (val.get!long > maxVal.get!long) maxVal = val;
                } else if (_type == ColumnType.float_) {
                    if (val.get!double > maxVal.get!double) maxVal = val;
                }
            }
        }
        return maxVal;
    }
    
    /// Count non-null values
    size_t count() {
        size_t cnt = 0;
        foreach (isNull; _nulls) {
            if (!isNull) cnt++;
        }
        return cnt;
    }
    
    /// Get distinct values
    Variant[] distinct() {
        bool[string] seen;
        Variant[] result;
        
        foreach (i, val; _data) {
            if (!_nulls[i]) {
                string key = val.toString();
                if (key !in seen) {
                    seen[key] = true;
                    result ~= val;
                }
            }
        }
        return result;
    }
    
    /// Filter by predicate
    size_t[] filter(bool delegate(Variant) pred) {
        size_t[] indices;
        foreach (i, val; _data) {
            if (!_nulls[i] && pred(val)) {
                indices ~= i;
            }
        }
        return indices;
    }
    
    /// Compress column data (simple run-length encoding for repeated values)
    void compress() {
        // TODO: Implement compression
    }
    
    /// Get memory usage estimate
    size_t memoryUsage() {
        return _data.length * Variant.sizeof + _nulls.length * bool.sizeof;
    }
}
