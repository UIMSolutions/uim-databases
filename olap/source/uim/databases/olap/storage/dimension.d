module uim.databases.olap.storage.dimension;

import vibe.data.json;
import uim.databases.olap.storage.columnar;

/// Dimension table in a star schema
class DimensionTable : ColumnarTable {
    private {
        string _primaryKey;
        string[] _attributes;
    }
    
    this(string name, string primaryKey, string[] attributes) {
        super(name);
        _primaryKey = primaryKey;
        _attributes = attributes.dup;
    }
    
    /// Get primary key column name
    @property string primaryKey() {
        return _primaryKey;
    }
    
    /// Get attribute columns
    @property string[] attributes() {
        return _attributes.dup;
    }
    
    /// Lookup by primary key value
    Json lookup(string keyValue) {
        auto pkCol = getColumn(_primaryKey);
        
        // Find matching row
        for (size_t i = 0; i < pkCol.rowCount; i++) {
            if (!pkCol.isNull(i)) {
                auto val = pkCol.get(i);
                if (val.toString() == keyValue) {
                    return getRow(i);
                }
            }
        }
        
        return Json(null);
    }
}
