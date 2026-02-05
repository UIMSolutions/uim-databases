module uim.databases.olap.storage.fact;

import vibe.data.json;
import uim.databases.olap.storage.columnar;
import uim.databases.olap.storage.column;

/// Fact table in a star schema
class FactTable : ColumnarTable {
    private {
        string[] _measures;
        string[] _dimensionKeys;
    }
    
    this(string name, string[] measures, string[] dimensionKeys) {
        super(name);
        _measures = measures.dup;
        _dimensionKeys = dimensionKeys.dup;
    }
    
    /// Get measure columns
    @property string[] measures() {
        return _measures.dup;
    }
    
    /// Get dimension key columns
    @property string[] dimensionKeys() {
        return _dimensionKeys.dup;
    }
    
    /// Check if column is a measure
    bool isMeasure(string columnName) {
        import std.algorithm : canFind;
        return _measures.canFind(columnName);
    }
    
    /// Check if column is a dimension key
    bool isDimensionKey(string columnName) {
        import std.algorithm : canFind;
        return _dimensionKeys.canFind(columnName);
    }
}
