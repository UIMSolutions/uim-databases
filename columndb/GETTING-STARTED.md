# Getting Started with Column-Based Database

## 5-Minute Quick Start

### 1. Navigate to columndb
```bash
cd columndb
```

### 2. Build and Run REST API Server
```bash
dub build --config=executable
dub run --config=executable
```

Server starts on `http://127.0.0.1:8081`

### 3. Test with curl

Create a table:
```bash
curl -X POST http://localhost:8081/cdb/table \
  -H "Content-Type: application/json" \
  -d '{
    "tableName": "products",
    "columns": [
      {"name": "id", "type": "INTEGER"},
      {"name": "name", "type": "STRING"},
      {"name": "price", "type": "DOUBLE"}
    ]
  }'
```

Insert data:
```bash
curl -X POST http://localhost:8081/cdb/row \
  -H "Content-Type: application/json" \
  -d '{
    "tableName": "products",
    "row": {"id": 1, "name": "Widget", "price": 19.99}
  }'
```

Get all tables:
```bash
curl http://localhost:8081/cdb/tables
```

---

## 10-Minute Tutorial

### Create Analytics Table

```bash
# Create table with multiple column types
curl -X POST http://localhost:8081/cdb/table \
  -H "Content-Type: application/json" \
  -d '{
    "tableName": "sales",
    "columns": [
      {"name": "transaction_id", "type": "INTEGER"},
      {"name": "product", "type": "STRING"},
      {"name": "amount", "type": "DOUBLE"},
      {"name": "quantity", "type": "INTEGER"},
      {"name": "date", "type": "TIMESTAMP"},
      {"name": "active", "type": "BOOLEAN"}
    ]
  }'
```

### Bulk Insert Data

```bash
curl -X POST http://localhost:8081/cdb/rows \
  -H "Content-Type: application/json" \
  -d '{
    "tableName": "sales",
    "rows": [
      {"transaction_id": 1, "product": "Widget", "amount": 99.99, "quantity": 2, "date": "2026-02-13", "active": true},
      {"transaction_id": 2, "product": "Gadget", "amount": 149.99, "quantity": 1, "date": "2026-02-13", "active": true},
      {"transaction_id": 3, "product": "Device", "amount": 199.99, "quantity": 3, "date": "2026-02-12", "active": false}
    ]
  }'
```

### Query and Analyze

Find all transactions for a product:
```bash
curl -X POST http://localhost:8081/cdb/query \
  -H "Content-Type: application/json" \
  -d '{
    "tableName": "sales",
    "columnName": "product",
    "value": "Widget"
  }'
```

Get statistics for amount column:
```bash
curl http://localhost:8081/cdb/column/sales/amount/stats
```

Get table information:
```bash
curl http://localhost:8081/cdb/table/sales
```

---

## Using as a Library

### Basic Setup

```d
import uim.databases.columndb;
import std.stdio;

void main() {
  // Create database
  auto db = new CdbDatabase("mydb");

  // Create table
  auto table = db.createTable("products");

  // Add columns
  table.addColumn(new Column("id", ColumnType.INTEGER));
  table.addColumn(new Column("name", ColumnType.STRING));
  table.addColumn(new Column("price", ColumnType.DOUBLE));
}
```

### Insert Data

```d
// Insert single row
table.insertRow([
  "id": Json(1),
  "name": Json("Widget"),
  "price": Json(19.99)
]);

// Insert multiple rows
Json[string][] rows = [
  ["id": Json(1), "name": Json("Widget"), "price": Json(19.99)],
  ["id": Json(2), "name": Json("Gadget"), "price": Json(29.99)]
];

foreach (row; rows) {
  table.insertRow(row);
}
```

### Query Data

```d
// Find rows where column matches value
auto indices = table.query("name", Json("Widget"));
writeln("Found at indices: ", indices);

// Get specific row
auto row = table.getRow(0);
foreach (colName, value; row) {
  writeln(colName, ": ", value);
}

// Get all rows
auto allRows = table.getAllRows();
foreach (row; allRows) {
  writeln(row);
}
```

### Analytics and Aggregation

```d
// Calculate sum by column
double totalPrice = 0;
foreach (row; table.getAllRows()) {
  totalPrice += row["price"].get!double;
}
writeln("Total Price: ", totalPrice);

// Get column statistics
auto stats = table.getColumnStats("price");
writeln("Min: ", stats.minValue);
writeln("Max: ", stats.maxValue);
writeln("Avg: ", stats.avgValue);
writeln("Distinct: ", stats.distinctValues);
```

### Filtering and Scanning

```d
// Use column table for advanced operations
auto ctable = cast(CdbTable)table;

// Scan with predicate
auto expensiveIndices = ctable.scan((Json[string] row) {
  return row["price"].get!double > 50.0;
});

foreach (idx; expensiveIndices) {
  auto row = table.getRow(idx);
  writeln("Expensive: ", row["name"], " - $", row["price"]);
}
```

---

## REST API Reference

### Create Table
```
POST /cdb/table
```

```json
{
  "tableName": "products",
  "columns": [
    {"name": "id", "type": "INTEGER"},
    {"name": "name", "type": "STRING"},
    {"name": "price", "type": "DOUBLE"},
    {"name": "active", "type": "BOOLEAN"}
  ]
}
```

