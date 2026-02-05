module uim.databases.vector.classes.vector;

import uim.databases.vector;
@safe:

/// Represents a vector with its identifier and metadata
class Vector {
    this() {
    }

    // #region id
    /// Identifier of the vector
    protected string _id;
    @property string id() const {
        return _id;
    }
    @property void id(string value) {
        _id = value;
    }
    // #endregion id

    protected double[] _values;
    protected string[string] _metadata;

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
