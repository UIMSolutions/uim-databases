module source.objectdb;

import std.datetime;
import std.uuid;
import std.algorithm;
import std.array;
import std.range;
import std.exception;
import std.conv;
import vibe.data.json;

/// Represents a document in the database
struct Document {
    string id;
    Json data;
    SysTime createdAt;
    SysTime updatedAt;
    
    this(string id, Json data) {
        this.id = id;
        this.data = data;
        this.createdAt = Clock.currTime();
        this.updatedAt = Clock.currTime();
    }
    
    void update(Json newData) {
        this.data = newData;
        this.updatedAt = Clock.currTime();
    }
}

/// Query operator types
enum QueryOp {
    EQUALS,      // ==
    NOT_EQUALS,  // !=
    GREATER,     // >
    LESS,        // <
    GREATER_EQ,  // >=
    LESS_EQ,     // <=
    CONTAINS,    // string contains
    IN,          // value in array
    EXISTS       // field exists
}

/// Query condition
struct QueryCondition {
    string field;
    QueryOp op;
    Json value;
    
    bool matches(Json doc) {
        // Navigate to nested field using dot notation
        Json fieldValue = getNestedField(doc, field);
        
        if (fieldValue.type == Json.Type.undefined) {
            return op == QueryOp.EXISTS && value.get!bool == false;
        }
        
        final switch (op) {
            case QueryOp.EQUALS:
                return jsonEquals(fieldValue, value);
            case QueryOp.NOT_EQUALS:
                return !jsonEquals(fieldValue, value);
            case QueryOp.GREATER:
                return jsonCompare(fieldValue, value) > 0;
            case QueryOp.LESS:
                return jsonCompare(fieldValue, value) < 0;
            case QueryOp.GREATER_EQ:
                return jsonCompare(fieldValue, value) >= 0;
            case QueryOp.LESS_EQ:
                return jsonCompare(fieldValue, value) <= 0;
            case QueryOp.CONTAINS:
                if (fieldValue.type == Json.Type.string && value.type == Json.Type.string) {
                    import std.string : indexOf;
                    return indexOf(fieldValue.get!string, value.get!string) != -1;
                }
                return false;
            case QueryOp.IN:
                if (value.type == Json.Type.array) {
                    foreach (v; value) {
                        if (jsonEquals(fieldValue, v)) return true;
                    }
                }
                return false;
            case QueryOp.EXISTS:
                return value.get!bool;
        }
    }
    
    private Json getNestedField(Json doc, string fieldPath) {
        import std.string : split;
        auto parts = split(fieldPath, ".");
        Json current = doc;
        
        foreach (part; parts) {
            if (current.type != Json.Type.object || part !in current) {
                return Json.undefined;
            }
            current = current[part];
        }
        
        return current;
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
    
    private int jsonCompare(Json a, Json b) {
        if (a.type == Json.Type.int_ && b.type == Json.Type.int_) {
            long av = a.get!long;
            long bv = b.get!long;
            return av < bv ? -1 : (av > bv ? 1 : 0);
        }
        if ((a.type == Json.Type.float_ || a.type == Json.Type.int_) &&
            (b.type == Json.Type.float_ || b.type == Json.Type.int_)) {
            double av = a.type == Json.Type.float_ ? a.get!double : a.get!long;
            double bv = b.type == Json.Type.float_ ? b.get!double : b.get!long;
            return av < bv ? -1 : (av > bv ? 1 : 0);
        }
        if (a.type == Json.Type.string && b.type == Json.Type.string) {
            string av = a.get!string;
            string bv = b.get!string;
            return av < bv ? -1 : (av > bv ? 1 : 0);
        }
        return 0;
    }
}

/// Query builder for filtering documents
struct Query {
    QueryCondition[] conditions;
    string sortField;
    bool sortAscending = true;
    size_t limitCount = 0;
    size_t skipCount = 0;
    
    Query where(string field, QueryOp op, Json value) {
        conditions ~= QueryCondition(field, op, value);
        return this;
    }
    
    Query sortBy(string field, bool ascending = true) {
        sortField = field;
        sortAscending = ascending;
        return this;
    }
    
    Query limit(size_t count) {
        limitCount = count;
        return this;
    }
    
    Query skip(size_t count) {
        skipCount = count;
        return this;
    }
    
    bool matches(Document doc) {
        foreach (condition; conditions) {
            if (!condition.matches(doc.data)) {
                return false;
            }
        }
        return true;
    }
}




