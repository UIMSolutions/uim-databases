module relationaldb;

import std.datetime;
import std.algorithm;
import std.array;
import std.range;
import std.exception;
import std.conv;
import std.string;
import vibe.data.json;

/// Column data types
enum ColumnType {
    INTEGER,
    FLOAT,
    STRING,
    BOOLEAN,
    DATE,
    JSON
}






/// Query result for SELECT
struct QueryResult {
    Json[] rows;
    string[] columns;
    size_t rowCount;
}



/// Relational Database
class RelationalDatabase {
    string name;
    Table[string] tables;
    
    this(string name = "default") {
        this.name = name;
    }
    
    /// Create a table
    void createTable(Schema schema) {
        if (schema.tableName in tables) {
            throw new Exception("Table '" ~ schema.tableName ~ "' already exists");
        }
        tables[schema.tableName] = new Table(schema.tableName, schema);
    }
    
    /// Drop a table
    void dropTable(string tableName) {
        tables.remove(tableName);
    }
    
    /// Get a table
    Table getTable(string tableName) {
        auto ptr = tableName in tables;
        if (ptr is null) {
            throw new Exception("Table '" ~ tableName ~ "' not found");
        }
        return *ptr;
    }
    
    /// Check if table exists
    bool hasTable(string tableName) {
        return (tableName in tables) !is null;
    }
    
    /// List all tables
    string[] listTables() {
        return tables.keys.dup;
    }
    
    /// Perform an INNER JOIN between two tables
    QueryResult join(string leftTable, string rightTable, 
                    string leftColumn, string rightColumn,
                    WhereCondition[] leftConditions = [],
                    WhereCondition[] rightConditions = []) {
        auto left = getTable(leftTable);
        auto right = getTable(rightTable);
        
        Json[] results;
        
        foreach (leftRow; left.rows) {
            // Check left conditions
            bool leftMatch = true;
            foreach (cond; leftConditions) {
                if (!cond.matches(leftRow.data)) {
                    leftMatch = false;
                    break;
                }
            }
            if (!leftMatch) continue;
            
            if (leftColumn !in leftRow.data) continue;
            auto leftValue = leftRow.data[leftColumn];
            
            foreach (rightRow; right.rows) {
                // Check right conditions
                bool rightMatch = true;
                foreach (cond; rightConditions) {
                    if (!cond.matches(rightRow.data)) {
                        rightMatch = false;
                        break;
                    }
                }
                if (!rightMatch) continue;
                
                if (rightColumn !in rightRow.data) continue;
                auto rightValue = rightRow.data[rightColumn];
                
                // Check join condition
                if (jsonEquals(leftValue, rightValue)) {
                    Json joined = Json.emptyObject;
                    
                    // Add left table columns with prefix
                    foreach (string key, value; leftRow.data) {
                        joined[leftTable ~ "." ~ key] = value;
                    }
                    
                    // Add right table columns with prefix
                    foreach (string key, value; rightRow.data) {
                        joined[rightTable ~ "." ~ key] = value;
                    }
                    
                    results ~= joined;
                }
            }
        }
        
        return QueryResult(results, [], results.length);
    }
    
    /// Get database statistics
    Json getStats() {
        auto stats = Json.emptyObject;
        stats["name"] = name;
        stats["tableCount"] = tables.length;
        
        Json[] tablesInfo;
        foreach (tableName, table; tables) {
            auto tableInfo = Json.emptyObject;
            tableInfo["name"] = tableName;
            tableInfo["rowCount"] = table.rows.length;
            tableInfo["columnCount"] = table.schema.columns.length;
            tablesInfo ~= tableInfo;
        }
        stats["tables"] = serializeToJson(tablesInfo);
        
        return stats;
    }
    
    private bool jsonEquals(Json a, Json b) {
        if (a.type != b.type) return false;
        
        final switch (a.type) {
            case Json.Type.undefined:
            case Json.Type.null_:
                return true;
            case Json.Type.bool_:
                return a.get!bool == b.get!bool;
            case Json.Type.int_:
                return a.get!long == b.get!long;
            case Json.Type.float_:
                return a.get!double == b.get!double;
            case Json.Type.string:
                return a.get!string == b.get!string;
            case Json.Type.array:
            case Json.Type.object:
                return a.toString() == b.toString();
        }
    }
}
