# Vector Database with D and vibe.d

A high-performance vector database implementation in D language with a REST API powered by vibe.d.

## Features

- **Multiple Distance Metrics**: Euclidean, Cosine Similarity, Manhattan, and Dot Product
- **Vector Operations**: Add, update, delete, and search vectors
- **Metadata Support**: Attach and filter by custom metadata
- **k-NN Search**: Find k nearest neighbors efficiently
- **REST API**: Full-featured HTTP API for all operations
- **Thread-safe**: Designed for concurrent access

## Installation

### Prerequisites
- DMD, LDC, or GDC compiler
- DUB (D package manager)

### Setup
```bash
# Clone or navigate to the project directory
cd /home/oz/DEV/D/UIM2026/DATABASES

# Build the project
dub build

# Run the server
dub run
```

The server will start on `http://localhost:8080`

## API Endpoints

### Health Check
```bash
GET /health
```
Returns database status and statistics.

### Add Vector
```bash
POST /vectors
Content-Type: application/json

{
  "id": "vector1",
  "vector": [0.1, 0.2, 0.3, ...],  # 128 dimensions
  "metadata": {
    "category": "example",
    "source": "test"
  }
}
```

### Get Vector
```bash
GET /vectors/:id
```
Retrieve a specific vector by ID.

### Update Vector
```bash
PUT /vectors/:id
Content-Type: application/json

{
  "vector": [0.1, 0.2, 0.3, ...],  # Optional
  "metadata": {                      # Optional
    "category": "updated"
  }
}
```

### Delete Vector
```bash
DELETE /vectors/:id
```

### List All Vectors
```bash
GET /vectors
```
Returns all vector IDs and count.

### Search by Vector
```bash
POST /search
Content-Type: application/json

{
  "vector": [0.1, 0.2, 0.3, ...],  # Query vector
  "k": 10                            # Number of results
}
```

### Search by ID
```bash
POST /search/:id
Content-Type: application/json

{
  "k": 10  # Number of similar vectors to return
}
```

### Get Statistics
```bash
GET /stats
```

### Clear Database
```bash
DELETE /clear
```

## Usage Examples

### Using cURL

#### Add a vector:
```bash
curl -X POST http://localhost:8080/vectors \
  -H "Content-Type: application/json" \
  -d '{
    "id": "vec1",
    "vector": [0.1, 0.2, 0.3, 0.4, 0.5, ...],
    "metadata": {"category": "test"}
  }'
```

#### Search for similar vectors:
```bash
curl -X POST http://localhost:8080/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, 0.4, 0.5, ...],
    "k": 5
  }'
```

#### Get vector by ID:
```bash
curl http://localhost:8080/vectors/vec1
```

### Using D Code

```d
import std.net.curl;
import std.json;
import std.stdio;

void main() {
    // Add a vector
    auto vector = new double[128];
    foreach (i; 0 .. 128) {
        vector[i] = i * 0.01;
    }
    
    JSONValue request = [
        "id": "example1",
        "vector": vector,
        "metadata": ["type": "example"]
    ];
    
    auto response = post("http://localhost:8080/vectors", 
                        request.toString(), 
                        ["Content-Type": "application/json"]);
    writeln(response);
}
```

## Architecture

### Components

1. **vectorops.d**: Core vector operations and distance metrics
   - Euclidean distance
   - Cosine similarity
   - Manhattan distance
   - Dot product
   - Vector normalization

2. **vectordb.d**: Vector database implementation
   - In-memory storage with hash-based indexing
   - k-NN search with linear scan
   - CRUD operations
   - Metadata filtering

3. **app.d**: REST API server using vibe.d
   - HTTP endpoints for all operations
   - JSON request/response handling
   - Error handling and validation

## Configuration

The database is currently configured with:
- **Dimension**: 128 (common for embeddings)
- **Distance Metric**: Cosine similarity
- **Port**: 8080

To change these settings, modify the initialization in `source/app.d`:

```d
db = cast(shared) new VectorDatabase(128, DistanceMetric.COSINE);
```

Available metrics:
- `DistanceMetric.EUCLIDEAN`
- `DistanceMetric.COSINE`
- `DistanceMetric.MANHATTAN`
- `DistanceMetric.DOT_PRODUCT`

## Performance Considerations

- **Current Implementation**: Uses linear scan for searches (O(n))
- **Best For**: Small to medium datasets (< 100k vectors)
- **Future Improvements**: Consider implementing HNSW or IVF for larger datasets

## Development

### Building
```bash
dub build
```

### Running in development mode
```bash
dub run
```

### Testing
```bash
# Run tests (if implemented)
dub test
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Roadmap

- [ ] Persistent storage (file-based or database)
- [ ] HNSW indexing for faster searches
- [ ] Batch operations
- [ ] Vector quantization
- [ ] Authentication and authorization
- [ ] Clustering operations
- [ ] Dimensionality reduction
- [ ] Multi-collection support
- [ ] Python client library
