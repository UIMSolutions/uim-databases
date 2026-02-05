module uim.databases.olap.query.builder;

import std.array;
import vibe.data.json;

/// MDX-like query builder for OLAP
class QueryBuilder {
    private {
        string _cubeName;
        string[] _selectDimensions;
        string[] _selectMeasures;
        Json _filters;
        string[] _orderBy;
        size_t _limit;
    }
    
    this() {
        _filters = Json.emptyObject;
        _limit = 0;
    }
    
    /// Select cube
    QueryBuilder from(string cubeName) {
        _cubeName = cubeName;
        return this;
    }
    
    /// Select dimensions
    QueryBuilder dimensions(string[] dims...) {
        _selectDimensions ~= dims;
        return this;
    }
    
    /// Select measures
    QueryBuilder measures(string[] meas...) {
        _selectMeasures ~= meas;
        return this;
    }
    
    /// Add filter
    QueryBuilder where(string dimension, string value) {
        _filters[dimension] = value;
        return this;
    }
    
    /// Add filters
    QueryBuilder where(Json filters) {
        foreach (string key, value; filters) {
            _filters[key] = value;
        }
        return this;
    }
    
    /// Order by
    QueryBuilder orderBy(string[] columns...) {
        _orderBy ~= columns;
        return this;
    }
    
    /// Limit results
    QueryBuilder limit(size_t count) {
        _limit = count;
        return this;
    }
    
    /// Build query object
    Json build() {
        auto query = Json.emptyObject;
        query["cube"] = _cubeName;
        query["dimensions"] = serializeToJson(_selectDimensions);
        query["measures"] = serializeToJson(_selectMeasures);
        query["filters"] = _filters;
        
        if (_orderBy.length > 0) {
            query["orderBy"] = serializeToJson(_orderBy);
        }
        
        if (_limit > 0) {
            query["limit"] = _limit;
        }
        
        return query;
    }
    
    /// Get cube name
    @property string cubeName() {
        return _cubeName;
    }
    
    /// Get dimensions
    @property string[] selectDimensions() {
        return _selectDimensions.dup;
    }
    
    /// Get measures
    @property string[] selectMeasures() {
        return _selectMeasures.dup;
    }
    
    /// Get filters
    @property Json filters() {
        return _filters;
    }
}
