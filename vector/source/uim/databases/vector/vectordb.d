module uim.databases.vector.vectordb;

import std.algorithm;
import std.array;
import std.range;
import std.exception;
import std.conv;
import vectorops;

/// Search result containing vector and its distance
struct SearchResult {
    Vector vector;
    double distance;
    
    int opCmp(ref const SearchResult other) const {
        if (distance < other.distance) return -1;
        if (distance > other.distance) return 1;
        return 0;
    }
}

/// Main vector database class
class VectorDatabase {
    private {
        Vector[string] vectors;
        size_t dimension;
        DistanceMetric metric;
    }

    /// Create a new vector database
    this(size_t dimension, DistanceMetric metric = DistanceMetric.EUCLIDEAN) {
        this.dimension = dimension;
        this.metric = metric;
    }

    /// Add a vector to the database
    void addVector(Vector vec) {
        enforce(vec.dimension == dimension, 
            "Vector dimension " ~ to!string(vec.dimension) ~ 
            " does not match database dimension " ~ to!string(dimension));
        
        vectors[vec.id] = vec;
    }

    /// Get a vector by ID
    Vector getVector(string id) {
        auto ptr = id in vectors;
        enforce(ptr !is null, "Vector with ID '" ~ id ~ "' not found");
        return *ptr;
    }

    /// Check if a vector exists
    bool hasVector(string id) const {
        return (id in vectors) !is null;
    }

    /// Delete a vector by ID
    bool deleteVector(string id) {
        return vectors.remove(id);
    }

    /// Update a vector's values and/or metadata
    void updateVector(string id, double[] newValues = null, string[string] newMetadata = null) {
        auto ptr = id in vectors;
        enforce(ptr !is null, "Vector with ID '" ~ id ~ "' not found");
        
        if (newValues !is null) {
            enforce(newValues.length == dimension, 
                "New vector dimension does not match database dimension");
            ptr.values = newValues.dup;
        }
        
        if (newMetadata !is null) {
            ptr.metadata = newMetadata;
        }
    }

    /// Search for the k nearest neighbors to a query vector
    SearchResult[] search(const double[] queryVector, size_t k) {
        enforce(queryVector.length == dimension, 
            "Query vector dimension does not match database dimension");
        
        SearchResult[] results;
        results.reserve(vectors.length);
        
        foreach (vec; vectors.byValue) {
            double dist = calculateDistance(queryVector, vec.values, metric);
            results ~= SearchResult(vec, dist);
        }
        
        // Sort by distance and take top k
        results.sort();
        return results.take(k).array;
    }

    /// Search by vector ID
    SearchResult[] searchById(string id, size_t k) {
        auto vec = getVector(id);
        return search(vec.values, k);
    }

    /// Get the number of vectors in the database
    @property size_t count() const {
        return vectors.length;
    }

    /// Get the dimension of vectors in this database
    @property size_t getDimension() const {
        return dimension;
    }

    /// Get all vector IDs
    string[] getAllIds() const {
        return vectors.keys.dup;
    }

    /// Clear all vectors
    void clear() {
        vectors.clear();
    }

    /// Filter vectors by metadata
    Vector[] filterByMetadata(string key, string value) {
        Vector[] results;
        foreach (vec; vectors.byValue) {
            if (key in vec.metadata && vec.metadata[key] == value) {
                results ~= vec;
            }
        }
        return results;
    }
}
