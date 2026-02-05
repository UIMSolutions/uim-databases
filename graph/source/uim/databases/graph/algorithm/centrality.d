module uim.databases.graph.algorithm.centrality;

import core.sync.rwmutex;
import std.algorithm;
import std.array;
import std.container;
import std.math;
import vibe.data.json;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;

/// Centrality score
struct CentralityScore {
    string nodeId;
    double score;
    
    Json toJson() {
        auto result = Json.emptyObject;
        result["nodeId"] = nodeId;
        result["score"] = score;
        return result;
    }
}

/// Graph centrality operations
class CentralityEngine {
    private {
        GraphStorage _graph;
    }
    
    this(GraphStorage graph) {
        _graph = graph;
    }
    
    /// Calculate degree centrality for all nodes
    CentralityScore[] degreeCentrality() {
        CentralityScore[] scores;
        
        auto allNodes = _graph.getAllNodes();
        auto nodeCount = cast(double)allNodes.length;
        
        foreach (node; allNodes) {
            auto neighbors = _graph.getNeighbors(node.id);
            auto score = nodeCount > 1 ? cast(double)neighbors.length / (nodeCount - 1) : 0.0;
            scores ~= CentralityScore(node.id, score);
        }
        
        return scores;
    }
    
    /// Calculate betweenness centrality for all nodes
    CentralityScore[] betweennessCentrality() {
        CentralityScore[] scores;
        auto allNodes = _graph.getAllNodes();
        auto nodeCount = cast(double)allNodes.length;
        
        double[string] betweenness;
        foreach (node; allNodes) {
            betweenness[node.id] = 0.0;
        }
        
        // For each pair of nodes, find shortest path
        foreach (i, sourceNode; allNodes) {
            auto visited = new bool[string];
            auto queue = DList!string(sourceNode.id);
            auto parent = new string[][string];
            
            visited[sourceNode.id] = true;
            
            while (!queue.empty) {
                auto nodeId = queue.front;
                queue.removeFront();
                
                auto neighbors = _graph.getNeighbors(nodeId);
                foreach (neighbor; neighbors) {
                    if (!(neighbor.id in visited)) {
                        visited[neighbor.id] = true;
                        parent[neighbor.id] = [nodeId];
                        queue.insertBack(neighbor.id);
                    } else if (parent[nodeId].length > 0) {
                        // Check if same level
                        bool sameLevel = false;
                        foreach (p; parent[nodeId]) {
                            auto neighbors2 = _graph.getNeighbors(p);
                            foreach (n; neighbors2) {
                                if (n.id == neighbor.id && p != nodeId) {
                                    sameLevel = true;
                                    break;
                                }
                            }
                        }
                        if (sameLevel) {
                            parent[neighbor.id] ~= nodeId;
                        }
                    }
                }
            }
            
            // Update betweenness
            foreach (targetNode; allNodes) {
                if (targetNode.id != sourceNode.id && targetNode.id in parent) {
                    // Count paths through each node
                    countPathContributions(targetNode.id, sourceNode.id, parent, betweenness);
                }
            }
        }
        
        foreach (node; allNodes) {
            auto score = nodeCount > 2 ? betweenness[node.id] / ((nodeCount - 1) * (nodeCount - 2)) : 0.0;
            scores ~= CentralityScore(node.id, score);
        }
        
        return scores;
    }
    
    /// Calculate closeness centrality for all nodes
    CentralityScore[] closenessCentrality() {
        CentralityScore[] scores;
        auto allNodes = _graph.getAllNodes();
        
        foreach (node; allNodes) {
            double sumDistances = 0.0;
            size_t reachableCount = 0;
            
            auto visited = new bool[string];
            auto queue = DList!string[string];
            queue[node.id] = DList!string();
            visited[node.id] = true;
            
            size_t distance = 0;
            while (!queue.empty && reachableCount < allNodes.length - 1) {
                distance++;
                string[] nextBatch;
                
                foreach (key; queue.byKey()) {
                    auto neighbors = _graph.getNeighbors(key);
                    foreach (neighbor; neighbors) {
                        if (!(neighbor.id in visited)) {
                            visited[neighbor.id] = true;
                            nextBatch ~= neighbor.id;
                            sumDistances += distance;
                            reachableCount++;
                        }
                    }
                }
                
                foreach (key; queue.byKey()) {
                    queue.remove(key);
                }
                
                foreach (n; nextBatch) {
                    queue[n] = DList!string();
                }
            }
            
            auto score = reachableCount > 0 && sumDistances > 0 ? 
                (cast(double)(reachableCount) / sumDistances) : 0.0;
            scores ~= CentralityScore(node.id, score);
        }
        
        return scores;
    }
    
    /// PageRank algorithm
    CentralityScore[] pageRank(size_t iterations = 10, double dampingFactor = 0.85) {
        auto allNodes = _graph.getAllNodes();
        double[string] rank;
        double[string] newRank;
        
        auto initialRank = 1.0 / cast(double)allNodes.length;
        foreach (node; allNodes) {
            rank[node.id] = initialRank;
            newRank[node.id] = (1.0 - dampingFactor) / cast(double)allNodes.length;
        }
        
        for (size_t i = 0; i < iterations; i++) {
            foreach (node; allNodes) {
                newRank[node.id] = (1.0 - dampingFactor) / cast(double)allNodes.length;
            }
            
            foreach (node; allNodes) {
                auto incomingEdges = _graph.getIncomingEdges(node.id);
                foreach (edge; incomingEdges) {
                    auto sourceNode = _graph.getNode(edge.fromNodeId);
                    if (sourceNode !is null) {
                        auto outDegree = _graph.getOutgoingEdges(edge.fromNodeId).length;
                        if (outDegree > 0) {
                            newRank[node.id] += dampingFactor * rank[edge.fromNodeId] / cast(double)outDegree;
                        }
                    }
                }
            }
            
            rank = newRank;
        }
        
        CentralityScore[] scores;
        foreach (node; allNodes) {
            scores ~= CentralityScore(node.id, rank[node.id]);
        }
        
        return scores;
    }
    
    private {
        void countPathContributions(string nodeId, string sourceId, string[][string] parent, ref double[string] betweenness) {
            if (nodeId !in parent || parent[nodeId].length == 0) {
                return;
            }
            
            betweenness[nodeId] += 1.0;
            foreach (p; parent[nodeId]) {
                countPathContributions(p, sourceId, parent, betweenness);
            }
        }
    }
}

import std.container : DList;
