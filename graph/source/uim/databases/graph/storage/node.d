module uim.databases.graph.storage.node;

import std.uuid;
import std.datetime;
import vibe.data.json;

/// Graph node
class Node {
    private {
        string _id;
        string _label;
        Json _properties;
        string[] _labels;
        SysTime _createdAt;
        SysTime _updatedAt;
    }
    
    this(string label = "", Json properties = Json.emptyObject) {
        _id = randomUUID().toString();
        _label = label;
        _properties = properties;
        _createdAt = Clock.currTime();
        _updatedAt = _createdAt;
    }
    
    this(string id, string label, Json properties) {
        _id = id;
        _label = label;
        _properties = properties;
        _createdAt = Clock.currTime();
        _updatedAt = _createdAt;
    }
    
    /// Get node ID
    @property string id() {
        return _id;
    }
    
    /// Get node label
    @property string label() {
        return _label;
    }
    
    /// Set node label
    @property void label(string l) {
        _label = l;
        _updatedAt = Clock.currTime();
    }
    
    /// Get properties
    @property Json properties() {
        return _properties;
    }
    
    /// Set properties
    @property void properties(Json props) {
        _properties = props;
        _updatedAt = Clock.currTime();
    }
    
    /// Get property
    Json getProperty(string key) {
        if (key in _properties) {
            return _properties[key];
        }
        return Json(null);
    }
    
    /// Set property
    void setProperty(string key, Json value) {
        _properties[key] = value;
        _updatedAt = Clock.currTime();
    }
    
    /// Add label
    void addLabel(string lbl) {
        import std.algorithm : canFind;
        if (!_labels.canFind(lbl)) {
            _labels ~= lbl;
        }
    }
    
    /// Remove label
    void removeLabel(string lbl) {
        import std.algorithm : remove;
        _labels = _labels.remove!(a => a == lbl).array;
    }
    
    /// Get all labels
    @property string[] labels() {
        return _labels.dup;
    }
    
    /// Check if has label
    bool hasLabel(string lbl) {
        import std.algorithm : canFind;
        return _labels.canFind(lbl);
    }
    
    /// Get created time
    @property SysTime createdAt() {
        return _createdAt;
    }
    
    /// Get updated time
    @property SysTime updatedAt() {
        return _updatedAt;
    }
    
    /// Clone node
    Node clone() {
        auto newNode = new Node(_id, _label, _properties.clone());
        newNode._labels = _labels.dup;
        newNode._createdAt = _createdAt;
        newNode._updatedAt = _updatedAt;
        return newNode;
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["id"] = _id;
        result["label"] = _label;
        result["properties"] = _properties;
        result["labels"] = serializeToJson(_labels);
        result["createdAt"] = _createdAt.toISOExtString();
        result["updatedAt"] = _updatedAt.toISOExtString();
        return result;
    }
}

import std.algorithm : remove, canFind;
