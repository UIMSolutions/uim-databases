module uim.databases.graph.storage.graph;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import std.container;
import vibe.data.json;
import vibe.core.log;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;

/// Graph storage
class GraphStorage {
    private {
        string _name;
        Node[string] _nodes;
        Edge[string] _edges;
        string[][string] _nodeOutEdges;  // nodeId -> [edgeIds]
        string[][string] _nodeInEdges;   // nodeId -> [edgeIds]
        ReadWriteMutex _mutex;
    }
    
    this(string name) {
        _name = name;
        _mutex = new ReadWriteMutex();
        logInfo("Graph '%s' initialized", _name);
    }
    
    /// Get graph name
    @property string name() {
        return _name;
    }
    
    /// Add node
    string addNode(Node node) {
        synchronized(_mutex.writer) {
            if (node.id in _nodes) {
                throw new Exception("Node already exists: " ~ node.id);
            }
            
            _nodes[node.id] = node;
            _nodeOutEdges[node.id] = [];
            _nodeInEdges[node.id] = [];
            
            logInfo("Added node: %s (%s)", node.id, node.label);
            return node.id;
        }
    }
    
    /// Add edge
    string addEdge(Edge edge) {
        synchronized(_mutex.writer) {
            if (edge.fromNodeId !in _nodes || edge.toNodeId !in _nodes) {
                throw new Exception("One or both nodes do not exist");
            }
            
            if (edge.id in _edges) {
                throw new Exception("Edge already exists: " ~ edge.id);
            }
            
            _edges[edge.id] = edge;
            _nodeOutEdges[edge.fromNodeId] ~= edge.id;
            _nodeInEdges[edge.toNodeId] ~= edge.id;
            
            if (!edge.isDirected) {
                _nodeInEdges[edge.fromNodeId] ~= edge.id;
                _nodeOutEdges[edge.toNodeId] ~= edge.id;
            }
            
            logInfo("Added edge: %s (%s) from %s to %s", edge.id, edge.type, edge.fromNodeId, edge.toNodeId);
            return edge.id;
        }
    }
    
    /// Get node
    Node getNode(string nodeId) {
        synchronized(_mutex.reader) {
            if (auto node = nodeId in _nodes) {
                return node.clone();
            }
            return null;
        }
    }
    
    /// Get edge
    Edge getEdge(string edgeId) {
        synchronized(_mutex.reader) {
            if (auto edge = edgeId in _edges) {
                return edge.clone();
            }
            return null;
        }
    }
    
    /// Update node
    bool updateNode(string nodeId, Json properties) {
        synchronized(_mutex.writer) {
            if (auto node = nodeId in _nodes) {
                node.properties = properties;
                return true;
            }
            return false;
        }
    }
    
    /// Update edge
    bool updateEdge(string edgeId, Json properties) {
        synchronized(_mutex.writer) {
            if (auto edge = edgeId in _edges) {
                edge.properties = properties;
                return true;
            }
            return false;
        }
    }
    
    /// Delete node
    bool deleteNode(string nodeId) {
        synchronized(_mutex.writer) {
            if (nodeId !in _nodes) {
                return false;
            }
            
            // Delete all connected edges
            auto outEdges = _nodeOutEdges[nodeId].dup;
            foreach (edgeId; outEdges) {
                deleteEdge(edgeId);
            }
            
            auto inEdges = _nodeInEdges[nodeId].dup;
            foreach (edgeId; inEdges) {
                deleteEdge(edgeId);
            }
            
            _nodes.remove(nodeId);
            _nodeOutEdges.remove(nodeId);
            _nodeInEdges.remove(nodeId);
            
            logInfo("Deleted node: %s", nodeId);
            return true;
        }
    }
    
    /// Delete edge
    bool deleteEdge(string edgeId) {
        synchronized(_mutex.writer) {
            if (auto edge = edgeId in _edges) {
                auto fromId = edge.fromNodeId;
                auto toId = edge.toNodeId;
                
                _nodeOutEdges[fromId] = _nodeOutEdges[fromId].filter!(id => id != edgeId).array;
                _nodeInEdges[toId] = _nodeInEdges[toId].filter!(id => id != edgeId).array;
                
                if (!edge.isDirected) {
                    _nodeInEdges[fromId] = _nodeInEdges[fromId].filter!(id => id != edgeId).array;
                    _nodeOutEdges[toId] = _nodeOutEdges[toId].filter!(id => id != edgeId).array;
                }
                
                _edges.remove(edgeId);
                logInfo("Deleted edge: %s", edgeId);
                return true;
            }
            return false;
        }
    }
    
