module uim.databases.object.classes.index;

import uim.databases.object;

mixin(ShowModule!());

@safe:

/// Index for faster queries
class Index {
    private {
        string field;
        string[Json] indexMap;  // value -> document IDs (simplified)
        string[][string] valueToIds;  // value string -> doc IDs
    }
    
    this(string field) {
        this.field = field;
    }
    
    void add(string docId, Json doc) {
        auto value = getFieldValue(doc, field);
        if (value.type != Json.Type.undefined) {
            string key = value.toString();
            if (key !in valueToIds) {
                valueToIds[key] = null;
            }
            valueToIds[key] ~= docId;
        }
    }
    
    void remove(string docId, Json doc) {
        auto value = getFieldValue(doc, field);
        if (value.type != Json.Type.undefined) {
            string key = value.toString();
            if (key in valueToIds) {
                valueToIds[key] = valueToIds[key].filter!(id => id != docId).array;
                if (valueToIds[key].length == 0) {
                    valueToIds.remove(key);
                }
            }
        }
    }
    
    string[] lookup(Json value) {
        string key = value.toString();
        if (key in valueToIds) {
            return valueToIds[key].dup;
        }
        return null;
    }
    
    private Json getFieldValue(Json doc, string fieldPath) {
        import std.string : split;
        auto parts = split(fieldPath, ".");
        Json current = doc;
        
        foreach (part; parts) {
            if (!current.isObject || part !in current) {
                return Json.undefined;
            }
            current = current[part];
        }
        
        return current;
    }
}