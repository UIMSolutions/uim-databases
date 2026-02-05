# Graph Database

A high-performance graph database library written in D with vibe.d for REST API support. Implements nodes, edges, graph algorithms, and centrality measures for relationship-based data.

## Features

### Storage
- **Nodes**: Labeled nodes with properties and metadata
- **Edges**: Directed and undirected edges with properties
- **Thread-Safe**: Read-write mutex protection for concurrent access
- **Efficient Lookups**: O(1) node and edge retrieval by ID

### Graph Algorithms
- **Traversal**: BFS (Breadth-first search), DFS (Depth-first search)
- **Pathfinding**: Shortest path, all paths with length limit, path existence check
- **Connectivity**: Connected components, neighbors within distance
- **Centrality Measures**: 
  - Degree centrality (connectivity)
  - Closeness centrality (average distance)
  - Betweenness centrality (shortest path frequency)
  - PageRank (importance distribution)

### Query Engine
- Fluent query builder pattern
- Pattern matching and traversal queries
- Relationship-based queries
- Statistical analysis

### REST API
Complete HTTP endpoints for all operations with JSON request/response format.

### Performance
- Adjacency list representation for efficient neighbor lookup
- O(1) average access time for most operations
- Optimized for social networks, knowledge graphs, recommendation systems

## Directory Structure

```
graph/
├── dub.sdl                  # Package configuration
├── LICENSE                  # Apache 2.0
└── source/
    ├── app.d               # Application entry point
    └── uim/databases/graph/
        ├── package.d       # Main module
        ├── storage/        # Data structures
        │   ├── node.d      # Node implementation
        │   ├── edge.d      # Edge implementation
        │   └── graph.d     # Graph storage engine
        ├── algorithm/      # Graph algorithms
        │   ├── traversal.d # BFS, DFS, components
        │   ├── pathfinding.d # Shortest path, all paths
        │   └── centrality.d # Centrality measures
        ├── query/          # Query execution
        │   └── package.d   # Query engine and builder
        └── api/            # REST API
            └── package.d   # HTTP endpoints
```

## Installation

### Build Library
```bash
cd graph
dub build --build=release
```

### Run Server
```bash
dub run
```

Server will start on `http://localhost:8080`

## Usage Examples

### Create Graph and Nodes

```d
auto graph = new GraphStorage("my-graph");

auto node1 = new Node("Person", Json(["name": "Alice", "age": 30]));
auto node2 = new Node("Person", Json(["name": "Bob", "age": 25]));

auto node1Id = graph.addNode(node1);
auto node2Id = graph.addNode(node2);
```

### Create Relationships

```d
auto edge = new Edge(node1Id, node2Id, "KNOWS", true, 
    Json(["since": "2020"]));
graph.addEdge(edge);
```

### Traverse Graph

```d
auto traversal = new TraversalEngine(graph);

// BFS traversal
auto bfsNodes = traversal.bfs(startNodeId);

// DFS traversal
auto dfsNodes = traversal.dfs(startNodeId);

// Find connected components
auto components = traversal.connectedComponents();
```

### Find Paths

```d
auto pathfinding = new PathfindingEngine(graph);

// Shortest path
auto path = pathfinding.findShortestPath(fromId, toId);
if (path.found) {
    foreach (nodeId; path.nodeIds) {
        // Process node
    }
}

// All paths with limit
auto paths = pathfinding.findAllPaths(fromId, toId, maxLength: 4);
```

### Calculate Centrality

```d
auto centrality = new CentralityEngine(graph);

// Degree centrality
auto degreeScores = centrality.degreeCentrality();

// Closeness centrality
auto closenessScores = centrality.closenessCentrality();

// PageRank
auto pageRankScores = centrality.pageRank(iterations: 10);
```

### Query Engine

```d
auto queryEngine = new GraphQueryEngine(graph);

// Traverse BFS
auto result1 = queryEngine.traverseBFS(startNodeId);

// Find path
auto result2 = queryEngine.findPath(fromId, toId);

// Calculate centrality
auto result3 = queryEngine.calculatePageRank(iterations: 10);

// Get connected components
auto result4 = queryEngine.findConnectedComponents();
```

## REST API Reference

### Node Operations

#### Create Node
```
POST /graph/nodes
Content-Type: application/json

{
  "label": "Person",
  "properties": {
    "name": "Alice",
    "age": 30
  }
}

Response: { "id": "uuid", "message": "Node created" }
```

#### Get Node
```
GET /graph/nodes/{id}

Response: { "id": "uuid", "label": "Person", "properties": {...} }
```

#### List All Nodes
```
GET /graph/nodes

Response: { "nodes": [...], "count": 4 }
```

#### Update Node
```
PUT /graph/nodes/{id}
Content-Type: application/json

{ "name": "Alice Updated", "age": 31 }

Response: { "message": "Node updated" }
```

#### Delete Node
```
DELETE /graph/nodes/{id}

Response: { "message": "Node deleted" }
```

#### Get Node Neighbors
```
GET /graph/nodes/{id}/neighbors

Response: { "neighbors": [...], "count": 3 }
```

#### Get Outgoing Edges
```
GET /graph/nodes/{id}/outgoing

Response: { "edges": [...], "count": 2 }
```

#### Get Incoming Edges
```
GET /graph/nodes/{id}/incoming

Response: { "edges": [...], "count": 1 }
```

### Edge Operations

#### Create Edge
```
POST /graph/edges
Content-Type: application/json

{
  "from": "node-id-1",
  "to": "node-id-2",
  "type": "KNOWS",
  "directed": true,
  "properties": {
    "since": "2020"
  }
}

Response: { "id": "uuid", "message": "Edge created" }
```

