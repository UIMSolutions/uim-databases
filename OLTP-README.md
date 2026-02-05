# UIM OLTP Database

A complete Online Transaction Processing (OLTP) database system built with D and vibe.d.

## Features

### 🗄️ Storage Engine
- **In-Memory Storage**: Fast data access with optional persistence
- **Table Management**: Create, drop, and manage tables
- **Row-Level Operations**: Insert, update, delete, query
- **Indexing**: Automatic indexing on columns for fast lookups
- **Versioning**: Row versioning for MVCC support

### 🔒 Transaction Management
- **ACID Properties**: Full Atomicity, Consistency, Isolation, Durability
- **Isolation Levels**: 
  - Read Uncommitted
  - Read Committed
  - Repeatable Read
  - Serializable
- **Transaction States**: Active, Committed, Aborted, Failed

### 🔐 Concurrency Control
- **Lock Manager**: Sophisticated lock management system
- **Lock Modes**:
  - Shared (read) locks
  - Exclusive (write) locks
  - Intent locks
- **Deadlock Detection**: Prevent and handle deadlocks
- **Timeout Management**: Configurable lock timeouts

### 📝 Write-Ahead Logging (WAL)
- **Durability**: All changes logged before commit
- **Recovery**: Automatic recovery from crashes
- **Checkpoint Support**: Periodic checkpoints for performance
- **Transaction Replay**: Rebuild state from logs

### 🌐 REST API
Full HTTP REST API using vibe.d:

- **Database Operations**
  - `GET /` - Database info
  - `GET /stats` - Database statistics
  - `POST /checkpoint` - Perform checkpoint

- **Table Management**
  - `POST /tables/:tableName` - Create table
  - `DELETE /tables/:tableName` - Drop table
  - `GET /tables` - List all tables

- **Data Operations**
  - `POST /tables/:tableName/rows` - Insert row
  - `GET /tables/:tableName/rows` - Query rows
  - `GET /tables/:tableName/rows/:rowId` - Get specific row
  - `PUT /tables/:tableName/rows/:rowId` - Update row
  - `DELETE /tables/:tableName/rows/:rowId` - Delete row

- **Transactions**
  - `POST /transactions/begin` - Begin transaction
  - `POST /transactions/:txId/commit` - Commit transaction
  - `POST /transactions/:txId/rollback` - Rollback transaction

## Installation

Add to your `dub.sdl`:

```sdl
dependency "uim-databases-oltp" path="./oltp" configuration="library"
```

## Quick Start

### Programmatic Usage

```d
import uim.databases.oltp;
import vibe.data.json;

// Create database
auto db = new OLTPDatabase("mydb");

// Create table
db.createTable("users", ["id", "name", "email"]);

// Begin transaction
auto txn = db.beginTransaction();

try {
    // Insert data
    auto data = Json.emptyObject;
    data["name"] = "Alice";
    data["email"] = "alice@example.com";
    auto rowId = txn.insert("users", data);
    
    // Query data
    auto rows = txn.query("users", "name", "Alice");
    
    // Commit
    txn.commit();
} catch (Exception e) {
    txn.rollback();
}

// Shutdown
db.shutdown();
```

### Running as Server

```bash
# Build and run
cd oltp
dub run

# Or specify database name and port
dub run -- mydb 8080
```

### Using REST API

```bash
# Create table
curl -X POST http://localhost:8080/tables/users \
  -H "Content-Type: application/json" \
  -d '{"columns": ["name", "email", "status"]}'

# Insert row
curl -X POST http://localhost:8080/tables/users/rows \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com", "status": "active"}'

# Query rows
curl http://localhost:8080/tables/users/rows

# Query with filter
curl "http://localhost:8080/tables/users/rows?column=status&value=active"

# Get statistics
curl http://localhost:8080/stats

# Perform checkpoint
curl -X POST http://localhost:8080/checkpoint
```

## Architecture

```
OLTPDatabase
├── StorageEngine
│   ├── Table (with rows and indices)
│   └── Row (versioned data)
├── LockManager
│   └── Lock tracking and compatibility
├── WALLogger
│   └── Write-ahead log persistence
└── REST API
    └── HTTP endpoints via vibe.d
```

## Examples

See [oltp-database-example.d](../oltp-database-example.d) for comprehensive examples including:
- Creating tables
- Insert/Update/Delete operations
- Querying data
- Transaction commit/rollback
- Database statistics
- Checkpoint operations

Run the example:
```bash
dub run --single oltp-database-example.d
```

## Configuration

### Database Options

```d
// Custom data and WAL directories
auto db = new OLTPDatabase("mydb", "./my_data", "./my_wal");

// Custom lock timeout
auto lockManager = new LockManager(30.seconds);

// Custom WAL buffer size
auto walLogger = new WALLogger("./wal", 500, true);
```

### Server Options

```d
// Custom port and bind address
auto api = new OLTPRestAPI(db, 9000, "0.0.0.0");
```

## Performance Considerations

1. **Indexing**: Create indices on frequently queried columns
2. **Batch Operations**: Group multiple operations in single transactions
3. **Checkpoints**: Regular checkpoints prevent WAL growth
4. **Lock Granularity**: Use appropriate isolation levels
5. **Connection Pooling**: For multiple concurrent clients

## Limitations

Current implementation has these limitations:
- In-memory storage (persistence layer is placeholder)
- Simple deadlock detection (not full cycle detection)
- No query optimizer
- Basic index structure (hash-based)
- No cross-table joins
- Limited SQL support (uses direct API calls)

## Future Enhancements

- [ ] Full disk persistence
- [ ] B-tree indices
- [ ] SQL query parser and optimizer
- [ ] Multi-version concurrency control (MVCC)
- [ ] Cross-table joins
- [ ] Replication support
- [ ] Backup and restore
- [ ] Query execution plans

## License

Apache License 2.0

Copyright © 2026, UIM Solutions

## Contributing

This is part of the UIM Databases project. Contributions are welcome!
