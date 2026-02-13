# Key-Value Store Database (KVStore)

A high-performance, thread-safe key-value database implementation in D with vibe.d REST API support.

## Features

- **In-Memory Store** (`KVStore`): Fast, in-memory key-value storage with metadata tracking
- **Persistent Store** (`PersistentKVStore`): JSON-based persistent storage on disk
- **REST API**: Full HTTP-based API for remote access using vibe.d
- **Bulk Operations**: Support for multi-set and multi-get operations
- **Statistics**: Track store metrics and access patterns
- **Error Handling**: Custom exceptions for robust error management
- **Type-Safe**: Full D language type safety with `@safe` attributes

## Architecture

```
uim/databases/kvstore/
├── classes/          # Store implementations
│   ├── store.d       # In-memory KVStore class
│   └── persistent.d  # File-based persistent store
├── interfaces/       # Interface definitions
│   └── store.d       # IKVStore interface
├── api/              # REST API handlers
│   └── rest.d        # vibe.d REST endpoints
└── errors/           # Custom exceptions
    └── exceptions.d  # Exception classes
```

## Building

### As a Library

```bash
dub build --config=default
```

### As an Executable (Server)

```bash
dub build --config=executable
```

## Running

Start the REST API server:

```bash
dub run --config=executable
```

The server will listen on `http://127.0.0.1:8080`

## Usage Examples

### In-Memory Store

```d
import uim.databases.kvstore;

// Create store
auto store = new KVStore("mystore");

// Set values
store.set("name", "John Doe");
store.set("age", "30");

// Get values
string name = store.get("name");

// Check existence
if (store.exists("email")) {
    string email = store.get("email");
}

// Get all keys
foreach (key; store.keys()) {
    writeln("Key: ", key);
}

// Delete
store.remove("age");

// Clear all
store.clear();
```

### Persistent Store

```d
import uim.databases.kvstore;

// Create persistent store with file path
auto store = new PersistentKVStore("./data/kvstore.json");

// Automatically persists to disk on every write
store.set("username", "alice");
store.set("email", "alice@example.com");

// Data is automatically loaded from disk on initialization
auto value = store.get("username");
```

### REST API

#### Get a value
```bash
curl http://localhost:8080/kvstore/name
```

#### Set a value
```bash
curl -X POST http://localhost:8080/kvstore \
  -H "Content-Type: application/json" \
  -d '{"key": "name", "value": "John"}'
```

#### Check if key exists
```bash
curl http://localhost:8080/kvstore/check/name
```

#### Get all keys
```bash
curl http://localhost:8080/kvstore/keys
```

#### Get store statistics
```bash
curl http://localhost:8080/kvstore/stats
```

#### Delete a key
```bash
curl -X DELETE http://localhost:8080/kvstore/name
```

#### Set multiple values
```bash
curl -X POST http://localhost:8080/kvstore/multi \
  -H "Content-Type: application/json" \
  -d '{
    "pairs": {
      "key1": "value1",
      "key2": "value2",
      "key3": "value3"
    }
  }'
```

#### Get multiple values
```bash
curl -X POST http://localhost:8080/kvstore/multi-get \
  -H "Content-Type: application/json" \
  -d '["key1", "key2", "key3"]'
```

#### Clear all data
```bash
curl -X DELETE http://localhost:8080/kvstore
```

## API Reference

### IKVStore Interface

```d
interface IKVStore {
  string get(string key);                    // Get a value
  void set(string key, string value);        // Set a value
  void remove(string key);                   // Delete a key
  bool exists(string key);                   // Check if key exists
  string[] keys();                           // Get all keys
  size_t count();                            // Get key count
  void clear();                              // Clear all data
  string[string] multiGet(string[] keys);    // Get multiple values
  void multiSet(string[string] pairs);       // Set multiple values
}
```

### Exceptions

- `KeyNotFoundException`: Thrown when a key is not found
- `InvalidOperationException`: Thrown for invalid operations
- `StoreException`: Thrown for general store errors

## Performance Characteristics

### KVStore (In-Memory)
- **Get**: O(1) average
- **Set**: O(1) average
- **Delete**: O(1) average
- **Memory**: Limited by available RAM
- **Persistence**: None (volatile)

### PersistentKVStore (File-Based)
- **Get**: O(1) average (after load)
- **Set**: O(1) + disk write
- **Delete**: O(1) + disk write
- **Memory**: O(n) where n is number of keys
- **Persistence**: JSON format on disk

## Thread Safety

Both store implementations are designed to be used safely but do not include internal locking for concurrent access. For multi-threaded scenarios, external synchronization is recommended.

## Future Enhancements

- [ ] LRU (Least Recently Used) eviction policy
- [ ] TTL (Time-To-Live) support with automatic expiration
- [ ] Compression for persistent storage
- [ ] Database replication
- [ ] Transactions and ACID compliance
- [ ] Indexing and query capabilities
- [ ] Memory-mapped file storage

## Dependencies

- `uim-framework` ~>26.2.2
- `vibe-d` ~>0.9.0

## License

Apache 2.0 - See LICENSE file

## Authors

- Ozan Nurettin Süel (aka UIManufaktur)
