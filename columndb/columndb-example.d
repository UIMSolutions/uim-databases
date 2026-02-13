/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module columndb.columndb-example;

import uim.databases.columndb;
import std.stdio;
import std.format;

void main() {
  writeln("=== Column-Based Database Examples ===\n");

  // Example 1: Create Database and Table
  writeln("Example 1: Create Database and Table");
  writeln("---------");
  auto db = new CdbDatabase("retail");
  auto products = db.createTable("products");

  // Add columns
  products.addColumn(new Column("id", ColumnType.INTEGER));
  products.addColumn(new Column("name", ColumnType.STRING));
  products.addColumn(new Column("price", ColumnType.DOUBLE));
  products.addColumn(new Column("quantity", ColumnType.INTEGER));
  products.addColumn(new Column("active", ColumnType.BOOLEAN));

  writeln("Created table 'products' with 5 columns");
  writeln();

  // Example 2: Insert Data
  writeln("Example 2: Insert Data");
  writeln("---------");
  products.insertRow([
    "id": Json(1),
    "name": Json("Widget A"),
    "price": Json(19.99),
    "quantity": Json(100),
    "active": Json(true)
  ]);

  products.insertRow([
    "id": Json(2),
    "name": Json("Gadget B"),
    "price": Json(49.99),
    "quantity": Json(50),
    "active": Json(true)
  ]);

  products.insertRow([
    "id": Json(3),
    "name": Json("Device C"),
    "price": Json(99.99),
    "quantity": Json(25),
    "active": Json(false)
  ]);

  writeln("Inserted 3 products");
  writeln("Total rows: ", products.rowCount());
  writeln();

  // Example 3: Query by Column Value
  writeln("Example 3: Query by Column Value");
  writeln("---------");
  auto indices = products.query("name", Json("Widget A"));
  writeln("Found 'Widget A' at indices: ", indices);

  auto activeIndices = products.query("active", Json(true));
  writeln("Active products at indices: ", activeIndices);
  writeln();

  // Example 4: Get Row Data
  writeln("Example 4: Get Row Data");
  writeln("---------");
  auto row0 = products.getRow(0);
  foreach (colName, value; row0) {
    writeln(format("  %s: %s", colName, value));
  }
  writeln();

  // Example 5: Column Statistics
  writeln("Example 5: Column Statistics");
  writeln("---------");
  auto priceStats = products.getColumnStats("price");
  writeln("Price Statistics:");
  writeln(format("  Type: %s", priceStats.type));
  writeln(format("  Min: %s", priceStats.minValue));
  writeln(format("  Max: %s", priceStats.maxValue));
  writeln(format("  Avg: %s", priceStats.avgValue));
  writeln(format("  Distinct: %s", priceStats.distinctValues));
  writeln();

  // Example 6: Get All Rows
  writeln("Example 6: Get All Rows");
  writeln("---------");
  auto allRows = products.getAllRows();
  foreach (i, row; allRows) {
    writeln(format("Row %d: id=%s, name=%s, price=%s", i, row["id"], row["name"], row["price"]));
  }
  writeln();

  // Example 7: Multiple Tables
  writeln("Example 7: Multiple Tables");
  writeln("---------");
  auto customers = db.createTable("customers");
  customers.addColumn(new Column("id", ColumnType.INTEGER));
  customers.addColumn(new Column("name", ColumnType.STRING));
  customers.addColumn(new Column("email", ColumnType.STRING));

  customers.insertRow(["id": Json(1), "name": Json("Alice"), "email": Json("alice@example.com")]);
  customers.insertRow(["id": Json(2), "name": Json("Bob"), "email": Json("bob@example.com")]);

  writeln("Created 'customers' table");
  writeln("Database tables: ", db.tableNames());
  writeln("Total tables in database: ", db.tableCount());
  writeln();

  // Example 8: Table Information
  writeln("Example 8: Table Information");
  writeln("---------");
  writeln("Products table:");
  writeln(format("  Columns: %s", products.columnNames()));
  writeln(format("  Rows: %s", products.rowCount()));
  writeln(format("  Columns count: %s", products.columnCount()));
  writeln();

  // Example 9: Database Statistics
  writeln("Example 9: Database Statistics");
  writeln("---------");
  auto dbStats = db.getStats();
  writeln(format("Database: %s", dbStats.databaseName));
  writeln(format("Tables: %s", dbStats.tableCount));
  writeln(format("Total Memory: %s bytes", dbStats.totalMemory));
  writeln();

  // Example 10: Column Memory Usage
  writeln("Example 10: Column Memory Usage");
  writeln("---------");
  auto nameCol = products.getColumn("name");
  writeln(format("'name' column memory: %s bytes", nameCol.memoryUsage()));
  writeln();

  writeln("=== Examples Complete ===");
}
