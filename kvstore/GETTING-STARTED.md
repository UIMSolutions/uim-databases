# Getting Started with Key-Value Store

## 5-Minute Quick Start

### 1. **Navigate to the kvstore directory**
```bash
cd kvstore
```

### 2. **Run the REST API Server**
```bash
./quickstart.sh
```

Or manually:
```bash
dub build --config=executable
dub run --config=executable
```

### 3. **Test the API**
In another terminal, run:

```bash
# Set a value
curl -X POST http://localhost:8080/kvstore \
  -H "Content-Type: application/json" \
  -d '{"key": "greeting", "value": "Hello, World!"}'

# Get a value
curl http://localhost:8080/kvstore/greeting

# Get all keys
curl http://localhost:8080/kvstore/keys

# Get statistics
curl http://localhost:8080/kvstore/stats
```

---

## Using as a Library

### 1. **Add to your project's dub.sdl**
```sdl
dependency "uim-databases-kvstore" path="./kvstore"
```

### 2. **Import in your code**
```d
import uim.databases.kvstore;

void main() {
    // In-memory store
    auto store = new KVStore("mystore");
    store.set("key", "value");
    writeln(store.get("key"));
    
    // Or persistent store
    auto persistent = new PersistentKVStore("./data.json");
    persistent.set("config", "settings");
}
```

### 3. **Build your project**
```bash
dub build
```

---

## REST API Examples

### Create/Update a Key
```bash
curl -X POST http://localhost:8080/kvstore \
  -H "Content-Type: application/json" \
  -d '{"key": "username", "value": "alice"}'
```

**Response:**
```json
{
  "success": true,
  "key": "username",
  "message": "Value stored successfully"
}
```

### Get a Value
```bash
curl http://localhost:8080/kvstore/username
```

**Response:**
```json
{
  "success": true,
  "key": "username",
  "value": "alice"
}
```

### Check if Key Exists
```bash
curl http://localhost:8080/kvstore/check/username
```

**Response:**
```json
{
  "exists": true,
  "key": "username"
}
```

### Get All Keys
```bash
curl http://localhost:8080/kvstore/keys
```

**Response:**
```json
{
  "keys": ["username", "email", "age"],
  "count": 3
}
```

### Get Store Statistics
```bash
curl http://localhost:8080/kvstore/stats
```

**Response:**
```json
{
  "totalKeys": 3,
  "availableKeys": 3
}
```

### Delete a Key
```bash
curl -X DELETE http://localhost:8080/kvstore/username
```

**Response:**
```json
{
  "success": true,
  "key": "username"
}
```

### Set Multiple Values
```bash
curl -X POST http://localhost:8080/kvstore/multi \
  -H "Content-Type: application/json" \
  -d '{
    "pairs": {
      "fname": "John",
      "lname": "Doe",
      "email": "john@example.com"
    }
  }'
```

**Response:**
```json
{
  "success": true,
  "count": 3,
  "message": "Multiple values stored successfully"
}
```

### Get Multiple Values
```bash
curl -X POST http://localhost:8080/kvstore/multi-get \
  -H "Content-Type: application/json" \
  -d '["fname", "lname", "email"]'
```

**Response:**
```json
{
  "values": {
    "fname": "John",
    "lname": "Doe",
    "email": "john@example.com"
  },
  "found": 3,
  "requested": 3
}
```

### Clear Store
```bash
curl -X DELETE http://localhost:8080/kvstore
```

**Response:**
```json
{
  "success": true,
  "message": "Store cleared successfully"
}
```

---

## Programming Examples

### Example 1: Session Management
```d
import uim.databases.kvstore;

auto sessions = new KVStore("sessions");

// Store session
sessions.set("session_abc123", `{"user_id": 42, "created": "2026-02-13"}`);

// Retrieve session
string sessionData = sessions.get("session_abc123");

// Check if active
if (sessions.exists("session_abc123")) {
    writeln("Session is active");
}
```

