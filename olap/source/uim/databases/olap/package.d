module uim.databases.olap;

/// UIM OLAP (Online Analytical Processing) Database
/// 
/// A complete OLAP database system with:
/// - Columnar storage for efficient analytical queries
/// - OLAP cubes with dimensions and measures
/// - Star/snowflake schema support
/// - Aggregation engine (SUM, AVG, COUNT, MIN, MAX)
/// - OLAP operations (slice, dice, pivot, drill-down, roll-up)
/// - REST API for remote access
/// - Data warehouse capabilities
/// 
/// Example usage:
/// ```d
/// import uim.databases.olap;
/// 
/// // Create data warehouse
/// auto warehouse = new DataWarehouse("sales_dw");
/// 
/// // Create cube with measures and dimension keys
/// warehouse.createCube("sales", 
///     ["revenue", "quantity", "profit"], 
///     ["time_id", "product_id", "customer_id"]);
/// 
/// // Add dimensions
/// warehouse.addDimension("sales", "time", ["year", "quarter", "month", "day"]);
/// warehouse.addDimension("sales", "product", ["category", "brand", "name"]);
/// warehouse.addDimension("sales", "customer", ["region", "country", "city"]);
/// 
/// // Load fact data
/// auto factData = [
///     Json(["time_id": "2026-01", "product_id": "P1", "customer_id": "C1", 
///           "revenue": 1000.0, "quantity": 10, "profit": 200.0])
/// ];
/// warehouse.loadFactData("sales", factData);
/// 
/// // Query: Aggregate by time and product
/// auto result = warehouse.aggregate("sales", 
///     ["time_id", "product_id"], 
///     ["revenue", "quantity"]);
/// ```

public import uim.databases.olap.storage;
public import uim.databases.olap.cube;
public import uim.databases.olap.aggregation;
public import uim.databases.olap.query;
public import uim.databases.olap.api;
public import uim.databases.olap.warehouse;