#### Get Edge
```
GET /graph/edges/{id}

Response: { "id": "uuid", "type": "KNOWS", "from": "...", "to": "..." }
```

#### List All Edges
```
GET /graph/edges

Response: { "edges": [...], "count": 4 }
```

#### Update Edge
```
PUT /graph/edges/{id}
Content-Type: application/json

{ "since": "2021", "strength": "strong" }

Response: { "message": "Edge updated" }
```

#### Delete Edge
```
DELETE /graph/edges/{id}

Response: { "message": "Edge deleted" }
```

### Query Operations

#### BFS Traversal
```
GET /graph/query/bfs/{nodeId}

Response: { "nodes": [...], "success": true }
```

#### DFS Traversal
```
GET /graph/query/dfs/{nodeId}

Response: { "nodes": [...], "success": true }
```

#### Find Shortest Path
```
GET /graph/query/path/{fromId}/{toId}

Response: {
  "nodes": [...],
  "data": {
    "path": ["id1", "id2", "id3"],
    "cost": 2
  },
  "success": true
}
```

#### Find All Paths
```
GET /graph/query/paths/{fromId}/{toId}?maxLength=4

Response: {
  "data": {
    "paths": [
      { "nodeIds": [...], "cost": 2, "found": true },
      ...
    ],
    "count": 3
  },
  "success": true
}
```

#### Find Connected Components
```
GET /graph/query/components

Response: {
  "data": {
    "components": [
      { "nodes": [...], "size": 4 },
      { "nodes": [...], "size": 2 }
    ],
    "count": 2
  },
  "success": true
}
```

#### Get Neighbors Within Distance
```
GET /graph/query/neighbors/{nodeId}/{distance}

Response: { "nodes": [...], "success": true }
```

### Algorithm Operations

#### Degree Centrality
```
GET /graph/algorithm/degree-centrality

Response: {
  "data": {
    "scores": [
      { "nodeId": "uuid", "score": 0.666 },
      ...
    ]
  }
}
```

#### Betweenness Centrality
```
GET /graph/algorithm/betweenness-centrality

Response: {
  "data": {
    "scores": [
      { "nodeId": "uuid", "score": 0.333 },
      ...
    ]
  }
}
```

#### Closeness Centrality
```
GET /graph/algorithm/closeness-centrality

Response: {
  "data": {
    "scores": [
      { "nodeId": "uuid", "score": 0.75 },
      ...
    ]
  }
}
```

#### PageRank
```
GET /graph/algorithm/pagerank?iterations=10

Response: {
  "data": {
    "scores": [
      { "nodeId": "uuid", "score": 0.25 },
      ...
    ]
  }
}
```

### Statistics

#### Get Graph Statistics
```
GET /graph/stats

Response: {
  "name": "my-graph",
  "nodeCount": 4,
  "edgeCount": 6,
  "directedEdges": 6,
  "undirectedEdges": 0
}
```

## Use Cases

### Social Networks
Track relationships, find mutual connections, identify influential users via PageRank.

```d
// Create people nodes, add KNOWS edges
// Use PageRank to find most influential users
auto scores = centrality.pageRank(iterations: 20);
```

### Knowledge Graphs
Represent concepts and relationships, navigate ontologies, find knowledge paths.

```d
// Create concept nodes with IS_A, PART_OF edges
// Find all paths between concepts (relationships)
auto paths = pathfinding.findAllPaths(concept1, concept2, maxLength: 5);
```

### Recommendation Systems
Model user-item interactions and similarities.

```d
// User -> Item edges, Item -> Item similarity edges
// Find neighbors within distance 2 for recommendations
auto recommendations = traversal.neighborsWithinDistance(userId, distance: 2);
```

### Dependency Analysis
Track software module dependencies, detect cycles.

```d
// Modules as nodes, dependencies as directed edges
// Find connected components for independent modules
auto components = traversal.connectedComponents();
```

### Organizational Hierarchies
Represent reporting structures and team hierarchies.

```d
// Employees as nodes, REPORTS_TO edges
// Find common ancestors for organizational paths
auto ancestors = pathfinding.commonAncestors(emp1, emp2);
```

## Architecture

### Thread Safety
All operations protected by ReadWriteMutex:
- Multiple concurrent readers allowed
- Exclusive access during writes
- No data races or deadlocks

### Memory Efficiency
- Adjacency list representation (minimal space overhead)
- Node/Edge objects cached efficiently
- Lazy cloning for read operations

### Algorithm Complexity
- BFS/DFS: O(V + E) where V = nodes, E = edges
- Shortest Path: O(V + E) using BFS
- Degree Centrality: O(V)
- PageRank: O(iterations * (V + E))
- Connected Components: O(V + E)

## Performance Tips

1. **Large Graphs**: Consider indexing frequently queried properties
2. **Centrality Calculation**: Cache results for read-heavy workloads
3. **Pathfinding**: Limit search depth for deep graphs
4. **Concurrent Access**: Leverage read-write locking for high concurrency

## Dependencies

- D standard library (std)
- vibe.d (~0.9.0) for REST API and JSON handling
- core.sync.rwmutex for thread safety

## License

Apache License 2.0
UIMSolutions

## Examples

Complete examples in `graph-example.d`:
- Create nodes and edges
- BFS and DFS traversal
- Shortest path finding
- All paths enumeration
- Path existence checking
- Connected components
- Degree/Closeness centrality
- PageRank calculation
- Node/Edge filtering
- Graph statistics

Run examples:
```bash
dub run --single graph-example.d
```

## Related Databases

- **OLTP Database**: Transactional system with ACID guarantees
- **OLAP Database**: Analytical system with columnar storage
- **Vector Database**: Embeddings and similarity search

See parent project for complete database suite.
