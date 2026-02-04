# Relational Database with D and vibe.d

A full-featured relational database implementation in D language with SQL-like operations and a REST API powered by vibe.d. Similar to SQLite or PostgreSQL, this database provides structured tables with schemas, typed columns, constraints, and JOIN operations.

## Features

- **Typed Columns**: INTEGER, FLOAT, STRING, BOOLEAN, DATE, JSON
- **Constraints**: PRIMARY KEY, UNIQUE, NOT NULL, DEFAULT values, FOREIGN KEY
- **SQL-like Operations**: SELECT, INSERT, UPDATE, DELETE
- **WHERE Clauses**: =, !=, >, <, >=, <=, LIKE, IN, IS NULL, IS NOT NULL
- **JOIN Operations**: INNER JOIN between tables
- **Sorting**: ORDER BY with ASC/DESC
- **Pagination**: LIMIT and OFFSET
- **Schema Management**: Create/drop tables with full schema definition
- **Type Validation**: Automatic validation on insert/update
- **Primary Key Index**: Fast lookups by primary key
- **Timestamps**: Automatic createdAt and updatedAt tracking
- **REST API**: Complete HTTP API on port 8082

## Quick Start

### Prerequisites
- DMD, LDC, or GDC compiler
- DUB (D package manager)

### Running the Relational Database Server

```bash
# Using the dedicated config
dub --config=relational

# The server will start on http://localhost:8082
```

## API Endpoints

### Health Check
```bash
GET /health
GET /stats
```

### Table Management

#### List all tables
```bash
GET /tables
```

#### Create a table
```bash
POST /tables
Content-Type: application/json

{
  "name": "users",
  "columns": [
    {
      "name": "id",
      "type": "INTEGER",
      "nullable": false,
      "primaryKey": true
    },
    {
      "name": "name",
      "type": "STRING",
      "nullable": false
    },
    {
      "name": "email",
      "type": "STRING",
      "nullable": false,
      "unique": true
    },
    {
      "name": "age",
      "type": "INTEGER",
      "nullable": true
    },
    {
      "name": "active",
      "type": "BOOLEAN",
      "nullable": false,
      "default": true
    }
  ],
  "foreignKeys": [
    {
      "column": "department_id",
      "refTable": "departments",
      "refColumn": "id"
    }
  ]
}
```

**Column Types:**
- `INTEGER` / `INT` - Whole numbers
- `FLOAT` / `DOUBLE` / `REAL` - Decimal numbers
- `STRING` / `TEXT` / `VARCHAR` - Text data
- `BOOLEAN` / `BOOL` - True/false values
- `DATE` / `DATETIME` - ISO date strings
- `JSON` - Any JSON data

#### Drop a table
```bash
DELETE /tables/:name
```

#### Get table schema
```bash
GET /tables/:name/schema
```

#### Count rows in table
```bash
GET /tables/:name/count
```

### Data Operations

#### INSERT - Single row
```bash
POST /tables/:name/insert
Content-Type: application/json

{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com",
  "age": 30,
  "active": true
}
```

#### INSERT - Bulk (multiple rows)
```bash
POST /tables/:name/insert
Content-Type: application/json

{
  "rows": [
    {"id": 1, "name": "John", "email": "john@example.com", "age": 30},
    {"id": 2, "name": "Jane", "email": "jane@example.com", "age": 28},
    {"id": 3, "name": "Bob", "email": "bob@example.com", "age": 35}
  ]
}
```

#### SELECT - Query rows
```bash
POST /tables/:name/select
Content-Type: application/json

{
  "columns": ["name", "email", "age"],
  "where": [
    {
      "column": "age",
      "op": ">",
      "value": 25
    },
    {
      "column": "active",
      "op": "=",
      "value": true
    }
  ],
  "orderBy": "age",
  "ascending": false,
  "limit": 10,
  "offset": 0
}
```

**WHERE Operators:**
- `=` - Equals
- `!=` - Not equals
- `>` - Greater than
- `<` - Less than
- `>=` - Greater or equal
- `<=` - Less or equal
- `LIKE` - Pattern matching (use % as wildcard)
- `IN` - Value in array
- `IS NULL` - Check for null
- `IS NOT NULL` - Check for not null

