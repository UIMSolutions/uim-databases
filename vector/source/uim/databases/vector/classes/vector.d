module uim.databases.vector.classes.vector;

import uim.databases.vector;
@safe:

/// Represents a vector with its identifier and metadata
class Vector {
    string id;
    double[] values;
    string[string] metadata;

    this(string id, double[] values, string[string] metadata = null) {
        this.id = id;
        this.values = values.dup;
        this.metadata = metadata.dup;
    }

    /// Get the dimensionality of the vector
    @property size_t dimension() const {
        return values.length;
    }
}
