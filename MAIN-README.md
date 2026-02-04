# Database Implementations in D with vibe.d

This workspace contains three complete database implementations in D language with REST APIs powered by vibe.d:

## 🗄️ Databases

### 1. Vector Database (Port 8080)
Similarity search and nearest neighbor queries using various distance metrics.

**Features:**
- Multiple distance metrics (Euclidean, Cosine, Manhattan, Dot Product)
- k-NN search
- Vector operations
- Metadata support

**Run:**
```bash
dub --config=vector
```

**Documentation:** See [README.md](README.md)

---

### 2. Object Database (Port 8081)
Document-oriented database for storing JSON objects with flexible querying.

**Features:**
- JSON document storage
- Collections (like MongoDB)
- Rich query operators (==, !=, >, <, contains, in, exists)
- Nested field access with dot notation
- Indexing
- Sorting & pagination
- Bulk operations

**Run:**
```bash
dub --config=object
```

**Documentation:** See [OBJECT-README.md](OBJECT-README.md)

---

### 3. Relational Database (Port 8082)
SQL-like relational database with typed schemas, constraints, and JOIN operations.

**Features:**
- Typed columns (INTEGER, FLOAT, STRING, BOOLEAN, DATE, JSON)
- Constraints (PRIMARY KEY, UNIQUE, NOT NULL, FOREIGN KEY)
- SQL-like operations (SELECT, INSERT, UPDATE, DELETE)
- WHERE clauses with multiple operators
- INNER JOIN
- ORDER BY, LIMIT, OFFSET
- Schema management

**Run:**
```bash
dub --config=relational
```

**Documentation:** See [RELATIONAL-README.md](RELATIONAL-README.md)

---

## 🚀 Quick Start

### Run All Three Simultaneously

```bash
# Terminal 1 - Vector Database
dub --config=vector

# Terminal 2 - Object Database  
dub --config=object

# Terminal 3 - Relational Database
dub --config=relational
```

### Test the Databases

```bash
# Vector DB
curl http://localhost:8080/health

# Object DB
curl http://localhost:8081/health

# Relational DB
curl http://localhost:8082/health
```

### Run Examples

```bash
# Vector database example
rdmd example.d

# Object database example
rdmd object-example.d

# Relational database example
rdmd relational-example.d
```

## 📊 Comparison

| Feature | Vector DB | Object DB | Relational DB |
|---------|-----------|-----------|---------------|
| **Port** | 8080 | 8081 | 8082 |
| **Data Model** | Vectors | JSON Documents | Typed Rows |
| **Best For** | Similarity search | Flexible schemas | Structured data |
| **Query Type** | k-NN search | Document queries | SQL-like queries |
| **Schema** | Fixed dimension | Schema-less | Strict schema |
| **Joins** | ❌ | ❌ | ✅ INNER JOIN |
| **Indexing** | ❌ | ✅ Field indexes | ✅ Primary key |
| **Constraints** | ❌ | ❌ | ✅ Full constraints |

## 🛠️ Use Cases

### Vector Database
- Image similarity search
- Text embeddings search (semantic search)
- Recommendation systems
- Anomaly detection
- Face recognition
- Content-based retrieval

### Object Database
- User profiles with varying attributes
- Product catalogs
- Event logs
- Configuration storage
- CMS content
- Flexible data structures

### Relational Database
- User accounts with relationships
- Order management systems
- Inventory tracking
- Financial records
- Traditional CRUD applications
- Data with foreign key relationships

## 📁 Project Structure

```
DATABASES/
├── source/
│   ├── app.d                 # Vector DB API
│   ├── vectorops.d           # Vector operations
│   ├── vectordb.d            # Vector database core
│   ├── objectapp.d           # Object DB API
│   ├── objectdb.d            # Object database core
│   ├── relationalapp.d       # Relational DB API
│   └── relationaldb.d        # Relational database core
├── example.d                 # Vector DB example
├── object-example.d          # Object DB example
├── relational-example.d      # Relational DB example
├── README.md                 # Vector DB docs
├── OBJECT-README.md          # Object DB docs
├── RELATIONAL-README.md      # Relational DB docs
└── dub.json                  # Project configuration
```

## 🔧 Development

### Build
```bash
# Build specific database
dub build --config=vector
dub build --config=object
dub build --config=relational
```

### Dependencies
- **vibe.d**: Web framework and HTTP server
- **D compiler**: DMD, LDC, or GDC

## 📝 API Examples

### Vector Database
```bash
# Add vector
curl -X POST http://localhost:8080/vectors \
  -H "Content-Type: application/json" \
  -d '{"id": "vec1", "vector": [0.1, 0.2, ...], "metadata": {}}'

# Search
curl -X POST http://localhost:8080/search \
  -H "Content-Type: application/json" \
  -d '{"vector": [0.1, 0.2, ...], "k": 5}'
```

### Object Database
```bash
# Create collection
curl -X POST http://localhost:8081/collections/users

# Insert document
curl -X POST http://localhost:8081/collections/users/documents \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "age": 28}'

# Query
curl -X POST http://localhost:8081/collections/users/find \
  -H "Content-Type: application/json" \
  -d '{"where": [{"field": "age", "op": ">", "value": 25}]}'
```

### Relational Database
```bash
# Create table
curl -X POST http://localhost:8082/tables \
  -H "Content-Type: application/json" \
  -d '{"name": "users", "columns": [...]}'

# Insert row
curl -X POST http://localhost:8082/tables/users/insert \
  -H "Content-Type: application/json" \
  -d '{"id": 1, "name": "Alice", "age": 28}'

# Select
curl -X POST http://localhost:8082/tables/users/select \
  -H "Content-Type: application/json" \
  -d '{"columns": ["*"], "where": [{"column": "age", "op": ">", "value": 25}]}'
```

## 🎯 Future Enhancements

### All Databases
- [ ] Persistent storage (disk-based)
- [ ] Authentication & authorization
- [ ] Replication
- [ ] Backups

### Vector Database
- [ ] HNSW indexing
- [ ] Vector quantization
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
