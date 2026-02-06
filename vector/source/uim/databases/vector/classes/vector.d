/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.classes.vector;

import uim.databases.vector;
@safe:

/// Represents a vector with its identifier and metadata
class Vector {
    this() {
    }

    this(string id, double[] values, string[string] metadata = null) {
        this.id = id;
        this.values = values.dup;
        this.metadata = metadata.dup;
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
    ///
    unittest {
        mixin(ShowTests!"Vector ID Property Test");

        Vector v = new Vector();
        v.id = "vec1";
        assert(v.id == "vec1");
    }
    // #endregion id

    // #region values
    /// Values of the vector
    protected double[] _values;
    @property double[] values() const {
        return _values.dup;
    }
    @property void values(double[] vals) {
        _values = vals.dup;
    }
    ///
    unittest {
        mixin(ShowTests!"Vector Values Property Test");

        Vector v = new Vector();
        v.values = [1.0, 2.0, 3.0];
        assert(v.values.length == 3);
        assert(v.values[0] == 1.0);
    }
    // #endregion values
    
    // #region metadata
    /// Metadata associated with the vector
    protected string[string] _metadata;
    @property void metadata(string[string] meta) {
        _metadata = meta.dup;
    }
    @property string[string] metadata() const {
        return _metadata.dup;
    }
        ///
    unittest {
        mixin(ShowTests!"Vector Metadata Property Test");

        Vector v = new Vector();
        v.metadata = ["author": "Alice", "category": "test"];
        assert(v.metadata["author"] == "Alice");
        assert(v.metadata["category"] == "test");
    }   
    // #endregion metadata

    /// Get the dimensionality of the vector
    @property size_t dimension() const {
        return values.length;
    }
}
