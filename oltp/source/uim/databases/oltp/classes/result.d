module uim.databases.oltp.classes.result;

import std.variant;
import vibe.data.json;

/// Query result wrapper
class QueryResult {
    private {
        Json _data;
        size_t _rowCount;
        size_t _affectedRows;
        bool _success;
        string _error;
    }
    
    this() {
        _data = Json.emptyArray;
        _rowCount = 0;
        _affectedRows = 0;
        _success = true;
        _error = "";
    }
    
    /// Set result data
    void setData(Json data) {
        _data = data;
        if (_data.type == Json.Type.array) {
            _rowCount = _data.length;
        }
    }
    
    /// Get result data
    @property Json data() {
        return _data;
    }
    
    /// Get number of rows returned
    @property size_t rowCount() {
        return _rowCount;
    }
    
    /// Set number of affected rows (for INSERT/UPDATE/DELETE)
    @property void affectedRows(size_t count) {
        _affectedRows = count;
    }
    
    /// Get number of affected rows
    @property size_t affectedRows() {
        return _affectedRows;
    }
    
    /// Set success status
    @property void success(bool status) {
        _success = status;
    }
    
    /// Check if query was successful
    @property bool success() {
        return _success;
    }
    
    /// Set error message
    @property void error(string msg) {
        _error = msg;
        _success = false;
    }
    
    /// Get error message
    @property string error() {
        return _error;
    }
    
    /// Get first row
    Json firstRow() {
        if (_rowCount > 0) {
            return _data[0];
        }
        return Json(null);
    }
    
    /// Iterate over rows
    int opApply(int delegate(Json) dg) {
        if (_data.type != Json.Type.array) {
            return 0;
        }
        
        foreach (row; _data) {
            int result = dg(row);
            if (result) {
                return result;
            }
        }
        return 0;
    }
}
