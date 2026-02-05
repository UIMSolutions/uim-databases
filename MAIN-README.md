# Database Implementations in D with vibe.d

This workspace contains three complete database implementations in D language with REST APIs powered by vibe.d:

## 🗄️ Databases

### 1. Vector Database
Similarity search and nearest neighbor queries using various distance metrics.

**Features:**
- Multiple distance metrics (Euclidean, Cosine, Manhattan, Dot Product)
- k-NN search
- Vector operations
- Metadata support

**Documentation:** See [README.md](README.md)

---

### 2. Object Database
Document-oriented database for storing JSON objects with flexible querying.

**Features:**
- JSON document storage
- Collections (like MongoDB)
- Rich query operators (==, !=, >, <, contains, in, exists)
- Nested field access with dot notation
- Indexing
- Sorting & pagination
- Bulk operations

**Documentation:** See [OBJECT-README.md](OBJECT-README.md)

---

### 3. Relational Database
SQL-like relational database with typed schemas, constraints, and JOIN operations.

**Features:**
- Typed columns (INTEGER, FLOAT, STRING, BOOLEAN, DATE, JSON)
- Constraints (PRIMARY KEY, UNIQUE, NOT NULL, FOREIGN KEY)
- SQL-like operations (SELECT, INSERT, UPDATE, DELETE)
- WHERE clauses with multiple operators
- INNER JOIN
- ORDER BY, LIMIT, OFFSET
- Schema management

**Documentation:** See [RELATIONAL-README.md](RELATIONAL-README.md)

---

### 4. OLTP Database
High-performance transactional database with full ACID compliance, connection pooling, and write-ahead logging.

**Features:**
- ACID transactions with isolation levels (READ_UNCOMMITTED, READ_COMMITTED, REPEATABLE_READ, SERIALIZABLE)
- Connection pooling with configurable sizes
- Row-level locking (shared, exclusive, intent)
- Write-Ahead Logging (WAL) with recovery
- Transaction timestamps and rollback
- Full REST API for operations

**Documentation:** See [OLTP-README.md](OLTP-README.md)

---

### 5. OLAP Database
Data warehouse system optimized for analytical queries with columnar storage and multidimensional analysis.

**Features:**
- Columnar storage for analytical efficiency
- Fact tables and dimension tables
- OLAP cubes with measures and hierarchies
- Aggregation operations (sum, avg, min, max, count, distinct)
- Slicing, dicing, pivoting, drill-down, roll-up
- Complex hierarchy support
- Full REST API for analytics

**Documentation:** See [OLAP-README.md](OLAP-README.md)

---

### 6. Graph Database
Relationship database for modeling networks with advanced graph algorithms and centrality measures.

**Features:**
- Nodes and edges with properties
- Thread-safe concurrent access
- Graph traversal (BFS, DFS)
- Pathfinding (shortest path, all paths)
- Connected components
- Centrality measures (degree, betweenness, closeness, PageRank)
- Efficient adjacency list representation
- Full REST API for graph operations

**Documentation:** See [GRAPH-README.md](GRAPH-README.md)

---

## 🚀 Quick Start

### Run Each Database

```bash
# Vector Database (8080)
cd vector && dub run

# Object Database (8081)
cd object && dub run

# Relational Database (8082)
cd relational && dub run

# OLTP Database (8083)
cd oltp && dub run

# OLAP Database (8084)
cd olap && dub run

# Graph Database (8085)
cd graph && dub run
```

### Run Examples

```bash
# Vector database example
dub run --single example.d

# Object database example
dub run --single object-example.d

# Relational database example
dub run --single relational-example.d

# OLTP database example
dub run --single oltp-database-example.d

# OLAP database example
dub run --single olap-example.d

# Graph database example
dub run --single graph-example.d
```

## 📊 Comparison

| Feature | Vector DB | Object DB | Relational | OLTP | OLAP | Graph |
|---------|-----------|-----------|-----------|------|------|-------|
| **Data Model** | Vectors | JSON | Typed Rows | Transactional | Columnar | Nodes/Edges |
| **Best For** | Similarity | Flexible | Structured | ACID Txns | Analytics | Relationships |
| **Query Type** | k-NN | Document | SQL | Transactions | Aggregations | Traversal |
| **Schema** | Fixed dims | Schema-less | Strict | Strict | Strict | Flexible |
| **Joins** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Transactions** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Locking** | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Aggregations** | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| **Pathfinding** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Centrality** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

## 🛠️ Use Cases

### Vector Database
- Image similarity search
- Text embeddings search (semantic search)
- Recommendation systems
- Anomaly detection
- Face recognition

### Object Database
- User profiles with varying attributes
- Product catalogs
- Event logs
- Configuration storage
- Flexible data structures

