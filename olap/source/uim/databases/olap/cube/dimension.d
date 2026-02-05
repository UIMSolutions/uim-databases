module uim.databases.olap.cube.dimension;

import std.array;
import vibe.data.json;

/// OLAP dimension
class Dimension {
    private {
        string _name;
        string[] _attributes;
        string[string] _attributeTypes; // attribute -> type
        string[] _hierarchyLevels;
    }
    
    this(string name, string[] attributes = []) {
        _name = name;
        _attributes = attributes.dup;
    }
    
    /// Get dimension name
    @property string name() {
        return _name;
    }
    
    /// Add attribute
    void addAttribute(string attrName, string attrType = "string") {
        _attributes ~= attrName;
        _attributeTypes[attrName] = attrType;
    }
    
    /// Get attributes
    @property string[] attributes() {
        return _attributes.dup;
    }
    
    /// Set hierarchy levels
    void setHierarchy(string[] levels) {
        _hierarchyLevels = levels.dup;
    }
    
    /// Get hierarchy levels
    @property string[] hierarchyLevels() {
        return _hierarchyLevels.dup;
    }
    
    /// Get attribute type
    string getAttributeType(string attrName) {
        if (auto type = attrName in _attributeTypes) {
            return *type;
        }
        return "string";
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["name"] = _name;
        result["attributes"] = serializeToJson(_attributes);
        result["hierarchy"] = serializeToJson(_hierarchyLevels);
        return result;
    }
}
