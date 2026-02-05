module uim.databases.oltp.classes.query;

import std.array;
import std.format;
import vibe.core.log;

/// Query builder for OLTP operations
class Query {
    private {
        string _table;
        string[] _columns;
        string[string] _whereConditions;
        string[string] _values;
        string _queryType; // SELECT, INSERT, UPDATE, DELETE
        size_t _limit;
        size_t _offset;
    }
    
    this() {
        _limit = 0;
        _offset = 0;
    }
    
    /// Set the table name
    Query table(string tableName) {
        _table = tableName;
        return this;
    }
    
    /// Select specific columns
    Query select(string[] columns...) {
        _queryType = "SELECT";
        _columns = columns.dup;
        return this;
    }
    
    /// Insert operation
    Query insert(string[string] values) {
        _queryType = "INSERT";
        _values = values.dup;
        return this;
    }
    
    /// Update operation
    Query update(string[string] values) {
        _queryType = "UPDATE";
        _values = values.dup;
        return this;
    }
    
    /// Delete operation
    Query deleteFrom() {
        _queryType = "DELETE";
        return this;
    }
    
    /// Add WHERE condition
    Query where(string column, string value) {
        _whereConditions[column] = value;
        return this;
    }
    
    /// Set LIMIT
    Query limit(size_t count) {
        _limit = count;
        return this;
    }
    
    /// Set OFFSET
    Query offset(size_t count) {
        _offset = count;
        return this;
    }
    
    /// Build the SQL query string
    string build() {
        Appender!string query;
        
        final switch (_queryType) {
            case "SELECT":
                query ~= "SELECT ";
                if (_columns.length == 0) {
                    query ~= "*";
                } else {
                    query ~= _columns.join(", ");
                }
                query ~= " FROM " ~ _table;
                break;
                
            case "INSERT":
                query ~= "INSERT INTO " ~ _table;
                if (_values.length > 0) {
                    auto keys = _values.keys;
                    auto vals = _values.values;
                    query ~= format(" (%s) VALUES (%s)", 
                        keys.join(", "),
                        vals.map!(v => "'" ~ v ~ "'").join(", ")
                    );
                }
                break;
                
            case "UPDATE":
                query ~= "UPDATE " ~ _table ~ " SET ";
                string[] setPairs;
                foreach (key, val; _values) {
                    setPairs ~= format("%s = '%s'", key, val);
                }
                query ~= setPairs.join(", ");
                break;
                
            case "DELETE":
                query ~= "DELETE FROM " ~ _table;
                break;
                
            case "":
                throw new Exception("Query type not specified");
        }
        
        // Add WHERE clause
        if (_whereConditions.length > 0) {
            query ~= " WHERE ";
            string[] conditions;
            foreach (column, value; _whereConditions) {
                conditions ~= format("%s = '%s'", column, value);
            }
            query ~= conditions.join(" AND ");
        }
        
        // Add LIMIT and OFFSET
        if (_limit > 0) {
            query ~= format(" LIMIT %d", _limit);
        }
        if (_offset > 0) {
            query ~= format(" OFFSET %d", _offset);
        }
        
        return query.data;
    }
    
    /// Get query parameters (for prepared statements)
    string[string] getParams() {
        return _values;
    }
}

// Import needed functions
import std.algorithm : map, joiner;
import std.conv : to;