#### UPDATE - Modify rows
```bash
POST /tables/:name/update
Content-Type: application/json

{
  "set": {
    "active": false,
    "updated_note": "deactivated"
  },
  "where": [
    {
      "column": "age",
      "op": "<",
      "value": 18
    }
  ]
}
```

#### DELETE - Remove rows
```bash
POST /tables/:name/delete
Content-Type: application/json

{
  "where": [
    {
      "column": "active",
      "op": "=",
      "value": false
    }
  ]
}
```
**Note:** DELETE requires a WHERE clause for safety.

#### Get by Primary Key
```bash
GET /tables/:name/rows/:pk
```

### JOIN Operations

#### INNER JOIN
```bash
POST /join
Content-Type: application/json

{
  "leftTable": "users",
  "rightTable": "orders",
  "leftColumn": "id",
  "rightColumn": "user_id",
  "leftWhere": [
    {"column": "active", "op": "=", "value": true}
  ],
  "rightWhere": [
    {"column": "amount", "op": ">", "value": 50}
  ]
}
```

Results include columns prefixed with table names:
```json
{
  "rows": [
    {
      "users.id": 1,
      "users.name": "John",
      "users.email": "john@example.com",
      "orders.id": 101,
      "orders.user_id": 1,
      "orders.product": "Widget",
      "orders.amount": 99.99
    }
  ]
}
```

## Usage Examples

### Using cURL

#### Create a table and insert data:
```bash
# Create users table
curl -X POST http://localhost:8082/tables \
  -H "Content-Type: application/json" \
  -d '{
    "name": "users",
    "columns": [
      {"name": "id", "type": "INTEGER", "nullable": false, "primaryKey": true},
      {"name": "name", "type": "STRING", "nullable": false},
      {"name": "email", "type": "STRING", "nullable": false, "unique": true},
      {"name": "age", "type": "INTEGER"}
    ]
  }'

# Insert a user
curl -X POST http://localhost:8082/tables/users/insert \
  -H "Content-Type: application/json" \
  -d '{
    "id": 1,
    "name": "Alice",
    "email": "alice@example.com",
    "age": 28
  }'
```

#### Query with WHERE clause:
```bash
curl -X POST http://localhost:8082/tables/users/select \
  -H "Content-Type: application/json" \
  -d '{
    "columns": ["*"],
    "where": [
      {"column": "age", "op": ">", "value": 25}
    ],
    "orderBy": "age",
    "ascending": true
  }'
```

#### Update rows:
```bash
curl -X POST http://localhost:8082/tables/users/update \
  -H "Content-Type: application/json" \
  -d '{
    "set": {"age": 29},
    "where": [
      {"column": "id", "op": "=", "value": 1}
    ]
  }'
```

#### INNER JOIN example:
```bash
curl -X POST http://localhost:8082/join \
  -H "Content-Type: application/json" \
  -d '{
    "leftTable": "users",
    "rightTable": "orders",
    "leftColumn": "id",
    "rightColumn": "user_id"
  }'
```

### Using the Example Client

```bash
# Run the comprehensive example
rdmd relational-example.d
```

This demonstrates:
- Creating tables with schemas
- Defining foreign keys
- Inserting data (single and bulk)
- SELECT queries with WHERE, ORDER BY
- UPDATE and DELETE operations
- INNER JOIN between tables
- Primary key lookups
- Schema inspection

## SQL Equivalents