### Example 2: Application Configuration
```d
auto config = new PersistentKVStore("./config.json");

// Load or create configuration
if (!config.exists("api.version")) {
    config.multiSet([
        "api.version": "1.0.0",
        "api.port": "8080",
        "db.host": "localhost",
        "db.port": "5432"
    ]);
}

string apiVersion = config.get("api.version");
```

### Example 3: Cache Layer
```d
auto cache = new KVStore("cache");

string getCachedData(string key) {
    if (cache.exists(key)) {
        return cache.get(key);  // Return from cache
    }
    
    // Fetch from source
    string data = fetchFromDatabase(key);
    cache.set(key, data);  // Store in cache
    return data;
}
```

### Example 4: Feature Flags
```d
auto features = new KVStore("features");

features.multiSet([
    "feature.dark_mode": "true",
    "feature.beta_api": "false",
    "feature.new_ui": "true"
]);

if (features.get("feature.dark_mode") == "true") {
    // Enable dark mode
}
```

### Example 5: Error Handling
```d
auto store = new KVStore("app");

try {
    string value = store.get("nonexistent");
} catch (KeyNotFoundException e) {
    writeln("Key not found: ", e.msg);
}

// Or use multiGet (non-throwing)
auto values = store.multiGet(["key1", "key2"]);
foreach (key, value; values) {
    writeln(key, " = ", value);
}
```

---

## Performance Tips

1. **Use In-Memory Store for High Performance**
   - O(1) operations for get, set, delete
   - Best for caching and transient data

2. **Use Persistent Store for Configuration**
   - Automatic persistence to disk
   - Data survives across restarts
   - Accept slight I/O overhead

3. **Batch Operations**
   - Use `multiSet()` and `multiGet()` for bulk operations
   - More efficient than individual operations

4. **Use REST API for Remote Access**
   - HTTP protocol for cross-service communication
   - Scalability across machines

5. **Monitor Store Size**
   - Use `count()` and `keys()` to monitor
   - Implement cleanup routines for large stores

---

## Troubleshooting

### Build Issues

**Problem**: Dependencies not found
```
Error: Failed to find package uim-framework
```

**Solution**:
```bash
dub fetch --cache=user
dub upgrade
```

### Runtime Issues

**Problem**: Port already in use
```
Error: Address already in use
```

**Solution**: Either stop the previous server or change the port in `app.d` (line ~40)

**Problem**: File permissions error with persistent store
```
Error: Failed to save store: Permission denied
```

**Solution**: Ensure write permissions for the data directory:
```bash
mkdir -p ./data
chmod 755 ./data
```

---

## Project Structure Reference

```
kvstore/
├── README.md              # Full documentation
├── quickstart.sh          # Quick start script
├── dub.sdl               # Project config
├── kvstore-example.d     # Basic examples
├── kvstore-advanced-example.d  # Advanced examples
└── source/
    ├── app.d             # REST API server
    └── uim/databases/kvstore/
        ├── classes/      # Store implementations
        ├── interfaces/   # Store interface
        ├── api/          # REST API
        └── errors/       # Exception handling
```

---

## Next Steps

1. **Run the Examples**
   ```bash
   cd kvstore
   dub run kvstore-example.d
   dub run kvstore-advanced-example.d
   ```

2. **Integrate into Your Project**
   - Import the module in your D code
   - Use as library in your larger application

3. **Explore Advanced Features**
   - Create custom store implementations
   - Extend REST API with additional endpoints
   - Implement caching strategies

4. **Deploy**
   - Build for production with optimizations
   - Configure for your deployment environment
   - Monitor performance and usage

---

## Security Considerations

⚠️ **Note**: This implementation is for development and learning purposes.

For production use:
- Add authentication/authorization
- Validate all inputs
- Use HTTPS for REST API
- Implement rate limiting
- Add encryption for sensitive data
- Implement access control lists
- Regular backups for persistent store

---

## Support & Documentation

- **README.md** - Full API documentation
- **kvstore-example.d** - Basic usage examples  
- **kvstore-advanced-example.d** - Advanced patterns
- **KVSTORE-IMPLEMENTATION.md** - Implementation details

---

**Version**: 1.0.0  
**License**: Apache 2.0  
**Last Updated**: 2026-02-13