### Insert Row
```
POST /cdb/row
```

```json
{
  "tableName": "products",
  "row": {"id": 1, "name": "Widget", "price": 19.99, "active": true}
}
```

### Insert Multiple Rows
```
POST /cdb/rows
```

```json
{
  "tableName": "products",
  "rows": [
    {"id": 1, "name": "Widget", "price": 19.99, "active": true},
    {"id": 2, "name": "Gadget", "price": 29.99, "active": true}
  ]
}
```

### Get Row
```
GET /cdb/row/:table/:index
```

Example: `GET /cdb/row/products/0`

### Query Column
```
POST /cdb/query
```

```json
{
  "tableName": "products",
  "columnName": "name",
  "value": "Widget"
}
```

### Get Column Statistics
```
GET /cdb/column/:table/:name/stats
```

Example: `GET /cdb/column/products/price/stats`

### Get Table Info
```
GET /cdb/table/:name
```

Example: `GET /cdb/table/products`

### List All Tables
```
GET /cdb/tables
```

### Database Statistics
```
GET /cdb/stats
```

### Drop Table
```
DELETE /cdb/table/:name
```

Example: `DELETE /cdb/table/products`

---

## Supported Data Types

| Type | Description | Usage |
|------|-------------|-------|
| INTEGER | 64-bit signed integer | `{"type": "INTEGER"}` |
| DOUBLE | 64-bit floating point | `{"type": "DOUBLE"}` |
| STRING | UTF-8 string | `{"type": "STRING"}` |
| BOOLEAN | True/false value | `{"type": "BOOLEAN"}` |
| TIMESTAMP | Date/time string | `{"type": "TIMESTAMP"}` |

---

## Real-World Examples

### Sales Analytics

```d
auto db = new CdbDatabase("sales");
auto transactions = db.createTable("transactions");

// Add columns
transactions.addColumn(new Column("date", ColumnType.TIMESTAMP));
transactions.addColumn(new Column("region", ColumnType.STRING));
transactions.addColumn(new Column("amount", ColumnType.DOUBLE));
transactions.addColumn(new Column("product", ColumnType.STRING));

// Insert data...

// Aggregate by region
double[string] regionTotal;
foreach (row; transactions.getAllRows()) {
  string region = row["region"].get!string;
  double amount = row["amount"].get!double;
  regionTotal[region] += amount;
}
```

### Time Series Data

```d
auto timeseries = db.createTable("metrics");

// Columns: timestamp, metric_name, value
timeseries.addColumn(new Column("timestamp", ColumnType.TIMESTAMP));
timeseries.addColumn(new Column("metric", ColumnType.STRING));
timeseries.addColumn(new Column("value", ColumnType.DOUBLE));

// Query specific metric
auto cpuIndices = timeseries.query("metric", Json("cpu_usage"));

// Get statistics
auto stats = timeseries.getColumnStats("value");
writeln("CPU Avg: ", stats.avgValue);
```

### User Analytics

```d
auto users = db.createTable("user_events");

users.addColumn(new Column("user_id", ColumnType.INTEGER));
users.addColumn(new Column("event_type", ColumnType.STRING));
users.addColumn(new Column("timestamp", ColumnType.TIMESTAMP));
users.addColumn(new Column("value", ColumnType.DOUBLE));

// Find all login events
auto loginIndices = users.query("event_type", Json("login"));
writeln("Total logins: ", loginIndices.length);
```

---

## Performance Tips

1. **Bulk Operations**: Use `POST /cdb/rows` instead of multiple single inserts
2. **Aggregation**: Process rows in streaming fashion to minimize memory
3. **Statistics**: Cache statistics results if querying frequently
4. **Column Types**: Choose appropriate types for better memory efficiency
5. **Query Results**: Use returned indices to avoid full table scans

---

## Error Handling

```d
try {
  auto col = new Column("amount", ColumnType.DOUBLE);
  col.append(Json("not-a-number"));  // Type error!
} catch (TypeMismatchException e) {
  writeln("Type mismatch: ", e.msg);
}

try {
  auto table = db.getTable("nonexistent");
} catch (TableException e) {
  writeln("Table error: ", e.msg);
}

try {
  auto row = table.getRow(9999);  // Out of bounds
} catch (IndexOutOfBoundsException e) {
  writeln("Index error: ", e.msg);
}
```

---

## Troubleshooting

### Build fails
```bash
dub fetch --cache=user
dub upgrade
```

### Port already in use
Change port in `app.d` line ~28 (default 8081)

### Type mismatch errors
Check column type when inserting: INTEGER vs DOUBLE confusion is common

### Out of memory
Use streaming aggregation instead of `getAllRows()` for large tables

---

## Next Steps

1. Run the examples:
   ```bash
   dub run columndb-example.d
   dub run columndb-advanced-example.d
   ```

2. Integrate into your project

3. Explore advanced features:
   - Predicates with `columnTable.scan()`
   - Statistics gathering
   - Multi-table joins (custom code)

4. Deployment:
   - Build optimized binary
   - Configure endpoints
   - Monitor memory usage

---

**Version**: 1.0.0  
**License**: Apache 2.0  
**Last Updated**: 2026-02-13
