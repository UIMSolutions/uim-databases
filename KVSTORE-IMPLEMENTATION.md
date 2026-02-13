# Key-Value Store Implementation Summary

## Project Overview

A complete, production-ready key-value database implementation in D language with vibe.d REST API support. This module integrates seamlessly with the UIM database framework.

## Directory Structure

```
kvstore/
├── dub.sdl                          # Project configuration
├── dub.selections.json              # Dependency versions
├── LICENSE                          # Apache 2.0 License
├── README.md                        # Full documentation
├── kvstore-example.d               # Usage examples
├── source/
│   ├── app.d                       # REST API server entry point
│   └── uim/databases/kvstore/
│       ├── package.d               # Main module export
│       ├── classes/
│       │   ├── package.d           # Export all classes
│       │   ├── store.d             # In-memory KVStore class
│       │   └── persistent.d        # File-based PersistentKVStore class
│       ├── interfaces/
│       │   ├── package.d           # Export all interfaces
│       │   └── store.d             # IKVStore interface
│       ├── api/
│       │   ├── package.d           # Export API modules
│       │   └── rest.d              # vibe.d REST endpoints
│       └── errors/
│           ├── package.d           # Export exceptions
│           └── exceptions.d        # Exception classes
```

## Core Components

### 1. **Interfaces** (`interfaces/store.d`)
- `IKVStore`: Main interface defining all key-value operations
  - `get(key)` - Retrieve values
  - `set(key, value)` - Store values
  - `remove(key)` - Delete keys
  - `exists(key)` - Check key existence
  - `keys()` - Get all keys
  - `count()` - Get store size
  - `clear()` - Remove all data
  - `multiGet(keys)` - Batch get operations
  - `multiSet(pairs)` - Batch set operations

### 2. **Store Implementations**

#### **KVStore** (`classes/store.d`)
- In-memory storage with O(1) operations
- Metadata tracking (creation time, last access)
- Statistics collection
- No persistence (volatile)
- Ideal for caching and transient data

#### **PersistentKVStore** (`classes/persistent.d`)
- JSON-based file persistence
- Automatic load on initialization
- Automatic save on write operations
- Maintains all data across restarts
- Ideal for configuration and persistent state

### 3. **Error Handling** (`errors/exceptions.d`)
- `KeyNotFoundException` - Key not found
- `InvalidOperationException` - Invalid operations
- `StoreException` - General store errors

### 4. **REST API** (`api/rest.d`)
Complete HTTP API endpoints:
- `GET /kvstore/:key` - Get value
- `POST /kvstore` - Set value
- `DELETE /kvstore/:key` - Delete value
- `GET /kvstore/check/:key` - Check existence
- `GET /kvstore/keys` - List all keys
- `GET /kvstore/stats` - Get statistics
- `POST /kvstore/multi` - Batch set
- `POST /kvstore/multi-get` - Batch get
- `DELETE /kvstore` - Clear store

## Building and Running

### Build as Library
```bash
cd kvstore
dub build --config=default
```

### Build and Run REST Server
```bash
cd kvstore
dub run --config=executable
```

Server starts on `http://127.0.0.1:8080`

## Usage Examples

### Basic In-Memory Usage
```d
import uim.databases.kvstore;

auto store = new KVStore("mystore");
store.set("username", "alice");
string name = store.get("username");
store.remove("username");
```

### Persistent Storage
```d
auto store = new PersistentKVStore("./data.json");
store.set("config", "value");
// Automatically saved to disk
```

### REST API Usage
```bash
# Set a value
curl -X POST http://localhost:8080/kvstore \
  -H "Content-Type: application/json" \
  -d '{"key": "name", "value": "John"}'

# Get a value
curl http://localhost:8080/kvstore/name

# Get all keys
curl http://localhost:8080/kvstore/keys
```

## Integration with UIM Framework

This module follows UIM database framework conventions:
- Uses `uim-framework` dependencies
- Follows naming conventions (IKVStore, KVStore)
- Organized package structure
- Consistent error handling
- Apache 2.0 licensing
- Full documentation

Can be imported and used alongside other UIM database modules:
```d
import uim.databases.kvstore;     // Key-Value Store
import uim.databases.relational;  // Relational Database
import uim.databases.object;      // Object Database
import uim.databases.graph;       // Graph Database
```

## Performance Characteristics

### KVStore
- **Get Operation**: O(1)
- **Set Operation**: O(1)
- **Delete Operation**: O(1)
- **Memory**: O(n) where n = number of keys
- **Persistence**: None

### PersistentKVStore
- **Get Operation**: O(1) after load
- **Set Operation**: O(1) + disk I/O
- **Delete Operation**: O(1) + disk I/O
- **Disk Space**: JSON serialized data
- **Persistence**: Full JSON database

## Dependencies

- `uim-framework @^26.2.2` - UIM framework core
- `vibe-d @^0.9.0` - REST framework and HTTP server

## Features Summary

✅ In-memory key-value storage  
✅ Persistent JSON-based storage  
✅ REST API with vibe.d  
✅ Bulk operations support  
✅ Metadata tracking  
✅ Exception handling  
✅ Type-safe D implementation  
✅ Complete documentation  
✅ Usage examples  
✅ Production-ready code  

## Future Enhancements

- [ ] LRU/LFU eviction policies
- [ ] TTL (Time-To-Live) support
- [ ] Database replication
- [ ] Master-slave synchronization
- [ ] Transactions and ACID compliance
- [ ] Compression algorithms
- [ ] Binary serialization (Msgpack, Protobuf)
- [ ] Cluster support
- [ ] Query indexing
- [ ] Backup and recovery

## License

Apache License 2.0 - See [LICENSE](LICENSE) file

## Authors

- Ozan Nurettin Süel (UI Manufaktur)

---

**Status**: ✅ Complete and production-ready  
**Version**: 1.0.0  
**Last Updated**: 2026-02-13
