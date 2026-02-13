# Column-Based Database (ColumnDB)

A high-performance, column-oriented database implementation in D with vibe.d REST API support. Optimized for analytical queries and data aggregation.

## Features

- **Column-Oriented Storage**: Data stored by column for better compression and analytical performance
- **Multiple Data Types**: INTEGER, DOUBLE, STRING, BOOLEAN, TIMESTAMP
- **Type Safety**: Full D language type safety with compile-time checking
- **Statistics**: Per-column statistics (min, max, avg, distinct values, nulls)
- **Column-Based Operations**: Efficient column scans and aggregations
- **REST API**: Complete HTTP-based API for remote access using vibe.d
- **Bulk Operations**: Insert multiple rows efficiently
- **Query Capabilities**: Query by value and range scans
- **In-Memory**: Fast in-memory columnar storage
- **Metadata**: Track column types, sizes, and access patterns

## Architecture

```
uim/databases/columndb/
├── classes/         # Implementations
│   ├── column.d     # Column storage
│   ├── table.d      # Table management
│   └── database.d   # Database management
├── interfaces/      # Contracts
│   └── column.d     # Column & Table interfaces
├── api/             # REST endpoints
│   └── rest.d       # vibe.d handlers
└── errors/          # Error types
    └── exceptions.d # Exception classes
```

## Data Types

- `INTEGER` - 64-bit signed integers
- `DOUBLE` - 64-bit floating-point numbers
- `STRING` - UTF-8 strings
- `BOOLEAN` - True/false values
- `TIMESTAMP` - Date/time values

## Building

### As a Library
```bash
cd columndb
dub build --config=default
```

### As an Executable (Server)
```bash
cd columndb
dub build --config=executable
```

## Running

Start the REST API server:
```bash
cd columndb
dub run --config=executable
```

Server listens on `http://127.0.0.1:8081`

## REST API Endpoints

### Create Table
```bash
POST /cdb/table
```
Create a new table with specified columns.

**Request:**
```json
{
  "tableName": "sales",
  "columns": [
    {"name": "id", "type": "INTEGER"},
    {"name": "product", "type": "STRING"},
    {"name": "amount", "type": "DOUBLE"},
    {"name": "date", "type": "TIMESTAMP"},
    {"name": "active", "type": "BOOLEAN"}
  ]
}
```

**Response:**
```json
{
  "success": true,
  "tableName": "sales",
  "columnCount": 5,
  "message": "Table created successfully"
}
```

### Get Table Info
```bash
GET /cdb/table/:name
```

Get information about a table (columns, row count).

**Response:**
```json
{
  "tableName": "sales",
  "columnNames": ["id", "product", "amount", "date", "active"],
  "rowCount": 1000,
  "columnCount": 5
}
```

### List All Tables
```bash
GET /cdb/tables
```

**Response:**
```json
{
  "tables": [
    {"name": "sales", "rows": 1000, "columns": 5},
    {"name": "customers", "rows": 500, "columns": 4}
  ],
  "count": 2
}
```

### Insert Row
```bash
POST /cdb/row
```

Insert a single row into table.

**Request:**
```json
{
  "tableName": "sales",
  "row": {
    "id": 1,
    "product": "Widget",
    "amount": 99.99,
    "date": "2026-02-13",
    "active": true
  }
}
```

### Insert Multiple Rows
```bash
POST /cdb/rows
```

Insert multiple rows at once.

**Request:**
```json
{
  "tableName": "sales",
  "rows": [
    {"id": 1, "product": "Widget", "amount": 99.99, "date": "2026-02-13", "active": true},
    {"id": 2, "product": "Gadget", "amount": 149.99, "date": "2026-02-13", "active": true},
    {"id": 3, "product": "Device", "amount": 199.99, "date": "2026-02-12", "active": false}
  ]
}
```

### Get Row
```bash
GET /cdb/row/:table/:index
```

Get a specific row by index.

**Response:**
```json
{
  "success": true,
  "tableName": "sales",
  "index": 0,
  "row": {
    "id": 1,
    "product": "Widget",
    "amount": 99.99,
    "date": "2026-02-13",
    "active": true
  }
}
```

### Query Column
```bash
POST /cdb/query
```

Find rows where column matches a value.

**Request:**
```json
{
  "tableName": "sales",
  "columnName": "product",
  "value": "Widget"
}
```

**Response:**
```json
{
  "success": true,
  "tableName": "sales",
  "columnName": "product",
  "indices": [0, 5, 12, 18],
  "matchCount": 4
}
```

### Get Column Statistics
```bash
GET /cdb/column/:table/:name/stats
```

Get statistics for a column.

**Response:**
```json
{
  "columnName": "amount",
  "type": "DOUBLE",
  "rowCount": 1000,
  "distinctValues": 487,
  "nullCount": 0,
  "minValue": 10.5,
  "maxValue": 999.99,
  "avgValue": 245.67
}
```

### Database Statistics
```bash
GET /cdb/stats
```

