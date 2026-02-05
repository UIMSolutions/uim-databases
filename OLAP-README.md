# UIM OLAP Database

A complete Online Analytical Processing (OLAP) database system built with D and vibe.d.

## Features

### 📊 Columnar Storage
- **Column-Oriented**: Optimized for analytical queries
- **Compression Support**: Efficient storage of repeated values
- **Type System**: Integer, Float, String, Date, Boolean
- **Null Handling**: Proper null value management
- **Statistics**: Built-in column statistics (sum, avg, min, max, count)

### 🎲 OLAP Cube
- **Multidimensional Analysis**: Dimensions and measures
- **Star Schema**: Fact and dimension tables
- **Hierarchies**: Support for drill-down and roll-up
- **Metadata Management**: Comprehensive cube metadata

### 📈 Aggregation Engine
- **Aggregation Functions**:
  - SUM: Total values
  - AVG: Average values
  - COUNT: Count records
  - MIN: Minimum value
  - MAX: Maximum value
  - COUNT DISTINCT: Unique count
  
- **Group By**: Multi-dimensional grouping
- **Filtering**: WHERE clause support

### 🔄 OLAP Operations
- **Slice**: Fix one dimension, analyze others
- **Dice**: Filter multiple dimensions
- **Pivot**: Rotate data for different views
- **Drill-Down**: Navigate from summary to detail
- **Roll-Up**: Navigate from detail to summary

### 🌐 REST API
Full HTTP REST API using vibe.d:

- **Warehouse Operations**
  - `GET /` - Warehouse info
  - `GET /stats` - Statistics

- **Cube Management**
  - `POST /cubes` - Create cube
  - `GET /cubes` - List cubes
  - `GET /cubes/:cubeName` - Get cube info
  - `DELETE /cubes/:cubeName` - Delete cube

- **Data Loading**
  - `POST /cubes/:cubeName/facts` - Load fact data
  - `POST /cubes/:cubeName/dimensions/:dimName` - Load dimension data

- **OLAP Queries**
  - `POST /cubes/:cubeName/aggregate` - Aggregate query
  - `POST /cubes/:cubeName/slice` - Slice operation
  - `POST /cubes/:cubeName/dice` - Dice operation
  - `POST /cubes/:cubeName/pivot` - Pivot table
  - `POST /cubes/:cubeName/drilldown` - Drill-down
  - `POST /cubes/:cubeName/rollup` - Roll-up

## Installation

Add to your `dub.sdl`:

```sdl
dependency "uim-databases-olap" path="./olap" configuration="library"
```

## Quick Start

### Programmatic Usage

```d
import uim.databases.olap;
import vibe.data.json;

// Create warehouse
auto warehouse = new DataWarehouse("sales_dw");

// Create cube
warehouse.createCube("sales", 
    ["revenue", "quantity"],  // measures
    ["time_id", "product_id"] // dimension keys
);

// Add dimensions
warehouse.addDimension("sales", "time", ["year", "month", "day"]);
warehouse.addDimension("sales", "product", ["category", "name"]);

// Load fact data
auto facts = [
    Json(["time_id": "2026-01", "product_id": "P1", 
          "revenue": 1000.0, "quantity": 10.0])
];
warehouse.loadFactData("sales", facts);

// Aggregate: Total revenue by time
auto result = warehouse.aggregate("sales", 
    ["time_id"], 
    ["revenue", "quantity"]);
```

### Running as Server

```bash
# Build and run
cd olap
dub run

# Or specify warehouse name and port
dub run -- sales_warehouse 9090
```

### Using REST API

