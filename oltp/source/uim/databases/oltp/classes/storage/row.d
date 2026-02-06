module uim.databases.oltp.storage.row;

import std.uuid;
import std.datetime;
import vibe.data.json;

/// Represents a single row in a table
class Row {
    private {
        string _id;
        Json _data;
        SysTime _createdAt;
        SysTime _updatedAt;
        string _transactionId;
        bool _deleted;
        size_t _version;
    }
    
    this() {
        _id = randomUUID().toString();
        _data = Json.emptyObject;
        _createdAt = Clock.currTime();
        _updatedAt = _createdAt;
        _deleted = false;
        _version = 1;
    }
    
    this(Json data) {
        this();
        _data = data;
    }
    
    /// Get row ID
    @property string id() {
        return _id;
    }
    
    /// Get/Set row data
    @property Json data() {
        return _data;
    }
    
    @property void data(Json value) {
        _data = value;
        _updatedAt = Clock.currTime();
        _version++;
    }
    
    /// Get column value
    Json get(string column) {
        if (column in _data) {
            return _data[column];
        }
        return Json(null);
    }
    
    /// Set column value
    void set(string column, Json value) {
        _data[column] = value;
        _updatedAt = Clock.currTime();
        _version++;
    }
    
    /// Check if column exists
    bool has(string column) {
        return (column in _data) !is null;
    }
    
    /// Mark row as deleted
    void markDeleted(string transactionId) {
        _deleted = true;
        _transactionId = transactionId;
        _updatedAt = Clock.currTime();
    }
    
    /// Check if row is deleted
    @property bool isDeleted() {
        return _deleted;
    }
    
    /// Get version number
    @property size_t version_() {
        return _version;
    }
    
    /// Get created timestamp
    @property SysTime createdAt() {
        return _createdAt;
    }
    
    /// Get updated timestamp
    @property SysTime updatedAt() {
        return _updatedAt;
    }
    
    /// Get transaction ID
    @property string transactionId() {
        return _transactionId;
    }
    
    /// Set transaction ID
    @property void transactionId(string id) {
        _transactionId = id;
    }
    
    /// Clone the row
    Row clone() {
        auto newRow = new Row();
        newRow._id = _id;
        newRow._data = _data.clone();
        newRow._createdAt = _createdAt;
        newRow._updatedAt = _updatedAt;
        newRow._transactionId = _transactionId;
        newRow._deleted = _deleted;
        newRow._version = _version;
        return newRow;
    }
    
    /// Convert to JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["_id"] = _id;
        result["_version"] = _version;
        result["_createdAt"] = _createdAt.toISOExtString();
        result["_updatedAt"] = _updatedAt.toISOExtString();
        result["_deleted"] = _deleted;
        result["data"] = _data;
        return result;
    }
}
