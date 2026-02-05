module uim.databases.graph.storage.edge;

import std.uuid;
import std.datetime;
import vibe.data.json;

/// Graph edge (relationship)
class Edge {
    private {
        string _id;
        string _type;
        string _fromNodeId;
        string _toNodeId;
        Json _properties;
        SysTime _createdAt;
        SysTime _updatedAt;
        bool _directed;
    }
    
    this(string fromNodeId, string toNodeId, string type = "RELATES_TO", bool directed = true, Json properties = Json.emptyObject) {
        _id = randomUUID().toString();
        _type = type;
        _fromNodeId = fromNodeId;
        _toNodeId = toNodeId;
        _properties = properties;
        _directed = directed;
        _createdAt = Clock.currTime();
        _updatedAt = _createdAt;
    }
    
    /// Get edge ID
    @property string id() {
        return _id;
    }
    
    /// Get edge type
    @property string type() {
        return _type;
    }
    
    /// Set edge type
    @property void type(string t) {
        _type = t;
        _updatedAt = Clock.currTime();
    }
    
    /// Get from node ID
    @property string fromNodeId() {
        return _fromNodeId;
    }
    
    /// Get to node ID
    @property string toNodeId() {
        return _toNodeId;
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
    
    /// Check if directed
    @property bool isDirected() {
        return _directed;
    }
    
    /// Get created time
    @property SysTime createdAt() {
        return _createdAt;
    }
    
    /// Get updated time
    @property SysTime updatedAt() {
        return _updatedAt;
    }
    
    /// Check if connects two nodes
    bool connects(string nodeId1, string nodeId2) {
        if (_directed) {
            return _fromNodeId == nodeId1 && _toNodeId == nodeId2;
        } else {
            return (_fromNodeId == nodeId1 && _toNodeId == nodeId2) ||
                   (_fromNodeId == nodeId2 && _toNodeId == nodeId1);
        }
    }
    
    /// Clone edge
    Edge clone() {
        auto newEdge = new Edge(_fromNodeId, _toNodeId, _type, _directed, _properties.clone());
        newEdge._id = _id;
        newEdge._createdAt = _createdAt;
        newEdge._updatedAt = _updatedAt;
        return newEdge;
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["id"] = _id;
        result["type"] = _type;
        result["from"] = _fromNodeId;
        result["to"] = _toNodeId;
        result["directed"] = _directed;
        result["properties"] = _properties;
        result["createdAt"] = _createdAt.toISOExtString();
        result["updatedAt"] = _updatedAt.toISOExtString();
        return result;
    }
}