```bash
# Create cube
curl -X POST http://localhost:9090/cubes \
  -H "Content-Type: application/json" \
  -d '{
    "name": "sales",
    "measures": ["revenue", "quantity"],
    "dimensionKeys": ["time_id", "product_id"],
    "dimensions": [
      {"name": "time", "attributes": ["year", "month"]},
      {"name": "product", "attributes": ["category", "name"]}
    ]
  }'

# Load fact data
curl -X POST http://localhost:9090/cubes/sales/facts \
  -H "Content-Type: application/json" \
  -d '[
    {"time_id": "2026-01", "product_id": "P1", "revenue": 1000, "quantity": 10}
  ]'

# Aggregate query
curl -X POST http://localhost:9090/cubes/sales/aggregate \
  -H "Content-Type: application/json" \
  -d '{
    "dimensions": ["time_id"],
    "measures": ["revenue", "quantity"]
  }'

# Slice operation
curl -X POST http://localhost:9090/cubes/sales/slice \
  -H "Content-Type: application/json" \
  -d '{
    "dimension": "time_id",
    "value": "2026-01",
    "measures": ["revenue"]
  }'

# Pivot table
curl -X POST http://localhost:9090/cubes/sales/pivot \
  -H "Content-Type: application/json" \
  -d '{
    "rowDimensions": ["product_id"],
    "columnDimensions": ["time_id"],
    "measures": ["revenue"]
  }'
```

## Architecture

```
DataWarehouse
├── OLAPCube
│   ├── FactTable (columnar)
│   │   └── Measures + Dimension Keys
│   └── DimensionTables (columnar)
│       └── Attributes
├── AggregationEngine
│   └── OLAP operations
└── REST API
    └── HTTP endpoints via vibe.d
```

## Examples

See [olap-example.d](../olap-example.d) for comprehensive examples including:
- Creating cubes and dimensions
- Loading fact and dimension data
- Aggregation queries
- Slice and dice operations
- Pivot tables
- Query builder

Run the example:
```bash
dub run --single olap-example.d
```

## Star Schema Example

```d
// Fact Table: Sales
warehouse.createCube("sales",
    ["revenue", "quantity", "profit"],  // Measures
    ["time_id", "product_id", "store_id", "customer_id"]  // Foreign keys
);

// Dimension Tables
warehouse.addDimension("sales", "time", 
    ["year", "quarter", "month", "day"]);
warehouse.addDimension("sales", "product", 
    ["category", "subcategory", "brand", "name"]);
warehouse.addDimension("sales", "store", 
    ["region", "country", "city", "name"]);
warehouse.addDimension("sales", "customer", 
    ["segment", "country", "city"]);
```

## Query Examples

### Aggregation
```d
// Total sales by year and product category
auto result = warehouse.aggregate("sales",
    ["year", "category"],
    ["revenue", "quantity"]
);
```

### Slice
```d
// Sales for 2026 only
auto result = warehouse.slice("sales", 
    "year", "2026", 
    ["revenue", "profit"]
);
```

### Dice
```d
// Sales for Electronics in Q1 2026
auto filters = Json(["year": "2026", "category": "Electronics"]);
auto result = warehouse.dice("sales", 
    filters,
    ["month", "product"],
    ["revenue"]
);
```

### Pivot
```d
// Products (rows) × Time (columns)
auto result = warehouse.pivot("sales",
    ["product"],      // row dimensions
    ["month"],        // column dimensions
    ["revenue"]       // measures
);
```

## Performance Features

1. **Columnar Storage**: Fast aggregations on columns
2. **In-Memory**: Lightning-fast queries
3. **Index Support**: Quick filtering
4. **Batch Loading**: Efficient data ingestion
5. **Statistics Cache**: Pre-computed column stats

## Use Cases

- **Business Intelligence**: Sales analysis, KPI dashboards
- **Data Analytics**: Customer behavior, market trends
- **Reporting**: Financial reports, operational metrics
- **Decision Support**: What-if analysis, forecasting

## Comparison: OLAP vs OLTP

| Feature | OLAP (This) | OLTP (Sibling) |
|---------|-------------|----------------|
| Purpose | Analysis | Transactions |
| Queries | Complex, analytical | Simple, transactional |
| Storage | Column-oriented | Row-oriented |
| Operations | Aggregations | Insert/Update/Delete |
| Data Volume | Large historical | Current operational |
| Response Time | Seconds | Milliseconds |
| Users | Analysts | End users |

## Future Enhancements

- [ ] Materialized views
- [ ] Query optimization and caching
- [ ] Partition pruning
- [ ] Parallel query execution
- [ ] Data compression (RLE, dictionary)
- [ ] Incremental cube refresh
- [ ] MDX query language
- [ ] Export to CSV/Parquet
- [ ] Integration with visualization tools

## License

Apache License 2.0

Copyright © 2026, UIM Solutions
