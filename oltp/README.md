# UIM OLTP Library

Online Transaction Processing (OLTP) library for D language using vibe.d framework.

## Features

### Transaction Management
- **ACID Compliance**: Ensures Atomicity, Consistency, Isolation, and Durability
- **Multiple Isolation Levels**: Support for Read Uncommitted, Read Committed, Repeatable Read, and Serializable
- **Automatic Rollback**: Transaction rollback on errors
- **Transaction States**: Track transaction lifecycle (active, committed, aborted, failed)

### Connection Pooling
- **Thread-Safe**: Mutex-protected connection management
- **Configurable Pool Size**: Set minimum and maximum pool sizes
- **Connection Health Checks**: Automatic ping to verify connection health
- **Pool Statistics**: Monitor pool usage and performance
- **Automatic Cleanup**: Release dead connections

### Query Builder
- **SQL Generation**: Build SELECT, INSERT, UPDATE, DELETE queries
- **Safe Construction**: Prevent SQL injection through parameterization
- **Fluent API**: Chain methods for readable query building
- **WHERE Conditions**: Add multiple conditions with AND logic
- **LIMIT and OFFSET**: Pagination support

### Result Handling
- **Structured Results**: JSON-based result storage
- **Row Iteration**: Easy iteration over query results
- **Error Tracking**: Success/failure status with error messages
- **Affected Rows**: Track number of rows modified

## Installation

Add to your `dub.sdl`:

```sdl
dependency "uim-databases-oltp" path="./oltp"
```

Or to your `dub.json`:

```json
{
  "dependencies": {
    "uim-databases-oltp": {"path": "./oltp"}
  }
}
```

## Quick Start

### Basic Usage

```d
import uim.databases.oltp;

// Create connection pool
auto pool = new ConnectionPool("host=localhost;db=mydb", 10);

// Acquire connection
auto conn = pool.acquire();

// Begin transaction
auto txn = conn.beginTransaction(IsolationLevel.readCommitted);

try {
    // Execute queries
    txn.execute("INSERT INTO users (name) VALUES ('John')");
    txn.commit();
} catch (Exception e) {
    txn.rollback();
} finally {
    pool.release(conn);
}
```

### Using Query Builder

```d
auto query = new Query()
    .table("users")
    .select("id", "name", "email")
    .where("status", "active")
    .limit(10);

auto sql = query.build();
// SELECT id, name, email FROM users WHERE status = 'active' LIMIT 10
```

### Transaction with Multiple Operations

```d
auto conn = pool.acquire();
auto txn = conn.beginTransaction(IsolationLevel.serializable);

try {
    // Debit account
    auto debit = new Query()
        .table("accounts")
        .update(["balance": "balance - 100"])
        .where("account_id", "1");
    txn.execute(debit.build());
    
    // Credit account
    auto credit = new Query()
        .table("accounts")
        .update(["balance": "balance + 100"])
        .where("account_id", "2");
    txn.execute(credit.build());
    
    txn.commit();
} catch (Exception e) {
    txn.rollback();
    throw e;
} finally {
    pool.release(conn);
}
```

## Architecture

### Components

1. **Interfaces**
   - `ITransaction`: Transaction management interface
   - `IConnection`: Database connection interface
   - `IConnectionPool`: Connection pooling interface

2. **Classes**
   - `Transaction`: Transaction implementation with ACID support
   - `Connection`: Database connection wrapper
   - `ConnectionPool`: Thread-safe connection pool
   - `Query`: SQL query builder
   - `QueryResult`: Query result wrapper

### Isolation Levels

- `readUncommitted`: Lowest isolation, allows dirty reads
- `readCommitted`: Prevents dirty reads
- `repeatableRead`: Prevents non-repeatable reads
- `serializable`: Highest isolation, full transaction isolation

## Examples

See [oltp-example.d](../oltp-example.d) for comprehensive examples.

## Integration with vibe.d

This library uses vibe.d for:
- Logging (`vibe.core.log`)
- JSON handling (`vibe.data.json`)
- Asynchronous I/O support

## License

Apache License 2.0

Copyright © 2026, UIM Solutions
