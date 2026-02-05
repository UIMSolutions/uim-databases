module uim.databases.oltp.wal.record;

import std.datetime;
import std.uuid;
import vibe.data.json;

/// Types of WAL records
enum WALRecordType {
    begin,
    insert,
    update,
    delete_,
    commit,
    rollback,
    checkpoint
}

/// Write-Ahead Log record
struct WALRecord {
    string id;
    WALRecordType type;
    string transactionId;
    string tableName;
    string rowId;
    Json data;
    SysTime timestamp;
    
    this(WALRecordType type, string transactionId, string tableName = "", string rowId = "", Json data = Json.emptyObject) {
        this.id = randomUUID().toString();
        this.type = type;
        this.transactionId = transactionId;
        this.tableName = tableName;
        this.rowId = rowId;
        this.data = data;
        this.timestamp = Clock.currTime();
    }
    
    /// Convert to JSON
    Json toJson() const {
        auto result = Json.emptyObject;
        result["id"] = id;
        result["type"] = type.to!string;
        result["transactionId"] = transactionId;
        result["tableName"] = tableName;
        result["rowId"] = rowId;
        result["data"] = data;
        result["timestamp"] = timestamp.toISOExtString();
        return result;
    }
    
    /// Create from JSON
    static WALRecord fromJson(Json json) {
        WALRecord record;
        record.id = json["id"].get!string;
        record.type = json["type"].get!string.to!WALRecordType;
        record.transactionId = json["transactionId"].get!string;
        record.tableName = json["tableName"].get!string;
        record.rowId = json["rowId"].get!string;
        record.data = json["data"];
        record.timestamp = SysTime.fromISOExtString(json["timestamp"].get!string);
        return record;
    }
}

import std.conv : to;