    /// Get all nodes
    Node[] getAllNodes() {
        synchronized(_mutex.reader) {
            return _nodes.values.map!(n => n.clone()).array;
        }
    }
    
    /// Get all edges
    Edge[] getAllEdges() {
        synchronized(_mutex.reader) {
            return _edges.values.map!(e => e.clone()).array;
        }
    }
    
    /// Get outgoing edges of a node
    Edge[] getOutgoingEdges(string nodeId) {
        synchronized(_mutex.reader) {
            if (auto edgeIds = nodeId in _nodeOutEdges) {
                return (*edgeIds)
                    .map!(id => _edges[id])
                    .filter!(e => e !is null)
                    .map!(e => e.clone())
                    .array;
            }
            return [];
        }
    }
    
    /// Get incoming edges of a node
    Edge[] getIncomingEdges(string nodeId) {
        synchronized(_mutex.reader) {
            if (auto edgeIds = nodeId in _nodeInEdges) {
                return (*edgeIds)
                    .map!(id => _edges[id])
                    .filter!(e => e !is null)
                    .map!(e => e.clone())
                    .array;
            }
            return [];
        }
    }
    
    /// Get neighbors of a node
    Node[] getNeighbors(string nodeId) {
        synchronized(_mutex.reader) {
            Node[] neighbors;
            
            // Outgoing neighbors
            if (auto edgeIds = nodeId in _nodeOutEdges) {
                foreach (edgeId; *edgeIds) {
                    if (auto edge = edgeId in _edges) {
                        if (auto node = edge.toNodeId in _nodes) {
                            neighbors ~= node.clone();
                        }
                    }
                }
            }
            
            // Incoming neighbors (for undirected edges)
            if (auto edgeIds = nodeId in _nodeInEdges) {
                foreach (edgeId; *edgeIds) {
                    if (auto edge = edgeId in _edges) {
                        if (!edge.isDirected || edge.toNodeId == nodeId) {
                            if (auto node = edge.fromNodeId in _nodes) {
                                // Check if not already added
                                bool found = false;
                                foreach (n; neighbors) {
                                    if (n.id == edge.fromNodeId) {
                                        found = true;
                                        break;
                                    }
                                }
                                if (!found) {
                                    neighbors ~= node.clone();
                                }
                            }
                        }
                    }
                }
            }
            
            return neighbors;
        }
    }
    
    /// Find edges by type
    Edge[] findEdgesByType(string edgeType) {
        synchronized(_mutex.reader) {
            return _edges.values
                .filter!(e => e.type == edgeType)
                .map!(e => e.clone())
                .array;
        }
    }
    
    /// Find nodes by label
    Node[] findNodesByLabel(string label) {
        synchronized(_mutex.reader) {
            return _nodes.values
                .filter!(n => n.label == label)
                .map!(n => n.clone())
                .array;
        }
    }
    
    /// Get node count
    @property size_t nodeCount() {
        synchronized(_mutex.reader) {
            return _nodes.length;
        }
    }
    
    /// Get edge count
    @property size_t edgeCount() {
        synchronized(_mutex.reader) {
            return _edges.length;
        }
    }
    
    /// Get graph statistics
    Json getStatistics() {
        synchronized(_mutex.reader) {
            auto stats = Json.emptyObject;
            stats["name"] = _name;
            stats["nodeCount"] = _nodes.length;
            stats["edgeCount"] = _edges.length;
            
            size_t directedCount = 0;
            size_t undirectedCount = 0;
            foreach (edge; _edges.values) {
                if (edge.isDirected) directedCount++;
                else undirectedCount++;
            }
            stats["directedEdges"] = directedCount;
            stats["undirectedEdges"] = undirectedCount;
            
            return stats;
        }
    }
}

import std.algorithm : filter, map;
import std.array : array;
