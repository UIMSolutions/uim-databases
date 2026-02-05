module uim.databases.graph.api;

import vibe.http.router;
import vibe.http.server;
import vibe.core.log;
import vibe.data.json;
import std.algorithm;
import std.array;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;
import uim.databases.graph.query;

/// Graph REST API
class GraphRestAPI {
    private {
        GraphStorage _graph;
        GraphQueryEngine _queryEngine;
        Router _router;
    }
    
    this(GraphStorage graph) {
        _graph = graph;
        _queryEngine = new GraphQueryEngine(graph);
        _router = new Router();
        setupRoutes();
    }
    
    /// Get router
    @property Router router() {
        return _router;
    }
    
    private {
        void setupRoutes() {
            // Node endpoints
            _router.get("/graph/nodes", &handleGetNodes);
            _router.get("/graph/nodes/:id", &handleGetNode);
            _router.post("/graph/nodes", &handleCreateNode);
            _router.put("/graph/nodes/:id", &handleUpdateNode);
            _router.delete_("/graph/nodes/:id", &handleDeleteNode);
            _router.get("/graph/nodes/:id/neighbors", &handleGetNeighbors);
            _router.get("/graph/nodes/:id/outgoing", &handleGetOutgoingEdges);
            _router.get("/graph/nodes/:id/incoming", &handleGetIncomingEdges);
            
            // Edge endpoints
            _router.get("/graph/edges", &handleGetEdges);
            _router.get("/graph/edges/:id", &handleGetEdge);
            _router.post("/graph/edges", &handleCreateEdge);
            _router.put("/graph/edges/:id", &handleUpdateEdge);
            _router.delete_("/graph/edges/:id", &handleDeleteEdge);
            
            // Query endpoints
            _router.get("/graph/query/bfs/:nodeId", &handleBFS);
            _router.get("/graph/query/dfs/:nodeId", &handleDFS);
            _router.get("/graph/query/path/:fromId/:toId", &handleFindPath);
            _router.get("/graph/query/paths/:fromId/:toId", &handleFindAllPaths);
            _router.get("/graph/query/components", &handleConnectedComponents);
            _router.get("/graph/query/neighbors/:nodeId/:distance", &handleNeighborsWithinDistance);
            
            // Algorithm endpoints
            _router.get("/graph/algorithm/degree-centrality", &handleDegreeCentrality);
            _router.get("/graph/algorithm/betweenness-centrality", &handleBetweennessCentrality);
            _router.get("/graph/algorithm/closeness-centrality", &handleClosenessCentrality);
            _router.get("/graph/algorithm/pagerank", &handlePageRank);
            
            // Statistics endpoint
            _router.get("/graph/stats", &handleGetStats);
        }
        
        // Node handlers
        void handleGetNodes(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodes = _graph.getAllNodes();
                auto result = Json.emptyObject;
                result["nodes"] = serializeToJson(nodes.map!(n => n.toJson()).array);
                result["count"] = nodes.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetNode(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                auto node = _graph.getNode(nodeId);
                if (node is null) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Node not found"]);
                    return;
                }
                res.writeJsonBody(node.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleCreateNode(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto body_ = req.json;
                auto label = body_.get!string("label", "");
                auto props = body_.get!Json("properties", Json.emptyObject);
                
                auto node = new Node(label, props);
                auto nodeId = _graph.addNode(node);
                
                auto result = Json.emptyObject;
                result["id"] = nodeId;
                result["message"] = "Node created";
                res.statusCode = 201;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleUpdateNode(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                auto body_ = req.json;
                
                if (!_graph.updateNode(nodeId, body_)) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Node not found"]);
                    return;
                }
                
                auto result = Json.emptyObject;
                result["message"] = "Node updated";
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleDeleteNode(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                
                if (!_graph.deleteNode(nodeId)) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Node not found"]);
                    return;
                }
                
                auto result = Json.emptyObject;
                result["message"] = "Node deleted";
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetNeighbors(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                auto neighbors = _graph.getNeighbors(nodeId);
                
                auto result = Json.emptyObject;
                result["neighbors"] = serializeToJson(neighbors.map!(n => n.toJson()).array);
                result["count"] = neighbors.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetOutgoingEdges(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                auto edges = _graph.getOutgoingEdges(nodeId);
                
                auto result = Json.emptyObject;
                result["edges"] = serializeToJson(edges.map!(e => e.toJson()).array);
                result["count"] = edges.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetIncomingEdges(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["id"];
                auto edges = _graph.getIncomingEdges(nodeId);
                
                auto result = Json.emptyObject;
                result["edges"] = serializeToJson(edges.map!(e => e.toJson()).array);
                result["count"] = edges.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        // Edge handlers
        void handleGetEdges(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto edges = _graph.getAllEdges();
                auto result = Json.emptyObject;
                result["edges"] = serializeToJson(edges.map!(e => e.toJson()).array);
                result["count"] = edges.length;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetEdge(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto edgeId = req.params["id"];
                auto edge = _graph.getEdge(edgeId);
                if (edge is null) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Edge not found"]);
                    return;
                }
                res.writeJsonBody(edge.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleCreateEdge(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto body_ = req.json;
                auto fromId = body_.get!string("from", "");
                auto toId = body_.get!string("to", "");
                auto type = body_.get!string("type", "RELATES_TO");
                auto directed = body_.get!bool("directed", true);
                auto props = body_.get!Json("properties", Json.emptyObject);
                
                auto edge = new Edge(fromId, toId, type, directed, props);
                auto edgeId = _graph.addEdge(edge);
                
                auto result = Json.emptyObject;
                result["id"] = edgeId;
                result["message"] = "Edge created";
                res.statusCode = 201;
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleUpdateEdge(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto edgeId = req.params["id"];
                auto body_ = req.json;
                
                if (!_graph.updateEdge(edgeId, body_)) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Edge not found"]);
                    return;
                }
                
                auto result = Json.emptyObject;
                result["message"] = "Edge updated";
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 400;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleDeleteEdge(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto edgeId = req.params["id"];
                
                if (!_graph.deleteEdge(edgeId)) {
                    res.statusCode = 404;
                    res.writeJson(["error": "Edge not found"]);
                    return;
                }
                
                auto result = Json.emptyObject;
                result["message"] = "Edge deleted";
                res.writeJsonBody(result);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        // Query handlers
        void handleBFS(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["nodeId"];
                auto result = _queryEngine.traverseBFS(nodeId);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleDFS(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["nodeId"];
                auto result = _queryEngine.traverseDFS(nodeId);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleFindPath(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto fromId = req.params["fromId"];
                auto toId = req.params["toId"];
                auto result = _queryEngine.findPath(fromId, toId);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleFindAllPaths(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto fromId = req.params["fromId"];
                auto toId = req.params["toId"];
                auto maxLength = req.query.get("maxLength", "5").to!size_t;
                auto result = _queryEngine.findAllPaths(fromId, toId, maxLength);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleConnectedComponents(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto result = _queryEngine.findConnectedComponents();
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleNeighborsWithinDistance(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto nodeId = req.params["nodeId"];
                auto distance = req.params["distance"].to!size_t;
                auto result = _queryEngine.getNeighborsWithinDistance(nodeId, distance);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        // Algorithm handlers
        void handleDegreeCentrality(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto result = _queryEngine.calculateDegreeCentrality();
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleBetweennessCentrality(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto result = _queryEngine.calculateBetweennessCentrality();
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleClosenessCentrality(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto result = _queryEngine.calculateClosenessCentrality();
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handlePageRank(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto iterations = req.query.get("iterations", "10").to!size_t;
                auto result = _queryEngine.calculatePageRank(iterations);
                res.writeJsonBody(result.toJson());
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
        
        void handleGetStats(HTTPServerRequest req, HTTPServerResponse res) {
            try {
                auto stats = _graph.getStatistics();
                res.writeJsonBody(stats);
            } catch (Exception e) {
                res.statusCode = 500;
                res.writeJson(["error": e.msg]);
            }
        }
    }
}

import vibe.http.server;
import vibe.http.router;
import std.conv : to;