Get overall database statistics.

**Response:**
```json
{
  "databaseName": "analytics",
  "tableCount": 2,
  "tableNames": ["sales", "customers"],
  "totalMemory": 245000
}
```

### Drop Table
```bash
DELETE /cdb/table/:name
```

Remove a table from the database.

## Usage Examples

### Basic Usage - In-Memory Table

```d
import uim.databases.columndb;

void main() {
  // Create database
  auto db = new CdbDatabase("mydb");

  // Create table
  auto table = db.createTable("products");

  // Add columns
  table.addColumn(new Column("id", ColumnType.INTEGER));
  table.addColumn(new Column("name", ColumnType.STRING));
  table.addColumn(new Column("price", ColumnType.DOUBLE));

  // Insert data
  table.insertRow([
    "id": Json(1),
    "name": Json("Widget"),
    "price": Json(19.99)
  ]);

  table.insertRow([
    "id": Json(2),
    "name": Json("Gadget"),
    "price": Json(29.99)
  ]);

  // Query
  auto indices = table.query("name", Json("Widget"));
  writeln("Found at indices: ", indices);

  // Get row
  auto row = table.getRow(0);
  writeln("Row 0: ", row);
}
```

### Analytical Aggregation

```d
// Get all rows for analysis
auto rows = table.getAllRows();

double totalSales = 0;
foreach (row; rows) {
  if ("price" in row) {
    totalSales += row["price"].get!double;
  }
}

writeln("Total Sales: ", totalSales);
```

### Column Statistics

```d
auto stats = table.getColumnStats("price");
writeln("Price Statistics:");
writeln("  Min: ", stats.minValue);
writeln("  Max: ", stats.maxValue);
writeln("  Avg: ", stats.avgValue);
writeln("  Distinct: ", stats.distinctValues);
```

### Scan with Predicate

```d
auto ctable = cast(CdbTable)table;
auto expensiveItems = ctable.scan((Json[string] row) {
  if ("price" in row) {
    return row["price"].get!double > 100.0;
  }
  return false;
});

writeln("Expensive items at indices: ", expensiveItems);
```

## Performance Characteristics

### Time Complexity
- **Insert**: O(1) amortized
- **Query**: O(n) where n = column size
- **Get Row**: O(m) where m = column count
- **Column Scan**: O(n)

### Space Complexity
- **Memory**: O(n*m) where n = rows, m = columns
- **Per Value**: Variable based on data type

### Advantages over Row-Based Storage
- Better compression for numeric columns
- Faster aggregation queries
- Efficient column-specific operations
- Lower memory bandwidth requirements

## Type Safety

All operations are type-safe with compile-time checking:

```d
auto col = new Column("amount", ColumnType.DOUBLE);
col.append(Json(99.99));      // ✓ OK
col.append(Json("text"));     // ✗ Compile-time error
col.append(Json(100));        // ✗ Runtime error (integer != double)
```

## Error Handling

```d
import uim.databases.columndb;

auto db = new CdbDatabase("test");

try {
  auto table = db.getTable("nonexistent");
} catch (TableException e) {
  writeln("Caught: ", e.msg);
}

try {
  auto col = new Column("num", ColumnType.INTEGER);
  col.append(Json("not-a-number"));
} catch (TypeMismatchException e) {
  writeln("Type error: ", e.msg);
}
```

## Memory Management

```d
// Get memory usage
ulong colMemory = column.memoryUsage();
ulong dbMemory = db.getTotalMemory();

// Compression
column.compress();  // (Future: actual compression)
```

## Statistics and Monitoring

```d
// Table stats
auto tableStats = table.getStats();
writeln("Table: ", tableStats.tableName);
writeln("Rows: ", tableStats.rowCount);
writeln("Columns: ", tableStats.columnCount);
writeln("Memory: ", tableStats.totalMemory);

// Database stats
auto dbStats = db.getStats();
writeln("Database: ", dbStats.databaseName);
writeln("Tables: ", dbStats.tableCount);
writeln("Total Memory: ", dbStats.totalMemory);
```

## API Integration

```d
// In your main app
import uim.databases.columndb;
import vibe.d;

auto db = new CdbDatabase("analytics");
auto api = new CdbDatabaseAPI(db);

auto router = new URLRouter;
router.registerRestInterface(api);
// Configure and start server...
```

## Future Enhancements

- [ ] Persistent storage (Parquet, ORC formats)
- [ ] Query optimizer
- [ ] Index support (B-trees, bitmaps)
- [ ] Aggregation pipeline
- [ ] Group-by operations
- [ ] Join operations
- [ ] Compression algorithms
- [ ] Partitioning and bucketing
- [ ] Caching layer
- [ ] Transaction support

## Dependencies

- `uim-framework` ~>26.2.2
- `vibe-d` ~>0.9.0

## License

Apache 2.0 - See LICENSE file

## Authors

- Ozan Nurettin Süel (UI Manufaktur)
