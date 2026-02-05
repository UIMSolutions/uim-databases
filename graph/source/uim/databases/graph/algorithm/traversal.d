module uim.databases.graph.algorithm.traversal;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import std.container;
import vibe.data.json;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;

/// Graph traversal operations
class TraversalEngine {
    private {
        GraphStorage _graph;
    }
    
    this(GraphStorage graph) {
        _graph = graph;
    }
    
    /// Breadth-first search
    Node[] bfs(string startNodeId) {
        auto visited = new bool[string];
        auto queue = DList!string(startNodeId);
        Node[] result;
        
        visited[startNodeId] = true;
        
        while (!queue.empty) {
            auto nodeId = queue.front;
            queue.removeFront();
            
            auto node = _graph.getNode(nodeId);
            if (node !is null) {
                result ~= node;
            }
            
            auto neighbors = _graph.getNeighbors(nodeId);
            foreach (neighbor; neighbors) {
                if (!(neighbor.id in visited)) {
                    visited[neighbor.id] = true;
                    queue.insertBack(neighbor.id);
                }
            }
        }
        
        return result;
    }
    
    /// Depth-first search
    Node[] dfs(string startNodeId) {
        auto visited = new bool[string];
        Node[] result;
        
        dfsHelper(startNodeId, visited, result);
        
        return result;
    }
    
    /// Get connected components
    Node[][] connectedComponents() {
        auto visited = new bool[string];
        Node[][] components;
        
        auto allNodes = _graph.getAllNodes();
        foreach (node; allNodes) {
            if (!(node.id in visited)) {
                auto component = bfs(node.id);
                foreach (n; component) {
                    visited[n.id] = true;
                }
                components ~= component;
            }
        }
        
        return components;
    }
    
    /// Check if path exists between two nodes
    bool pathExists(string fromNodeId, string toNodeId) {
        if (fromNodeId == toNodeId) return true;
        
        auto visited = new bool[string];
        auto queue = DList!string(fromNodeId);
        visited[fromNodeId] = true;
        
        while (!queue.empty) {
            auto nodeId = queue.front;
            queue.removeFront();
            
            if (nodeId == toNodeId) {
                return true;
            }
            
            auto neighbors = _graph.getNeighbors(nodeId);
            foreach (neighbor; neighbors) {
                if (!(neighbor.id in visited)) {
                    visited[neighbor.id] = true;
                    queue.insertBack(neighbor.id);
                }
            }
        }
        
        return false;
    }
    
    /// Get all neighbors within distance
    Node[] neighborsWithinDistance(string nodeId, size_t distance) {
        auto visited = new bool[string];
        auto queue = DList!string[string];
        queue[nodeId] = DList!string();
        Node[] result;
        
        visited[nodeId] = true;
        
        size_t currentDistance = 0;
        while (!queue.empty && currentDistance < distance) {
            string[] nextQueue;
            
            foreach (key; queue.byKey()) {
                auto neighbors = _graph.getNeighbors(key);
                foreach (neighbor; neighbors) {
                    if (!(neighbor.id in visited)) {
                        visited[neighbor.id] = true;
                        nextQueue ~= neighbor.id;
                        result ~= neighbor;
                    }
                }
            }
            
            // Prepare next level
            foreach (key; queue.byKey()) {
                queue.remove(key);
            }
            foreach (nodeToAdd; nextQueue) {
                queue[nodeToAdd] = DList!string();
            }
            
            currentDistance++;
        }
        
        return result;
    }
    
    private {
        void dfsHelper(string nodeId, bool[string] visited, ref Node[] result) {
            visited[nodeId] = true;
            
            auto node = _graph.getNode(nodeId);
            if (node !is null) {
                result ~= node;
            }
            
            auto neighbors = _graph.getNeighbors(nodeId);
            foreach (neighbor; neighbors) {
                if (!(neighbor.id in visited)) {
                    dfsHelper(neighbor.id, visited, result);
                }
            }
        }
    }
}

import std.container : DList;
