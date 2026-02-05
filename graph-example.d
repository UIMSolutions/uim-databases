/// Graph Database Examples
/// Demonstrates all features of the graph database system

import std.stdio;
import std.array;
import std.algorithm;
import vibe.data.json;
import uim.databases.graph;

void main() {
    writeln("=== Graph Database Examples ===\n");
    
    // Example 1: Create graph and nodes
    writeln("Example 1: Create graph and nodes");
    auto graph = new GraphStorage("social-network");
    
    auto alice = new Node("Person", Json(["name": "Alice", "age": 30]));
    auto bob = new Node("Person", Json(["name": "Bob", "age": 25]));
    auto charlie = new Node("Person", Json(["name": "Charlie", "age": 35]));
    auto diana = new Node("Person", Json(["name": "Diana", "age": 28]));
    
    auto aliceId = graph.addNode(alice);
    auto bobId = graph.addNode(bob);
    auto charlieId = graph.addNode(charlie);
    auto dianaId = graph.addNode(diana);
    
    writef("Created 4 nodes\n");
    writef("Alice ID: %s\n", aliceId);
    writef("Bob ID: %s\n\n", bobId);
    
    // Example 2: Create edges
    writeln("Example 2: Create relationships (edges)");
    auto edge1 = new Edge(aliceId, bobId, "KNOWS", true, Json(["since": "2020"]));
    auto edge2 = new Edge(bobId, charlieId, "KNOWS", true, Json(["since": "2019"]));
    auto edge3 = new Edge(charlieId, dianaId, "KNOWS", true, Json(["since": "2021"]));
    auto edge4 = new Edge(aliceId, dianaId, "WORKS_WITH", true, Json(["project": "AI"]));
    
    graph.addEdge(edge1);
    graph.addEdge(edge2);
    graph.addEdge(edge3);
    graph.addEdge(edge4);
    
    writef("Created 4 edges\n");
    writef("Graph has %d nodes and %d edges\n\n", graph.nodeCount, graph.edgeCount);
    
    // Example 3: Get node neighbors
    writeln("Example 3: Get node neighbors");
    auto neighbors = graph.getNeighbors(aliceId);
    writef("Alice's neighbors: ");
    foreach (neighbor; neighbors) {
        writef("%s ", neighbor.getProperty("name").get!string);
    }
    writef("\n\n");
    
    // Example 4: Get outgoing and incoming edges
    writeln("Example 4: Get outgoing and incoming edges");
    auto outgoing = graph.getOutgoingEdges(aliceId);
    writef("Alice's outgoing edges: %d\n", outgoing.length);
    foreach (edge; outgoing) {
        writef("  %s -[%s]-> %s\n", edge.fromNodeId, edge.type, edge.toNodeId);
    }
    writef("\n");
    
    // Example 5: Breadth-first search
    writeln("Example 5: Breadth-first search (BFS)");
    auto traversal = new TraversalEngine(graph);
    auto bfsResult = traversal.bfs(aliceId);
    writef("BFS from Alice: ");
    foreach (node; bfsResult) {
        writef("%s ", node.getProperty("name").get!string);
    }
    writef("\n\n");
    
    // Example 6: Depth-first search
    writeln("Example 6: Depth-first search (DFS)");
    auto dfsResult = traversal.dfs(aliceId);
    writef("DFS from Alice: ");
    foreach (node; dfsResult) {
        writef("%s ", node.getProperty("name").get!string);
    }
    writef("\n\n");
    
    // Example 7: Find shortest path
    writeln("Example 7: Find shortest path");
    auto pathfinding = new PathfindingEngine(graph);
    auto path = pathfinding.findShortestPath(aliceId, charlieId);
    writef("Shortest path from Alice to Charlie: ");
    foreach (nodeId; path.nodeIds) {
        auto node = graph.getNode(nodeId);
        writef("%s -> ", node.getProperty("name").get!string);
    }
    writef("\b\b \nPath cost: %f\n\n", path.cost);
    
    // Example 8: Find all paths
    writeln("Example 8: Find all paths with length limit");
    auto paths = pathfinding.findAllPaths(aliceId, dianaId, 4);
    writef("Found %d paths from Alice to Diana\n", paths.length);
    foreach (i, p; paths) {
        writef("  Path %d: ", i + 1);
        foreach (nodeId; p.nodeIds) {
            auto node = graph.getNode(nodeId);
            writef("%s ", node.getProperty("name").get!string);
        }
        writef("(cost: %f)\n", p.cost);
    }
    writef("\n");
    
    // Example 9: Check path existence
    writeln("Example 9: Check path existence");
    bool pathExists = traversal.pathExists(aliceId, charlieId);
    writef("Path exists from Alice to Charlie: %s\n\n", pathExists);
    
    // Example 10: Get connected components
    writeln("Example 10: Find connected components");
    auto components = traversal.connectedComponents();
    writef("Found %d connected components\n", components.length);
    foreach (i, component; components) {
        writef("  Component %d: ", i + 1);
        foreach (node; component) {
            writef("%s ", node.getProperty("name").get!string);
        }
        writef("(%d nodes)\n", component.length);
    }
    writef("\n");
    
    // Example 11: Find neighbors within distance
    writeln("Example 11: Find neighbors within distance");
    auto nearby = traversal.neighborsWithinDistance(aliceId, 2);
    writef("Neighbors within distance 2 from Alice: ");
    foreach (node; nearby) {
        writef("%s ", node.getProperty("name").get!string);
    }
    writef("\n\n");
    
    // Example 12: Degree centrality
    writeln("Example 12: Calculate degree centrality");
    auto centrality = new CentralityEngine(graph);
    auto degreeScores = centrality.degreeCentrality();
    writef("Degree Centrality:\n");
    foreach (score; degreeScores) {
        auto node = graph.getNode(score.nodeId);
        writef("  %s: %.3f\n", node.getProperty("name").get!string, score.score);
    }
    writef("\n");
    
    // Example 13: Closeness centrality
    writeln("Example 13: Calculate closeness centrality");
    auto closenessScores = centrality.closenessCentrality();
    writef("Closeness Centrality:\n");
    foreach (score; closenessScores) {
        auto node = graph.getNode(score.nodeId);
        writef("  %s: %.3f\n", node.getProperty("name").get!string, score.score);
    }
    writef("\n");
    
    // Example 14: PageRank
    writeln("Example 14: Calculate PageRank");
    auto pageRankScores = centrality.pageRank(10);
    writef("PageRank (10 iterations):\n");
    foreach (score; pageRankScores) {
        auto node = graph.getNode(score.nodeId);
        writef("  %s: %.4f\n", node.getProperty("name").get!string, score.score);
    }
    writef("\n");
    
    // Example 15: Find nodes by label
    writeln("Example 15: Find nodes by label");
    auto personNodes = graph.findNodesByLabel("Person");
    writef("Found %d Person nodes\n", personNodes.length);
    foreach (node; personNodes) {
        writef("  %s (age: %d)\n", 
            node.getProperty("name").get!string,
            node.getProperty("age").get!int);
    }
    writef("\n");
    
    // Example 16: Find edges by type
    writeln("Example 16: Find edges by type");
    auto knowsEdges = graph.findEdgesByType("KNOWS");
    writef("Found %d KNOWS relationships\n\n", knowsEdges.length);
    
    // Example 17: Update node properties
    writeln("Example 17: Update node properties");
    auto aliceUpdated = Json(["name": "Alice", "age": 31, "city": "New York"]);
    graph.updateNode(aliceId, aliceUpdated);
    auto updatedAlice = graph.getNode(aliceId);
    writef("Updated Alice's age to: %d\n", updatedAlice.getProperty("age").get!int);
    writef("Updated Alice's city to: %s\n\n", updatedAlice.getProperty("city").get!string);
    
    // Example 18: Update edge properties
    writeln("Example 18: Update edge properties");
    auto allEdges = graph.getAllEdges();
    if (!allEdges.empty) {
        auto edgeToUpdate = allEdges[0];
        auto updatedProps = Json(["since": "2021", "strength": "strong"]);
        graph.updateEdge(edgeToUpdate.id, updatedProps);
        auto updated = graph.getEdge(edgeToUpdate.id);
        writef("Updated edge: %s\n\n", updated.getProperty("strength").get!string);
    }
    
    // Example 19: Graph statistics
    writeln("Example 19: Graph statistics");
    auto stats = graph.getStatistics();
    writef("Graph Statistics:\n");
    writef("  Name: %s\n", stats["name"].get!string);
    writef("  Nodes: %d\n", stats["nodeCount"].get!long);
    writef("  Edges: %d\n", stats["edgeCount"].get!long);
    writef("  Directed: %d\n", stats["directedEdges"].get!long);
    writef("  Undirected: %d\n\n", stats["undirectedEdges"].get!long);
    
    // Example 20: Delete nodes and edges
    writeln("Example 20: Delete nodes and edges");
    auto tempNode = new Node("Temporary", Json.emptyObject);
    auto tempId = graph.addNode(tempNode);
    writef("Created temporary node: %s\n", tempId);
    writef("Graph now has %d nodes\n", graph.nodeCount);
    
    graph.deleteNode(tempId);
    writef("After deletion: %d nodes\n\n", graph.nodeCount);
    
    writeln("=== Examples Complete ===");
}
