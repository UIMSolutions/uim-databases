# Object Database with D and vibe.d

A flexible object/document database implementation in D language with a REST API powered by vibe.d. Similar to MongoDB or CouchDB, this database stores JSON documents and provides powerful querying capabilities.

## Features

- **JSON Document Storage**: Store any JSON-compatible data structure
- **Multiple Collections**: Organize documents into separate collections (like tables)
- **Rich Querying**: Filter with multiple operators (==, !=, >, <, >=, <=, contains, in, exists)
- **Sorting & Pagination**: Sort results and use limit/skip for pagination
- **Indexing**: Create indexes on fields for faster lookups
- **Bulk Operations**: Insert multiple documents at once
- **Timestamps**: Automatic createdAt and updatedAt tracking
- **REST API**: Full-featured HTTP API on port 8081
- **UUID Generation**: Automatic unique ID generation for documents

## Quick Start

### Prerequisites
- DMD, LDC, or GDC compiler
- DUB (D package manager)

### Running the Object Database Server

```bash
# Using the dedicated config
dub --config=object

# Or run directly
dub run --config=object
```

The server will start on `http://localhost:8081`

## API Endpoints

### Health Check
```bash
GET /health
```

### Collection Management

#### List all collections
```bash
GET /collections
```

#### Create a collection
```bash
POST /collections/:name
```

#### Delete a collection
```bash
DELETE /collections/:name
```

#### Get collection statistics
```bash
GET /collections/:name/stats
```

### Document Operations

#### Insert a document
```bash
POST /collections/:name/documents
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com",
  "age": 30,
  "tags": ["developer", "D"]
}

# Or with custom ID:
{
  "_id": "custom-id-123",
  "name": "John Doe",
  ...
}
```

#### Get a document
```bash
GET /collections/:name/documents/:id
```

#### Update a document
```bash
PUT /collections/:name/documents/:id
Content-Type: application/json

{
  "name": "John Updated",
  "age": 31
}
```

#### Delete a document
```bash
DELETE /collections/:name/documents/:id
```

#### Get all documents
```bash
GET /collections/:name/all
```

### Query Operations

#### Find documents with conditions
```bash
POST /collections/:name/find
Content-Type: application/json

{
  "where": [
    {
      "field": "age",
      "op": ">",
      "value": 25
    },
    {
      "field": "active",
      "op": "==",
      "value": true
    }
  ],
  "sort": {
    "field": "age",
    "ascending": false
  },
  "limit": 10,
  "skip": 0
}
```

**Query Operators:**
- `==` or `equals` - Equality
- `!=` or `not_equals` - Not equal
- `>` or `greater` - Greater than
- `<` or `less` - Less than
- `>=` or `greater_eq` - Greater or equal
- `<=` or `less_eq` - Less or equal
- `contains` - String contains (substring search)
- `in` - Value in array
- `exists` - Field exists (value: true/false)

#### Count documents
```bash
POST /collections/:name/count
Content-Type: application/json

{
  "where": [
    {"field": "active", "op": "==", "value": true}
  ]
}
```

### Index Operations

#### Create an index
```bash
POST /collections/:name/indexes
Content-Type: application/json

{
  "field": "email"
}
```

#### Drop an index
```bash
DELETE /collections/:name/indexes/:field
```

### Bulk Operations

#### Bulk insert
```bash
POST /collections/:name/bulk
Content-Type: application/json

{
  "documents": [
    {"name": "User 1", "age": 25},
    {"name": "User 2", "age": 30},
    {"name": "User 3", "age": 35}
  ]
}
```

#### Clear collection
```bash
DELETE /collections/:name/clear
```

## Usage Examples

### Using cURL

#### Create a collection and insert documents:
```bash
# Create collection
curl -X POST http://localhost:8081/collections/users

# Insert a document
curl -X POST http://localhost:8081/collections/users/documents \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Alice",
    "email": "alice@example.com",
    "age": 28,
    "role": "developer"
  }'
```

#### Query documents:
```bash
# Find users older than 25
curl -X POST http://localhost:8081/collections/users/find \
  -H "Content-Type: application/json" \
  -d '{
    "where": [
      {"field": "age", "op": ">", "value": 25}
    ],
    "sort": {"field": "age", "ascending": true},
    "limit": 5
  }'
```

