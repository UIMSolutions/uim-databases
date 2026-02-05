module uim.databases.object.classes.database;

import uim.databases.object;

mixin(ShowModule!());

@safe:

/// Main object database class
class ObjectDatabase {
    private {
        Document[string] documents;
        Index[string] indexes;
        string name;
    }
    
    this(string name = "default") {
        this.name = name;
    }
    
    /// Insert a new document
    string insert(Json data) {
        auto id = randomUUID().toString();
        return insert(id, data);
    }
    
    /// Insert a document with a specific ID
    string insert(string id, Json data) {
        enforce(id !in documents, "Document with ID '" ~ id ~ "' already exists");
        
        auto doc = Document(id, data);
        documents[id] = doc;
        
        // Update indexes
        foreach (index; indexes.byValue) {
            index.add(id, data);
        }
        
        return id;
    }
    
    /// Get a document by ID
    Document get(string id) {
        auto ptr = id in documents;
        enforce(ptr !is null, "Document with ID '" ~ id ~ "' not found");
        return *ptr;
    }
    
    /// Check if a document exists
    bool exists(string id) const {
        return (id in documents) !is null;
    }
    
    /// Update a document
    void update(string id, Json data) {
        auto ptr = id in documents;
        enforce(ptr !is null, "Document with ID '" ~ id ~ "' not found");
        
        // Remove from indexes
        foreach (index; indexes.byValue) {
            index.remove(id, ptr.data);
        }
        
        // Update document
        ptr.update(data);
        
        // Re-add to indexes
        foreach (index; indexes.byValue) {
            index.add(id, data);
        }
    }
    
    /// Delete a document
    bool remove(string id) {
        auto ptr = id in documents;
        if (ptr is null) return false;
        
        // Remove from indexes
        foreach (index; indexes.byValue) {
            index.remove(id, ptr.data);
        }
        
        documents.remove(id);
        return true;
    }
    
    /// Find documents matching a query
    Document[] find(Query query) {
        Document[] results;
        
        // First, filter by conditions
        foreach (doc; documents.byValue) {
            if (query.matches(doc)) {
                results ~= doc;
            }
        }
        
        // Sort if specified
        if (query.sortField.length > 0) {
            results.sort!((a, b) {
                auto aVal = getFieldForSort(a.data, query.sortField);
                auto bVal = getFieldForSort(b.data, query.sortField);
                int cmp = compareJsonValues(aVal, bVal);
                return query.sortAscending ? cmp < 0 : cmp > 0;
            });
        }
        
        // Apply skip and limit
        if (query.skipCount > 0) {
            results = results.drop(query.skipCount).array;
        }
        if (query.limitCount > 0) {
            results = results.take(query.limitCount).array;
        }
        
        return results;
    }
    
    /// Find all documents
    Document[] findAll() {
        return documents.values.dup;
    }
    
    /// Count documents matching a query
    size_t count(Query query) {
        size_t cnt = 0;
        foreach (doc; documents.byValue) {
            if (query.matches(doc)) {
                cnt++;
            }
        }
        return cnt;
    }
    
    /// Get total document count
    @property size_t count() const {
        return documents.length;
    }
    
    /// Create an index on a field
    void createIndex(string field) {
        if (field in indexes) return;
        
        auto index = new Index(field);
        
        // Build index from existing documents
        foreach (id, doc; documents) {
            index.add(id, doc.data);
        }
        
        indexes[field] = index;
    }
    
    /// Drop an index
    void dropIndex(string field) {
        indexes.remove(field);
    }
    
    /// Clear all documents
    void clear() {
        documents.clear();
        foreach (index; indexes.byValue) {
            index = new Index(index.field);
        }
    }
    
    /// Get database statistics
    Json getStats() {
        auto stats = Json.emptyObject;
        stats["name"] = name;
        stats["documentCount"] = documents.length;
        stats["indexCount"] = indexes.length;
        stats["indexes"] = serializeToJson(indexes.keys);
        return stats;
    }
    
    private Json getFieldForSort(Json doc, string fieldPath) {
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
    
    private int compareJsonValues(Json a, Json b) {
        if (a.type == Json.Type.undefined && b.type == Json.Type.undefined) return 0;
        if (a.type == Json.Type.undefined) return 1;
        if (b.type == Json.Type.undefined) return -1;
        
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
        
        return a.toString() < b.toString() ? -1 : (a.toString() > b.toString() ? 1 : 0);
    }
}
