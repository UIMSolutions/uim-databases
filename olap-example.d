#!/usr/bin/env dub
/+ dub.sdl:
    name "olap-example"
    dependency "uim-databases-olap" path="./olap" configuration="library"
+/

module olap-example;

import std.stdio;
import vibe.data.json;
import uim.databases.olap;

void main() {
    writeln("=== UIM OLAP Database Example ===\n");
    
    // 1. Create Data Warehouse
    writeln("1. Creating Data Warehouse...");
    auto warehouse = new DataWarehouse("sales_warehouse");
    writeln("Warehouse created: ", warehouse.name);
    writeln();
    
    // 2. Create OLAP Cube
    writeln("2. Creating OLAP Cube...");
    warehouse.createCube("sales", 
        ["revenue", "quantity", "cost"], 
        ["time_id", "product_id", "customer_id"]);
    writeln("Cube 'sales' created with 3 measures and 3 dimension keys");
    writeln();
    
    // 3. Add Dimensions
    writeln("3. Adding Dimensions...");
    warehouse.addDimension("sales", "time", ["year", "quarter", "month"]);
    warehouse.addDimension("sales", "product", ["category", "brand", "name"]);
    warehouse.addDimension("sales", "customer", ["region", "country", "city"]);
    writeln("Added 3 dimensions: time, product, customer");
    writeln();
    
    // 4. Load Dimension Data
    writeln("4. Loading Dimension Data...");
    
    // Time dimension
    auto timeData = [
        Json(["id": "2026-01", "year": "2026", "quarter": "Q1", "month": "January"]),
        Json(["id": "2026-02", "year": "2026", "quarter": "Q1", "month": "February"]),
        Json(["id": "2026-03", "year": "2026", "quarter": "Q1", "month": "March"])
    ];
    warehouse.loadDimensionData("sales", "time", timeData);
    writeln("  Loaded time dimension: 3 rows");
    
    // Product dimension
    auto productData = [
        Json(["id": "P1", "category": "Electronics", "brand": "TechCo", "name": "Laptop"]),
        Json(["id": "P2", "category": "Electronics", "brand": "TechCo", "name": "Phone"]),
        Json(["id": "P3", "category": "Furniture", "brand": "HomeStyle", "name": "Desk"])
    ];
    warehouse.loadDimensionData("sales", "product", productData);
    writeln("  Loaded product dimension: 3 rows");
    
    // Customer dimension
    auto customerData = [
        Json(["id": "C1", "region": "North America", "country": "USA", "city": "New York"]),
        Json(["id": "C2", "region": "Europe", "country": "Germany", "city": "Berlin"]),
        Json(["id": "C3", "region": "Asia", "country": "Japan", "city": "Tokyo"])
    ];
    warehouse.loadDimensionData("sales", "customer", customerData);
    writeln("  Loaded customer dimension: 3 rows");
    writeln();
    
    // 5. Load Fact Data
    writeln("5. Loading Fact Data...");
    auto factData = [
        Json(["time_id": "2026-01", "product_id": "P1", "customer_id": "C1", 
              "revenue": 1500.0, "quantity": 5.0, "cost": 1000.0]),
        Json(["time_id": "2026-01", "product_id": "P2", "customer_id": "C2", 
              "revenue": 800.0, "quantity": 10.0, "cost": 500.0]),
        Json(["time_id": "2026-02", "product_id": "P1", "customer_id": "C3", 
              "revenue": 3000.0, "quantity": 10.0, "cost": 2000.0]),
        Json(["time_id": "2026-02", "product_id": "P3", "customer_id": "C1", 
              "revenue": 500.0, "quantity": 2.0, "cost": 300.0]),
        Json(["time_id": "2026-03", "product_id": "P2", "customer_id": "C2", 
              "revenue": 1600.0, "quantity": 20.0, "cost": 1000.0]),
        Json(["time_id": "2026-03", "product_id": "P3", "customer_id": "C3", 
              "revenue": 1000.0, "quantity": 4.0, "cost": 600.0])
    ];
    warehouse.loadFactData("sales", factData);
    writeln("Loaded fact data: 6 rows");
    writeln();
    
    // 6. Aggregate Query: Total Revenue by Time
    writeln("6. Aggregation: Total Revenue by Month...");
    auto result1 = warehouse.aggregate("sales", ["time_id"], ["revenue", "quantity"]);
    writeln("Results:");
    foreach (row; result1["data"]) {
        writeln("  ", row["time_id"].get!string, 
                ": Revenue=", row["revenue"].get!double, 
                ", Quantity=", row["quantity"].get!double);
    }
    writeln();
    
    // 7. Aggregate Query: Revenue by Product
    writeln("7. Aggregation: Total Revenue by Product...");
    auto result2 = warehouse.aggregate("sales", ["product_id"], ["revenue"]);
    writeln("Results:");
    foreach (row; result2["data"]) {
        writeln("  ", row["product_id"].get!string, 
                ": Revenue=", row["revenue"].get!double);
    }
    writeln();
    
    // 8. Multi-Dimensional Aggregation
    writeln("8. Multi-Dimensional: Revenue by Time and Product...");
    auto result3 = warehouse.aggregate("sales", 
        ["time_id", "product_id"], 
        ["revenue", "quantity"]);
    writeln("Results (", result3["resultCount"].get!long, " combinations):");
    foreach (row; result3["data"]) {
        writeln("  ", row["time_id"].get!string, " - ", 
                row["product_id"].get!string,
                ": Revenue=", row["revenue"].get!double);
    }
    writeln();
    
    // 9. Slice Operation: January Sales Only
    writeln("9. Slice: January Sales Only...");
    auto result4 = warehouse.slice("sales", "time_id", "2026-01", ["revenue", "quantity"]);
    writeln("January Results:");
    foreach (row; result4["data"]) {
        writeln("  Product ", row["product_id"].get!string, 
                ": Revenue=", row["revenue"].get!double);
    }
    writeln();
    
    // 10. Dice Operation: Filter by Time Range
    writeln("10. Dice: Electronics in Q1...");
    // Note: This would work better with actual filtering in practice
    auto result5 = warehouse.aggregate("sales", 
        ["product_id", "time_id"], 
        ["revenue"]);
    writeln("Results: ", result5["resultCount"].get!long, " rows");
    writeln();
    
    // 11. Pivot Table
    writeln("11. Pivot: Products (rows) x Time (columns)...");
    auto result6 = warehouse.pivot("sales",
        ["product_id"],  // rows
        ["time_id"],     // columns
        ["revenue"]);
    writeln("Pivot table with ", result6["data"].length, " data points");
    writeln();
    
    // 12. Cube Metadata
    writeln("12. Cube Metadata...");
    auto cube = warehouse.getCube("sales");
    auto metadata = cube.getMetadata();
    writeln("Cube Name: ", metadata["name"].get!string);
    writeln("Dimensions: ", metadata["dimensions"].length);
    writeln("Measures: ", metadata["measures"].length);
    writeln();
    
    // 13. Query Builder
    writeln("13. Query Builder Example...");
    auto query = new QueryBuilder()
        .from("sales")
        .dimensions("time_id", "product_id")
        .measures("revenue", "quantity")
        .where("time_id", "2026-01")
        .limit(10);
    
    auto queryJson = query.build();
    writeln("Built Query:");
    writeln(queryJson.toPrettyString());
    writeln();
    
    // 14. Warehouse Statistics
    writeln("14. Warehouse Statistics...");
    auto stats = warehouse.getStatistics();
    writeln(stats.toPrettyString());
    writeln();
    
    writeln("=== Example Complete ===");
}