### Relational Database
- User accounts with relationships
- Order management systems
- Inventory tracking
- Financial records
- Traditional CRUD applications

### OLTP Database
- Real-time transaction processing
- Banking/payment systems
- E-commerce order processing
- Reservation systems
- High-concurrency applications

### OLAP Database
- Business intelligence
- Data warehousing
- Sales analysis
- Trend analysis
- Executive dashboards

### Graph Database
- Social networks
- Knowledge graphs
- Recommendation systems
- Dependency analysis
- Organizational hierarchies

## 📁 Project Structure

```
DATABASES/
├── vector/                   # Vector similarity search
├── object/                   # Document-oriented database
├── relational/               # SQL-like relational database
├── oltp/                     # ACID transactional database
├── olap/                     # Data warehouse analytics
├── graph/                    # Graph relationship database
├── example.d                 # Vector DB example
├── object-example.d          # Object DB example
├── relational-example.d      # Relational DB example
├── oltp-database-example.d   # OLTP DB example
├── olap-example.d            # OLAP DB example
├── graph-example.d           # Graph DB example
├── README.md                 # Vector DB docs
├── OBJECT-README.md          # Object DB docs
├── RELATIONAL-README.md      # Relational DB docs
├── OLTP-README.md            # OLTP DB docs
├── OLAP-README.md            # OLAP DB docs
├── GRAPH-README.md           # Graph DB docs
└── MAIN-README.md            # This file
```

## 🔧 Development

### Build
```bash
# Build specific database
cd vector && dub build --build=release
cd object && dub build --build=release
cd relational && dub build --build=release
cd oltp && dub build --build=release
cd olap && dub build --build=release
cd graph && dub build --build=release
```

### Dependencies
- **vibe.d** (~0.9.0): Web framework and HTTP server
- **D compiler**: DMD, LDC, or GDC

## 🎯 Features Summary

### Storage & Persistence
- **Vector DB**: In-memory with metadata
- **Object DB**: In-memory JSON documents
- **Relational DB**: In-memory typed rows
- **OLTP DB**: In-memory with WAL recovery
- **OLAP DB**: In-memory columnar storage
- **Graph DB**: In-memory adjacency lists

### Concurrency & Thread Safety
- **Vector DB**: Read-write locks
- **Object DB**: RWMutex protection
- **Relational DB**: RWMutex protection
- **OLTP DB**: Row-level locking + WAL
- **OLAP DB**: RWMutex protection
- **Graph DB**: RWMutex protection

### Query Capabilities
- **Vector DB**: k-NN search, distance metrics
- **Object DB**: Field queries, nested access
- **Relational DB**: SQL-like, JOINs, complex WHERE
- **OLTP DB**: Transactions, isolation levels
- **OLAP DB**: Aggregations, slicing, dicing
- **Graph DB**: Traversal, pathfinding, centrality

## 📚 Documentation Files

- [MAIN-README.md](MAIN-README.md) - This file, overview of all databases
- [README.md](README.md) - Vector database detailed documentation
- [OBJECT-README.md](OBJECT-README.md) - Object database detailed documentation
- [RELATIONAL-README.md](RELATIONAL-README.md) - Relational database detailed documentation
- [OLTP-README.md](OLTP-README.md) - OLTP database detailed documentation
- [OLAP-README.md](OLAP-README.md) - OLAP database detailed documentation
- [GRAPH-README.md](GRAPH-README.md) - Graph database detailed documentation

## 🎯 Future Enhancements

### All Databases
- [ ] Persistent storage (disk-based)
- [ ] Authentication & authorization
- [ ] Replication
- [ ] Backups
- [ ] Monitoring & metrics

### Vector Database
- [ ] HNSW indexing
- [ ] Vector quantization
- [ ] Batch operations

### OLTP Database
- [ ] MVCC (multi-version concurrency control)
- [ ] Distributed transactions
- [ ] Query optimization

### OLAP Database
- [ ] Bitmap indexes
- [ ] Compression algorithms
- [ ] Incremental cube building

### Graph Database
- [ ] Query optimization
- [ ] Distributed graph processing
- [ ] Advanced algorithms (community detection)
- [ ] Multi-collection support

### Object Database
- [ ] Aggregation pipeline
- [ ] Full-text search
- [ ] Schema validation

### Relational Database
- [ ] Query optimizer
- [ ] Transactions
- [ ] More JOIN types
- [ ] Aggregate functions (SUM, AVG, etc.)
- [ ] GROUP BY
- [ ] SQL parser

## 📄 License

MIT License

## 🤝 Contributing

Contributions welcome! Each database is modular and can be enhanced independently.

## 🔗 Resources

- [D Language](https://dlang.org/)
- [vibe.d Framework](https://vibed.org/)
- [DUB Package Manager](https://dub.pm/)

---

**Choose the right database for your use case or use all three together!**
