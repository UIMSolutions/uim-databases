module uim.databases.graph.query;

import std.algorithm;
import std.array;
import vibe.data.json;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;
import uim.databases.graph.algorithm.traversal;
import uim.databases.graph.algorithm.pathfinding;
import uim.databases.graph.algorithm.centrality;

/// Graph query result
struct QueryResult {
    Node[] nodes;
    Edge[] edges;
    Json data;
    bool success;
    
    Json toJson() {
        auto result = Json.emptyObject;
        result["nodes"] = serializeToJson(nodes.map!(n => n.toJson()).array);
        result["edges"] = serializeToJson(edges.map!(e => e.toJson()).array);
        result["data"] = data;
        result["success"] = success;
        return result;
    }
}

/// Graph query engine
class GraphQueryEngine {
    private {
        GraphStorage _graph;
        TraversalEngine _traversal;
        PathfindingEngine _pathfinding;
        CentralityEngine _centrality;
    }
    
    this(GraphStorage graph) {
        _graph = graph;
        _traversal = new TraversalEngine(graph);
        _pathfinding = new PathfindingEngine(graph);
        _centrality = new CentralityEngine(graph);
    }
    
    /// Query builder
    QueryBuilder query() {
        return new QueryBuilder(this);
    }
    
    /// Execute BFS traversal
    QueryResult traverseBFS(string startNodeId) {
        auto nodes = _traversal.bfs(startNodeId);
        return QueryResult(nodes, [], Json.emptyObject, !nodes.empty);
    }
    
    /// Execute DFS traversal
    QueryResult traverseDFS(string startNodeId) {
        auto nodes = _traversal.dfs(startNodeId);
        return QueryResult(nodes, [], Json.emptyObject, !nodes.empty);
    }
    
    /// Find path between nodes
    QueryResult findPath(string fromNodeId, string toNodeId) {
        auto path = _pathfinding.findShortestPath(fromNodeId, toNodeId);
        
        auto nodes = path.nodeIds
            .map!(id => _graph.getNode(id))
            .filter!(n => n !is null)
            .array;
        
        auto data = Json.emptyObject;
        data["path"] = serializeToJson(path.nodeIds);
        data["cost"] = path.cost;
        
        return QueryResult(nodes, [], data, path.found);
    }
    
    /// Find all paths with length limit
    QueryResult findAllPaths(string fromNodeId, string toNodeId, size_t maxLength) {
        auto paths = _pathfinding.findAllPaths(fromNodeId, toNodeId, maxLength);
        
        auto data = Json.emptyObject;
        data["paths"] = serializeToJson(paths.map!(p => p.toJson()).array);
        data["count"] = paths.length;
        
        return QueryResult([], [], data, !paths.empty);
    }
    
    /// Find connected components
    QueryResult findConnectedComponents() {
        auto components = _traversal.connectedComponents();
        
        auto data = Json.emptyObject;
        auto componentsData = Json.emptyArray;
        foreach (component; components) {
            auto componentData = Json.emptyObject;
            componentData["nodes"] = serializeToJson(component.map!(n => n.id).array);
            componentData["size"] = component.length;
            componentsData ~= componentData;
        }
        data["components"] = componentsData;
        data["count"] = components.length;
        
        return QueryResult([], [], data, components.length > 0);
    }
    
    /// Calculate degree centrality
    QueryResult calculateDegreeCentrality() {
        auto scores = _centrality.degreeCentrality();
        
        auto data = Json.emptyObject;
        auto scoresData = Json.emptyArray;
        foreach (score; scores) {
            scoresData ~= score.toJson();
        }
        data["scores"] = scoresData;
        
        return QueryResult([], [], data, !scores.empty);
    }
    
    /// Calculate betweenness centrality
    QueryResult calculateBetweennessCentrality() {
        auto scores = _centrality.betweennessCentrality();
        
        auto data = Json.emptyObject;
        auto scoresData = Json.emptyArray;
        foreach (score; scores) {
            scoresData ~= score.toJson();
        }
        data["scores"] = scoresData;
        
        return QueryResult([], [], data, !scores.empty);
    }
    
    /// Calculate closeness centrality
    QueryResult calculateClosenessCentrality() {
        auto scores = _centrality.closenessCentrality();
        
        auto data = Json.emptyObject;
        auto scoresData = Json.emptyArray;
        foreach (score; scores) {
            scoresData ~= score.toJson();
        }
        data["scores"] = scoresData;
        
        return QueryResult([], [], data, !scores.empty);
    }
    
    /// Calculate PageRank
    QueryResult calculatePageRank(size_t iterations = 10) {
        auto scores = _centrality.pageRank(iterations);
        
        auto data = Json.emptyObject;
        auto scoresData = Json.emptyArray;
        foreach (score; scores) {
            scoresData ~= score.toJson();
        }
        data["scores"] = scoresData;
        
        return QueryResult([], [], data, !scores.empty);
    }
    
    /// Get neighbors within distance
    QueryResult getNeighborsWithinDistance(string nodeId, size_t distance) {
        auto neighbors = _traversal.neighborsWithinDistance(nodeId, distance);
        return QueryResult(neighbors, [], Json.emptyObject, !neighbors.empty);
    }
}

/// Fluent query builder for graph queries
class QueryBuilder {
    private {
        GraphQueryEngine _engine;
        string _operation;
        Json _filters;
        string[] _edgeTypes;
    }
    
    this(GraphQueryEngine engine) {
        _engine = engine;
        _filters = Json.emptyObject;
    }
    
    /// Traverse using BFS
    QueryBuilder bfs(string startNodeId) {
        _operation = "bfs:" ~ startNodeId;
        return this;
    }
    
    /// Traverse using DFS
    QueryBuilder dfs(string startNodeId) {
        _operation = "dfs:" ~ startNodeId;
        return this;
    }
    
    /// Find path
    QueryBuilder path(string fromNodeId, string toNodeId) {
        _operation = "path:" ~ fromNodeId ~ ":" ~ toNodeId;
        return this;
    }
    
    /// Filter by edge types
    QueryBuilder withEdgeTypes(string[] types) {
        _edgeTypes = types;
        return this;
    }
    
    /// Add filter condition
    QueryBuilder filter(string key, Json value) {
        _filters[key] = value;
        return this;
    }
    
    /// Execute query
    QueryResult execute() {
        if (_operation.length == 0) {
            return QueryResult([], [], Json.emptyObject, false);
        }
        
        import std.string : split;
        auto parts = _operation.split(":");
        
        if (parts[0] == "bfs") {
            return _engine.traverseBFS(parts[1]);
        } else if (parts[0] == "dfs") {
            return _engine.traverseDFS(parts[1]);
        } else if (parts[0] == "path") {
            return _engine.findPath(parts[1], parts[2]);
        }
        
        return QueryResult([], [], Json.emptyObject, false);
    }
}