### CREATE TABLE
**SQL:**
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY NOT NULL,
    name VARCHAR NOT NULL,
    email VARCHAR UNIQUE NOT NULL,
    age INTEGER,
    active BOOLEAN DEFAULT TRUE
);
```

**REST API:**
```bash
POST /tables
{"name": "users", "columns": [...]}
```

### INSERT
**SQL:**
```sql
INSERT INTO users (id, name, email, age) 
VALUES (1, 'John', 'john@example.com', 30);
```

**REST API:**
```bash
POST /tables/users/insert
{"id": 1, "name": "John", ...}
```

### SELECT
**SQL:**
```sql
SELECT name, email FROM users 
WHERE age > 25 AND active = true 
ORDER BY age DESC 
LIMIT 10 OFFSET 20;
```

**REST API:**
```bash
POST /tables/users/select
{
  "columns": ["name", "email"],
  "where": [
    {"column": "age", "op": ">", "value": 25},
    {"column": "active", "op": "=", "value": true}
  ],
  "orderBy": "age",
  "ascending": false,
  "limit": 10,
  "offset": 20
}
```

### UPDATE
**SQL:**
```sql
UPDATE users SET active = false WHERE age < 18;
```

**REST API:**
```bash
POST /tables/users/update
{
  "set": {"active": false},
  "where": [{"column": "age", "op": "<", "value": 18}]
}
```

### DELETE
**SQL:**
```sql
DELETE FROM users WHERE active = false;
```

**REST API:**
```bash
POST /tables/users/delete
{
  "where": [{"column": "active", "op": "=", "value": false}]
}
```

### JOIN
**SQL:**
```sql
SELECT * FROM users 
INNER JOIN orders ON users.id = orders.user_id;
```

**REST API:**
```bash
POST /join
{
  "leftTable": "users",
  "rightTable": "orders",
  "leftColumn": "id",
  "rightColumn": "user_id"
}
```

## Architecture

### Components

1. **relationaldb.d**: Core database implementation
   - Schema definition with typed columns
   - Table class with row storage
   - WHERE condition evaluation
   - SELECT, INSERT, UPDATE, DELETE operations
   - INNER JOIN implementation
   - Primary key indexing
   - Constraint validation

2. **relationalapp.d**: REST API server
   - Table management endpoints
   - Data operation endpoints
   - JOIN endpoint
   - Type parsing and validation
   - JSON serialization

### Data Model

**Schema:**
- Table name
- Column definitions (name, type, constraints)
- Primary key specification
- Foreign key relationships
- Unique constraints

**Row:**
- JSON data (validated against schema)
- createdAt timestamp
- updatedAt timestamp

### Query Processing

1. **Filtering**: WHERE conditions evaluated row-by-row
2. **Sorting**: ORDER BY on specified column
3. **Pagination**: OFFSET skips rows, LIMIT restricts count
4. **Projection**: SELECT specific columns or *
5. **JOIN**: Nested loop join with condition evaluation

### Constraints

- **PRIMARY KEY**: Unique, indexed, not null
- **UNIQUE**: No duplicate values allowed
- **NOT NULL**: Column must have a value
- **DEFAULT**: Value used if not provided
- **FOREIGN KEY**: Reference to another table (declared but not enforced in current implementation)

## Configuration

The server runs on port **8082** by default.

To change the port, modify [source/relationalapp.d](source/relationalapp.d):
```d
settings.port = 8082;  // Change this
```

## Performance Considerations

- **In-memory storage**: Fast but limited by RAM
- **Linear scans**: WHERE clauses use full table scans (best for < 100k rows)
- **Primary key index**: O(1) lookups by primary key
- **Nested loop joins**: O(n*m) complexity for joins
- **No query optimization**: Queries executed as specified

## Limitations

- Single-threaded (vibe.d handles concurrency)
- No transactions
- No query optimizer
- Foreign keys declared but not enforced
- Simple INNER JOIN only (no LEFT, RIGHT, FULL)
- No aggregate functions (SUM, AVG, COUNT, etc.)
- No GROUP BY
- No subqueries

## Future Enhancements

- [ ] Persistent storage (write-ahead log, B-tree indexes)
- [ ] Foreign key enforcement with CASCADE options
- [ ] LEFT/RIGHT/FULL OUTER JOIN
- [ ] Aggregate functions (SUM, AVG, COUNT, MIN, MAX)
- [ ] GROUP BY and HAVING
- [ ] Subqueries
- [ ] Indexes on non-primary-key columns
- [ ] Query optimizer
- [ ] Transactions (BEGIN, COMMIT, ROLLBACK)
- [ ] Views
- [ ] Triggers
- [ ] User authentication
- [ ] SQL query parser (direct SQL input)

## Running All Three Databases

You can run all three databases simultaneously:

```bash
# Terminal 1 - Vector Database (port 8080)
dub --config=vector

# Terminal 2 - Object Database (port 8081)
dub --config=object

# Terminal 3 - Relational Database (port 8082)
dub --config=relational
```

## License

MIT License

## Contributing

Contributions welcome! Please submit issues and pull requests.
