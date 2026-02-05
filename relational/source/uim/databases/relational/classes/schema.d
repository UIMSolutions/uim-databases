/// Table schema
class Schema {
    string tableName;
    Column[] columns;
    string primaryKeyColumn;
    string[][string] foreignKeys;  // column -> [refTable, refColumn]
    string[][string] uniqueConstraints;  // constraint_name -> [columns]
    
    this(string tableName) {
        this.tableName = tableName;
    }
    
    /// Add a column to the schema
    void addColumn(Column column) {
        columns ~= column;
        if (column.primaryKey) {
            primaryKeyColumn = column.name;
        }
    }
    
    /// Add a foreign key constraint
    void addForeignKey(string column, string refTable, string refColumn) {
        foreignKeys[column] = [refTable, refColumn];
    }
    
    /// Get column by name
    Column* getColumn(string name) {
        foreach (ref col; columns) {
            if (col.name == name) return &col;
        }
        return null;
    }
    
    /// Validate a row against the schema
    void validateRow(Json row) {
        foreach (col; columns) {
            if (col.name !in row) {
                if (!col.nullable && col.defaultValue.type == Json.Type.undefined) {
                    throw new Exception("Column '" ~ col.name ~ "' cannot be null");
                }
                continue;
            }
            
            auto value = row[col.name];
            if (value.type == Json.Type.null_ && !col.nullable) {
                throw new Exception("Column '" ~ col.name ~ "' cannot be null");
            }
            
            // Type validation
            if (value.type != Json.Type.null_) {
                validateType(value, col.type, col.name);
            }
        }
    }
    
    private void validateType(Json value, ColumnType expectedType, string colName) {
        bool valid = false;
        
        final switch (expectedType) {
            case ColumnType.INTEGER:
                valid = value.type == Json.Type.int_;
                break;
            case ColumnType.FLOAT:
                valid = value.type == Json.Type.float_ || value.type == Json.Type.int_;
                break;
            case ColumnType.STRING:
                valid = value.type == Json.Type.string;
                break;
            case ColumnType.BOOLEAN:
                valid = value.type == Json.Type.bool_;
                break;
            case ColumnType.DATE:
                valid = value.type == Json.Type.string;  // ISO date string
                break;
            case ColumnType.JSON:
                valid = true;  // Any JSON type
                break;
        }
        
        if (!valid) {
            throw new Exception("Column '" ~ colName ~ "' type mismatch");
        }
    }
    
    /// Get schema as JSON
    Json toJson() {
        auto schemaJson = Json.emptyObject;
        schemaJson["tableName"] = tableName;
        schemaJson["primaryKey"] = primaryKeyColumn;
        
        Json[] colsJson;
        foreach (col; columns) {
            auto colJson = Json.emptyObject;
            colJson["name"] = col.name;
            colJson["type"] = to!string(col.type);
            colJson["nullable"] = col.nullable;
            colJson["primaryKey"] = col.primaryKey;
            colJson["unique"] = col.unique;
            colsJson ~= colJson;
        }
        schemaJson["columns"] = serializeToJson(colsJson);
        
        return schemaJson;
    }
}