#### Complex query with multiple conditions:
```bash
curl -X POST http://localhost:8081/collections/users/find \
  -H "Content-Type: application/json" \
  -d '{
    "where": [
      {"field": "age", "op": ">=", "value": 25},
      {"field": "role", "op": "==", "value": "developer"}
    ]
  }'
```

### Using the Example Client

```bash
# Run the example client
rdmd object-example.d
```

This will demonstrate:
- Creating collections
- Inserting documents
- Querying with conditions
- Creating indexes
- Updating documents
- Bulk operations
- And more!

### Using D Code

```d
import std.net.curl;
import vibe.data.json;
import std.stdio;

void main() {
    // Create a document
    Json doc = Json.emptyObject;
    doc["name"] = "Bob";
    doc["email"] = "bob@example.com";
    doc["age"] = 32;
    
    // Insert it
    auto response = post("http://localhost:8081/collections/users/documents",
                        doc.toString(),
                        ["Content-Type": "application/json"]);
    
    writeln("Response: ", response);
}
```

## Architecture

### Components

1. **objectdb.d**: Core database implementation
   - Document storage with UUID generation
   - Query engine with multiple operators
   - Index system for field lookups
   - Sorting and pagination
   - Nested field access with dot notation

2. **objectapp.d**: REST API server
   - Collection management endpoints
   - CRUD operations for documents
   - Query and count operations
   - Index management
   - Bulk operations

### Data Model

Each document is stored with:
- `id`: Unique identifier (auto-generated UUID or custom)
- `data`: The actual JSON document
- `createdAt`: Timestamp of creation
- `updatedAt`: Timestamp of last update

### Query System

The query system supports:
- **Multiple conditions**: All conditions are AND-ed together
- **Nested field access**: Use dot notation like "address.city"
- **Type-aware comparisons**: Proper handling of numbers, strings, booleans
- **Sorting**: Sort by any field in ascending or descending order
- **Pagination**: Skip and limit for efficient data retrieval

### Indexing

Indexes improve query performance:
- Create indexes on frequently queried fields
- Indexes are automatically updated on insert/update/delete
- Simplified implementation using value-to-ID mapping

## Query Examples

### Find by exact match
```json
{
  "where": [
    {"field": "status", "op": "==", "value": "active"}
  ]
}
```

### Range query
```json
{
  "where": [
    {"field": "price", "op": ">=", "value": 10},
    {"field": "price", "op": "<=", "value": 100}
  ]
}
```

### String search
```json
{
  "where": [
    {"field": "description", "op": "contains", "value": "awesome"}
  ]
}
```

### Check field existence
```json
{
  "where": [
    {"field": "email", "op": "exists", "value": true}
  ]
}
```

### Value in array
```json
{
  "where": [
    {"field": "category", "op": "in", "value": ["electronics", "gadgets"]}
  ]
}
```

### Nested field query
```json
{
  "where": [
    {"field": "address.city", "op": "==", "value": "New York"}
  ]
}
```

### Sorted results with pagination
```json
{
  "where": [
    {"field": "age", "op": ">", "value": 18}
  ],
  "sort": {
    "field": "createdAt",
    "ascending": false
  },
  "skip": 20,
  "limit": 10
}
```

## Configuration

The server runs on port **8081** by default (to avoid conflict with the vector database on 8080).

To change the port, modify [source/objectapp.d](source/objectapp.d):
```d
settings.port = 8081;  // Change this
```

## Performance Considerations

- **In-memory storage**: All data is stored in memory (fast but limited by RAM)
- **Linear scan**: Queries perform linear scans (best for < 100k documents)
- **Index support**: Use indexes for frequently queried fields
- **No persistence**: Data is lost on restart (add file/database persistence for production)

## Future Enhancements

- [ ] Persistent storage (JSON files, SQLite, or custom format)
- [ ] Transactions
- [ ] OR conditions in queries
- [ ] Aggregation pipeline
- [ ] Full-text search
- [ ] Schema validation
- [ ] Replication
- [ ] Authentication & authorization
- [ ] WebSocket support for real-time updates
- [ ] Client libraries (Python, JavaScript, etc.)

## Running Both Databases

You can run both the vector database and object database simultaneously:

```bash
# Terminal 1 - Object Database (port 8081)
dub --config=object

# Terminal 2 - Vector Database (port 8080)
dub run
```

## License

MIT License

## Contributing

Contributions welcome! Please submit issues and pull requests.
