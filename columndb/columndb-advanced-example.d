/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module columndb.columndb-advanced-example;

import uim.databases.columndb;
import std.stdio;
import std.format;
import std.algorithm;

void main() {
  writeln("=== Column-Based Database Advanced Examples ===\n");

  // Setup: Create analytics database with sales data
  auto db = new CdbDatabase("analytics");
  auto sales = db.createTable("sales");

  // Define schema
  sales.addColumn(new Column("transaction_id", ColumnType.INTEGER));
  sales.addColumn(new Column("product_name", ColumnType.STRING));
  sales.addColumn(new Column("sale_amount", ColumnType.DOUBLE));
  sales.addColumn(new Column("quantity", ColumnType.INTEGER));
  sales.addColumn(new Column("region", ColumnType.STRING));
  sales.addColumn(new Column("timestamp", ColumnType.TIMESTAMP));

  // Insert sample data
  sales.insertRow([
    "transaction_id": Json(1000),
    "product_name": Json("Widget"),
    "sale_amount": Json(99.99),
    "quantity": Json(2),
    "region": Json("North"),
    "timestamp": Json("2026-02-13T10:00:00")
  ]);

  sales.insertRow([
    "transaction_id": Json(1001),
    "product_name": Json("Gadget"),
    "sale_amount": Json(149.99),
    "quantity": Json(1),
    "region": Json("South"),
    "timestamp": Json("2026-02-13T11:30:00")
  ]);

  sales.insertRow([
    "transaction_id": Json(1002),
    "product_name": Json("Widget"),
    "sale_amount": Json(199.98),
    "quantity": Json(2),
    "region": Json("North"),
    "timestamp": Json("2026-02-13T14:15:00")
  ]);

  sales.insertRow([
    "transaction_id": Json(1003),
    "product_name": Json("Device"),
    "sale_amount": Json(299.99),
    "quantity": Json(1),
    "region": Json("East"),
    "timestamp": Json("2026-02-13T16:00:00")
  ]);

  sales.insertRow([
    "transaction_id": Json(1004),
    "product_name": Json("Widget"),
    "sale_amount": Json(99.99),
    "quantity": Json(1),
    "region": Json("West"),
    "timestamp": Json("2026-02-13T17:45:00")
  ]);

  writeln("Dataset: 5 sales transactions inserted\n");

  // Example 1: Aggregation - Sum by Product
  writeln("Example 1: Aggregation - Sum Sales by Product");
  writeln("---------");
  double[string] salesByProduct;
  auto allRows = sales.getAllRows();

  foreach (row; allRows) {
    string product = row["product_name"].get!string;
    double amount = row["sale_amount"].get!double;
    if (product !in salesByProduct) {
      salesByProduct[product] = 0;
    }
    salesByProduct[product] += amount;
  }

  foreach (product, total; salesByProduct) {
    writeln(format("  %s: $%.2f", product, total));
  }
  writeln();

  // Example 2: Region-based Analysis
  writeln("Example 2: Regional Sales Analysis");
  writeln("---------");
  double[string] salesByRegion;

  foreach (row; allRows) {
    string region = row["region"].get!string;
    double amount = row["sale_amount"].get!double;
    if (region !in salesByRegion) {
      salesByRegion[region] = 0;
    }
    salesByRegion[region] += amount;
  }

  double totalSales = 0;
  foreach (region, amount; salesByRegion) {
    writeln(format("  %s: $%.2f", region, amount));
    totalSales += amount;
  }
  writeln(format("  Total: $%.2f", totalSales));
  writeln();

  // Example 3: Query and Filter
  writeln("Example 3: Filter Transactions by Product");
  writeln("---------");
  auto widgetIndices = sales.query("product_name", Json("Widget"));
  writeln("Widget transactions found at indices: ", widgetIndices);

  double widgetTotal = 0;
  foreach (idx; widgetIndices) {
    auto row = sales.getRow(idx);
    widgetTotal += row["sale_amount"].get!double;
    writeln(format("  Transaction %s: $%.2f", row["transaction_id"], row["sale_amount"]));
  }
  writeln(format("Widget Total: $%.2f", widgetTotal));
  writeln();

  // Example 4: Statistical Analysis
  writeln("Example 4: Statistical Analysis");
  writeln("---------");
  auto amountStats = sales.getColumnStats("sale_amount");
  writeln("Sale Amount Statistics:");
  writeln(format("  Count: %s", amountStats.rowCount));
  writeln(format("  Min: $%.2f", amountStats.minValue.get!double));
  writeln(format("  Max: $%.2f", amountStats.maxValue.get!double));
  writeln(format("  Avg: $%.2f", amountStats.avgValue.get!double));
  writeln(format("  Distinct Values: %s", amountStats.distinctValues));
  writeln();

  auto qtyStats = sales.getColumnStats("quantity");
  writeln("Quantity Statistics:");
  writeln(format("  Count: %s", qtyStats.rowCount));
  writeln(format("  Min: %s", qtyStats.minValue.get!long));
  writeln(format("  Max: %s", qtyStats.maxValue.get!long));
  writeln(format("  Avg: %.2f", qtyStats.avgValue.get!double));
  writeln();

  // Example 5: High-Value Transaction Analysis
  writeln("Example 5: High-Value Transaction Analysis");
  writeln("---------");
  double threshold = 150.0;
  writeln(format("Transactions over $%.2f:", threshold));

  foreach (row; allRows) {
    double amount = row["sale_amount"].get!double;
    if (amount >= threshold) {
      writeln(format("  Transaction %s: %s - $%.2f",
        row["transaction_id"],
        row["product_name"],
        row["sale_amount"]
      ));
    }
  }
  writeln();

  // Example 6: Column Scanning with Predicate
  writeln("Example 6: Filtered Column Scan");
  writeln("---------");
  auto ctable = cast(CdbTable)sales;
  if (ctable !is null) {
    auto northRegionIndices = ctable.scan((Json[string] row) {
      if ("region" in row) {
        return row["region"].get!string == "North";
      }
      return false;
    });

    writeln("North region transactions at indices: ", northRegionIndices);
    double northTotal = 0;
    foreach (idx; northRegionIndices) {
      auto row = sales.getRow(idx);
      northTotal += row["sale_amount"].get!double;
    }
    writeln(format("North region total: $%.2f", northTotal));
  }
  writeln();

  // Example 7: Multi-Condition Aggregation
  writeln("Example 7: Multi-Condition Aggregation");
  writeln("---------");
  writeln("Products sold in North region:");
  int southWidgetCount = 0;
  double southWidgetRevenue = 0;

  foreach (row; allRows) {
    string region = row["region"].get!string;
    string product = row["product_name"].get!string;
    int qty = row["quantity"].get!int;
    double amount = row["sale_amount"].get!double;

    if (region == "South" && product == "Widget") {
      southWidgetCount += qty;
      southWidgetRevenue += amount;
    }
  }

  writeln(format("  Widget units sold in South: %s", southWidgetCount));
  writeln(format("  Widget revenue in South: $%.2f", southWidgetRevenue));
  writeln();

  // Example 8: Database Size Analysis
  writeln("Example 8: Database and Table Statistics");
  writeln("---------");
  auto tableStats = ctable ? ctable.getStats() : TableStats();
  if (ctable !is null) {
    writeln(format("Table: %s", tableStats.tableName));
    writeln(format("  Rows: %s", tableStats.rowCount));
    writeln(format("  Columns: %s", tableStats.columnCount));
    writeln(format("  Memory: %s bytes", tableStats.totalMemory));
  }

  auto dbStats = db.getStats();
  writeln();
  writeln("Database Statistics:");
  writeln(format("  Name: %s", dbStats.databaseName));
  writeln(format("  Tables: %s", dbStats.tableCount));
  writeln(format("  Total Memory: %s bytes", dbStats.totalMemory));
  writeln();

  // Example 9: Data Density Analysis
  writeln("Example 9: Data Density Analysis");
  writeln("---------");
  auto regionCol = sales.getColumn("region");
  auto distinctRegions = regionCol.getAll();
  writeln(format("Distinct regions in sample: %s", distinctRegions));
  double datasetDensity = cast(double)sales.rowCount() / (cast(double)sales.columnCount() * 100);
  writeln(format("Data density: %.2f%%", datasetDensity * 100));
  writeln();

  // Example 10: Memory-Efficient Aggregation
  writeln("Example 10: Streaming Aggregation");
  writeln("---------");
  struct RegionAgg {
    string region;
    double totalAmount = 0;
    int totalQty = 0;
    int transCount = 0;
  }

  RegionAgg[string] regionAgg;

  // Process row by row (memory efficient for large datasets)
  for (ulong i = 0; i < sales.rowCount(); i++) {
    auto row = sales.getRow(i);
    string region = row["region"].get!string;

    if (region !in regionAgg) {
      regionAgg[region] = RegionAgg(region);
    }

    regionAgg[region].totalAmount += row["sale_amount"].get!double;
    regionAgg[region].totalQty += row["quantity"].get!int;
    regionAgg[region].transCount += 1;
  }

  writeln("Regional Aggregation (Streaming):");
  foreach (region, agg; regionAgg) {
    writeln(format("  %s:", region));
    writeln(format("    Transactions: %s", agg.transCount));
    writeln(format("    Total Qty: %s", agg.totalQty));
    writeln(format("    Total Revenue: $%.2f", agg.totalAmount));
    writeln(format("    Avg Transaction: $%.2f", agg.totalAmount / agg.transCount));
  }

  writeln();
  writeln("=== Advanced Examples Complete ===");
}
