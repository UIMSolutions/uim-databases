# GeoDatabase: Getting Started

Complete quick-start guide for the GeoDatabase module. Get up and running with geospatial queries in minutes.

## Prerequisites

- D Language 2.101.0+
- DUB package manager (comes with D)
- Basic familiarity with HTTP and REST APIs

## 5-Minute Setup

### 1. Build the Project

```bash
cd geodb
dub build
```

**Expected Output**:
```
Building geodb ~main (library)...
Compiling...
Build successful!
```

### 2. Start the Server

```bash
dub run
```

**Expected Output**:
```
Starting GeoDatabase REST API...
Server listening on http://localhost:8082
```

### 3. Test with curl

```bash
# Add a location
curl -X POST http://localhost:8082/location \
  -H "Content-Type: application/json" \
  -d '{
    "id": "paris",
    "name": "Paris",
    "latitude": 48.8566,
    "longitude": 2.3522,
    "metadata": {"country": "France"}
  }'

# Get the location
curl http://localhost:8082/location/paris
```

## Common Tasks

### Task 1: Add Multiple Locations

Create a script `add_cities.sh`:

```bash
#!/bin/bash

BASE_URL="http://localhost:8082"

# Paris
curl -X POST "$BASE_URL/location" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "paris",
    "name": "Paris, France",
    "latitude": 48.8566,
    "longitude": 2.3522,
    "metadata": {"population": 2161000}
  }'

# London
curl -X POST "$BASE_URL/location" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "london",
    "name": "London, UK",
    "latitude": 51.5074,
    "longitude": -0.1278,
    "metadata": {"population": 9002488}
  }'

# Berlin
curl -X POST "$BASE_URL/location" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "berlin",
    "name": "Berlin, Germany",
    "latitude": 52.5200,
    "longitude": 13.4050,
    "metadata": {"population": 3645000}
  }'

# Rome
curl -X POST "$BASE_URL/location" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "rome",
    "name": "Rome, Italy",
    "latitude": 41.9028,
    "longitude": 12.4964,
    "metadata": {"population": 2873494}
  }'

# Amsterdam
curl -X POST "$BASE_URL/location" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "amsterdam",
    "name": "Amsterdam, Netherlands",
    "latitude": 52.3676,
    "longitude": 4.9041,
    "metadata": {"population": 873000}
  }'

echo "Added 5 European cities"
```

Run it:
```bash
chmod +x add_cities.sh
./add_cities.sh
```

### Task 2: Find Nearby Locations

Find all cities within 500 km of Paris:

```bash
curl -X POST http://localhost:8082/find-nearby \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 48.8566,
    "longitude": 2.3522,
    "radiusMeters": 500000
  }' | jq .
```

**Expected Response**:
```json
{
  "locations": [
    {
      "id": "paris",
      "name": "Paris, France",
      "latitude": 48.8566,
      "longitude": 2.3522,
      "distance": 0
    },
    {
      "id": "london",
      "name": "London, UK",
      "latitude": 51.5074,
      "longitude": -0.1278,
      "distance": 340900
    }
  ],
  "count": 2
}
```

### Task 3: Find Nearest Cities

Find 3 closest cities to Berlin:

```bash
curl -X POST http://localhost:8082/find-nearest \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 52.5200,
    "longitude": 13.4050,
    "count": 3
  }' | jq .
```

### Task 4: Find Cities in Geographic Region

Find all cities in the rectangle defined by:
- North: 53°
- South: 40°
- East: 15°
- West: -5°

```bash
curl -X POST http://localhost:8082/find-in-bounds \
  -H "Content-Type: application/json" \
  -d '{
    "minLatitude": 40.0,
    "maxLatitude": 53.0,
    "minLongitude": -5.0,
    "maxLongitude": 15.0
  }' | jq .
```

### Task 5: Calculate Distance Between Cities

Distance from Paris to Rome:

```bash
curl -X POST http://localhost:8082/calculate-distance \
  -H "Content-Type: application/json" \
  -d '{
    "fromLatitude": 48.8566,
    "fromLongitude": 2.3522,
    "toLatitude": 41.9028,
    "toLongitude": 12.4964
  }' | jq .
```

**Expected Response**:
```json
{
  "distanceMeters": 1394000,
  "distanceKilometers": 1394.0
}
```

### Task 6: Get Database Statistics

```bash
curl http://localhost:8082/stats | jq .
```

**Expected Response**:
```json
{
  "databaseName": "cities",
  "locationCount": 5
}
```

## D Language Integration

### Using GeoDatabase Programmatically

Create `myapp.d`:

```d
import uim.databases.geodb;
import std.stdio;

void main() {
  // Create database
  auto db = new GeoDatabase("my_cities");
  
  // Add locations
  db.addLocation(new GeoLocation(
    "paris", "Paris",
    GeoPoint(48.8566, 2.3522),
    Json(["country": Json("France")])
  ));
  
  db.addLocation(new GeoLocation(
    "london", "London",
    GeoPoint(51.5074, -0.1278),
    Json(["country": Json("UK")])
  ));
  
  // Find nearby
  auto nearby = db.findNearby(GeoPoint(48.8566, 2.3522), 500000);
  
  writeln("Cities near Paris:");
  foreach (city; nearby) {
    writeln("  - " ~ city.name());
  }
  
  // Get stats
  auto stats = (cast(GeoDatabase)db).getStats();
  writeln("Total cities: " ~ to!string(stats.locationCount));
}
```

Compile and run:
```bash
dmd myapp.d -I=geodb/source
./myapp
```

## Example Programs

### Run Basic Examples

```bash
cd geodb
dub run :geodb-example
```

**Output includes**:
- Database creation
- Location addition and retrieval
- Nearby location searches
- Distance calculations
- Nearest neighbor queries
- Bounding box queries
- Statistics

### Run Advanced Examples

```bash
dub run :geodb-advanced-example
```

**Output includes**:
- Restaurant database (NYC)
- Radius-based searches
- Cuisine filtering
- Rating-based sorting
- Geographic region queries
- Service area analysis
- Multi-criteria search
- Distance matrix generation
- Proximity alerts

## Troubleshooting

### Problem: "Address already in use"

Port 8082 is already occupied. Change the port in `source/app.d`:

```d
// Change from:
listenHTTP("127.0.0.1", 8082, router);

// To:
listenHTTP("127.0.0.1", 9000, router);  // New port
```

Then rebuild:
```bash
dub build
```

### Problem: "Latitude/longitude out of range"

Ensure coordinates are valid:
- Latitude: -90 to 90
- Longitude: -180 to 180

Invalid: `GeoPoint(95.0, 200.0)` ❌
Valid: `GeoPoint(48.8566, 2.3522)` ✓

### Problem: "Location not found"

Verify the location ID exists:

```bash
# List all locations
curl http://localhost:8082/locations | jq .
```

### Problem: "Invalid radius"

Radius must be a positive number (in meters):

Invalid: `radiusMeters: -1000` ❌
Valid: `radiusMeters: 10000` ✓

## Coordinate Reference

### Major World Cities

```
New York:       (40.7128, -74.0060)
Los Angeles:    (34.0522, -118.2437)
London:         (51.5074, -0.1278)
Paris:          (48.8566, 2.3522)
Tokyo:          (35.6762, 139.6503)
Sydney:         (-33.8688, 151.2093)
Rio de Janeiro: (-22.9068, -43.1729)
Dubai:          (25.2048, 55.2708)
Singapore:      (1.3521, 103.8198)
```

## REST API Cheat Sheet

| Operation | Method | URL |
|-----------|--------|-----|
| Add location | POST | `/location` |
| Get location | GET | `/location/{id}` |
| Get all | GET | `/locations` |
| Remove | DELETE | `/location/{id}` |
| Find nearby | POST | `/find-nearby` |
| Find in bounds | POST | `/find-in-bounds` |
| Find nearest | POST | `/find-nearest` |
| Calculate distance | POST | `/calculate-distance` |
| Statistics | GET | `/stats` |

## Next Steps

1. **Read the full API documentation**: See [README.md](README.md)
2. **Explore advanced patterns**: Run `geodb-advanced-example.d`
3. **Build your application**: Use the library in your D projects
4. **Optimize for scale**: Consider spatial index upgrades (R-tree, QuadTree)

## Integration with Other UIM Modules

GeoDatabase can be combined with other UIM database modules:

- **KVStore**: Store location metadata in KVStore
- **ColumnDB**: Analyze location analytics in ColumnDB
- **OLTP**: Use GeoDatabase for spatial components of transactional systems

Example integration:
```d
import uim.databases.geodb;
import uim.databases.kvstore;

auto geoDb = new GeoDatabase("restaurants");
auto kvStore = new KVStore!string;

// Store location metadata
kvStore.set("restaurant_1_hours", "9am-11pm");
kvStore.set("restaurant_1_phone", "+33 1 2345 6789");
```

## Additional Resources

- **D Language**: https://dlang.org
- **vibe.d**: https://vibed.org
- **Haversine Formula**: https://en.wikipedia.org/wiki/Haversine_formula
- **WGS 84 Coordinates**: https://en.wikipedia.org/wiki/World_Geodetic_System

## Support

For issues, consult:
1. [README.md](README.md) - Full API reference
2. `geodb-example.d` - Basic usage examples
3. `geodb-advanced-example.d` - Advanced patterns
4. UIM Framework documentation

---

**Ready to build location-based services? Start with the examples above!**
