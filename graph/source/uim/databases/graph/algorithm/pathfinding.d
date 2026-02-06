/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.graph.algorithm.pathfinding;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import std.container;
import std.math;
import vibe.data.json;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;

/// Path result
struct Path {
    string[] nodeIds;
    double cost;
    bool found;
    
    Json toJson() {
        auto result = Json.emptyObject;
        result["nodeIds"] = serializeToJson(nodeIds);
        result["cost"] = cost;
        result["found"] = found;
        return result;
    }
}

/// Graph pathfinding operations
class PathfindingEngine {
    private {
        GraphStorage _graph;
    }
    
    this(GraphStorage graph) {
        _graph = graph;
    }
    
    /// Find shortest path using breadth-first search
    Path findShortestPath(string startNodeId, string endNodeId) {
        if (startNodeId == endNodeId) {
            return Path([startNodeId], 0, true);
        }
        
        auto visited = new bool[string];
        auto queue = DList!string();
        queue.insertBack(startNodeId);
        auto parent = new string[string];
        
        visited[startNodeId] = true;
        
        while (!queue.empty) {
            auto nodeId = queue.front;
            queue.removeFront();
            
            if (nodeId == endNodeId) {
                // Reconstruct path
                string[] path;
                string current = endNodeId;
                while (current in parent) {
                    path = current ~ path;
                    current = parent[current];
                }
                path = startNodeId ~ path;
                
                return Path(path, cast(double)path.length - 1, true);
            }
            
            auto neighbors = _graph.getNeighbors(nodeId);
            foreach (neighbor; neighbors) {
                if (!(neighbor.id in visited)) {
                    visited[neighbor.id] = true;
                    parent[neighbor.id] = nodeId;
                    queue.insertBack(neighbor.id);
                }
            }
        }
        
        return Path([], double.nan, false);
    }
    
    /// Find all paths with length limit
    Path[] findAllPaths(string startNodeId, string endNodeId, size_t maxLength) {
        Path[] paths;
        
        void dfs(string current, string[] currentPath, bool[string] visited) {
            if (current == endNodeId) {
                paths ~= Path(currentPath, cast(double)currentPath.length - 1, true);
                return;
            }
            
            if (currentPath.length >= maxLength) {
                return;
            }
            
            auto neighbors = _graph.getNeighbors(current);
            foreach (neighbor; neighbors) {
                if (!(neighbor.id in visited)) {
                    auto newVisited = visited.dup;
                    newVisited[neighbor.id] = true;
                    dfs(neighbor.id, currentPath ~ neighbor.id, newVisited);
                }
            }
        }
        
        auto visited = new bool[string];
        visited[startNodeId] = true;
        dfs(startNodeId, [startNodeId], visited);
        
        return paths;
    }
    
    /// Find path by relationship types
    Path findPathWithEdgeTypes(string startNodeId, string endNodeId, string[] edgeTypes) {
        if (startNodeId == endNodeId) {
            return Path([startNodeId], 0, true);
        }
        
        auto visited = new bool[string];
        auto queue = DList!string();
        queue.insertBack(startNodeId);
        auto parent = new string[string];
        
        visited[startNodeId] = true;
        
        while (!queue.empty) {
            auto nodeId = queue.front;
            queue.removeFront();
            
            if (nodeId == endNodeId) {
                // Reconstruct path
                string[] path;
                string current = endNodeId;
                while (current in parent) {
                    path = current ~ path;
                    current = parent[current];
                }
                path = startNodeId ~ path;
                
                return Path(path, cast(double)path.length - 1, true);
            }
            
            auto outEdges = _graph.getOutgoingEdges(nodeId);
            foreach (edge; outEdges) {
                auto hasType = false;
                foreach (t; edgeTypes) {
                    if (edge.type == t) {
                        hasType = true;
                        break;
                    }
                }
                
                if (hasType && !(edge.toNodeId in visited)) {
                    visited[edge.toNodeId] = true;
                    parent[edge.toNodeId] = nodeId;
                    queue.insertBack(edge.toNodeId);
                }
            }
        }
        
        return Path([], double.nan, false);
    }
    
    /// Get common ancestors
    string[] commonAncestors(string nodeId1, string nodeId2) {
        // Use reverse BFS to find ancestors
        auto ancestors1 = new bool[string];
        auto ancestors2 = new bool[string];
        
        auto visited1 = new bool[string];
        auto queue1 = DList!string();
        queue1.insertBack(nodeId1);
        visited1[nodeId1] = true;
        ancestors1[nodeId1] = true;
        
        while (!queue1.empty) {
            auto nodeId = queue1.front;
            queue1.removeFront();
            
            auto inEdges = _graph.getIncomingEdges(nodeId);
            foreach (edge; inEdges) {
                auto parentId = edge.fromNodeId;
                if (!(parentId in visited1)) {
                    visited1[parentId] = true;
                    ancestors1[parentId] = true;
                    queue1.insertBack(parentId);
                }
            }
        }
        
        auto visited2 = new bool[string];
        auto queue2 = DList!string();
        queue2.insertBack(nodeId2);
        visited2[nodeId2] = true;
        
        while (!queue2.empty) {
            auto nodeId = queue2.front;
            queue2.removeFront();
            
            if (nodeId in ancestors1) {
                ancestors2[nodeId] = true;
            }
            
            auto inEdges = _graph.getIncomingEdges(nodeId);
            foreach (edge; inEdges) {
                auto parentId = edge.fromNodeId;
                if (!(parentId in visited2)) {
                    visited2[parentId] = true;
                    if (parentId in ancestors1) {
                        ancestors2[parentId] = true;
                    }
                    queue2.insertBack(parentId);
                }
            }
        }
        
        return ancestors2.byKey().array;
    }
}

import std.container : DList;
