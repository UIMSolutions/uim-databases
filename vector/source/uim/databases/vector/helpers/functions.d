module uim.databases.vector.vectorops;

import std.math;
import std.algorithm;
import std.range;
import std.array;

/// Calculate the Euclidean distance between two vectors
double euclideanDistance(const double[] a, const double[] b) {
    assert(a.length == b.length, "Vectors must have the same dimension");
    
    double sum = 0.0;
    foreach (i; 0 .. a.length) {
        double diff = a[i] - b[i];
        sum += diff * diff;
    }
    return sqrt(sum);
}

/// Calculate the cosine similarity between two vectors
double cosineSimilarity(const double[] a, const double[] b) {
    assert(a.length == b.length, "Vectors must have the same dimension");
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    foreach (i; 0 .. a.length) {
        dotProduct += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }
    
    if (normA == 0.0 || normB == 0.0) {
        return 0.0;
    }
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
}

/// Calculate the Manhattan distance (L1 norm) between two vectors
double manhattanDistance(const double[] a, const double[] b) {
    assert(a.length == b.length, "Vectors must have the same dimension");
    
    double sum = 0.0;
    foreach (i; 0 .. a.length) {
        sum += abs(a[i] - b[i]);
    }
    return sum;
}

/// Calculate the dot product of two vectors
double dotProduct(const double[] a, const double[] b) {
    assert(a.length == b.length, "Vectors must have the same dimension");
    
    double result = 0.0;
    foreach (i; 0 .. a.length) {
        result += a[i] * b[i];
    }
    return result;
}

/// Normalize a vector to unit length
double[] normalize(const double[] vec) {
    double norm = sqrt(vec.map!(x => x * x).sum);
    if (norm == 0.0) {
        return vec.dup;
    }
    return vec.map!(x => x / norm).array;
}

/// Enum for distance metric types
enum DistanceMetric {
    EUCLIDEAN,
    COSINE,
    MANHATTAN,
    DOT_PRODUCT
}

/// Calculate distance based on the specified metric
double calculateDistance(const double[] a, const double[] b, DistanceMetric metric) {
    final switch (metric) {
        case DistanceMetric.EUCLIDEAN:
            return euclideanDistance(a, b);
        case DistanceMetric.COSINE:
            return 1.0 - cosineSimilarity(a, b); // Convert similarity to distance
        case DistanceMetric.MANHATTAN:
            return manhattanDistance(a, b);
        case DistanceMetric.DOT_PRODUCT:
            return -dotProduct(a, b); // Negative for higher = closer
    }
}
