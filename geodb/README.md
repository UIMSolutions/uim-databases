# GeoDatabase Module

A high-performance geospatial database implementation in D language using the vibe.d framework. Provides location-based storage, proximity searching, and geographic analysis capabilities.

## Features

- **Geographic Point Storage**: Store and manage locations with latitude/longitude coordinates
- **Proximity Search**: Find locations within a specified radius using bounding box optimization
- **Radius-based Queries**: Efficient nearby location discovery with radius constraints
- **K-Nearest Neighbor**: Find N closest locations to a point
- **Bounding Box Queries**: Search within geographic regions
- **Distance Calculation**: Haversine formula for accurate geodetic distances
- **Metadata Storage**: Attach arbitrary JSON metadata to locations
- **Statistics Tracking**: Database statistics and location counts
- **REST API**: Complete HTTP API for all operations
- **Type Safety**: Full @safe D implementation with compile-time guarantees

## Architecture

```
GeoDatabase (Main Storage)
  ├── GeoIndex (Spatial Indexing)
  │   ├── GeoLocation entries
  │   └── Query operations
  ├── GeoPoint (Coordinate representation)
  ├── GeoBounds (Geographic regions)
  └── Statistics tracking
```

## Quick Start

### Building

```bash
cd geodb
dub build
```

### Running the Server

```bash
dub run
```

The server listens on **http://localhost:8082**

### D Language Usage

```d
import uim.databases.geodb;
import std.stdio;

void main() {
  auto db = new GeoDatabase("restaurants");
  
  // Add a location
  db.addLocation(new GeoLocation(
    "loc1", "Paris", 
    GeoPoint(48.8566, 2.3522),
    Json(["country": Json("France")])
  ));
  
  // Find nearby locations
  auto nearby = db.findNearby(GeoPoint(48.8500, 2.3500), 10000);  // 10 km
  
  // Get location
  auto loc = db.getLocation("loc1");
  writeln(loc.name());
}
```

## REST API Reference

### 1. Add Location

**Endpoint**: `POST /location`

**Request**:
```json
{
  "id": "loc1",
  "name": "Paris",
  "latitude": 48.8566,
  "longitude": 2.3522,
  "metadata": {
    "country": "France",
    "population": 2161000
  }
}
```

**Response**:
```json
{
  "success": true,
  "message": "Location added successfully"
}
```

**Status Codes**:
- `200 OK`: Location added
- `400 Bad Request`: Invalid coordinates
- `409 Conflict`: Location ID already exists

---

### 2. Get Location

**Endpoint**: `GET /location/{id}`

**Response**:
```json
{
  "id": "loc1",
  "name": "Paris",
  "latitude": 48.8566,
  "longitude": 2.3522,
  "metadata": {
    "country": "France"
  }
}
```

**Status Codes**:
- `200 OK`: Location found
- `404 Not Found`: Location doesn't exist

---

### 3. Get All Locations

**Endpoint**: `GET /locations`

**Response**:
```json
{
  "locations": [
    {
      "id": "loc1",
      "name": "Paris",
      "latitude": 48.8566,
      "longitude": 2.3522,
      "metadata": {}
    }
  ]
}
```

**Status Codes**:
- `200 OK`: Success

---

### 4. Remove Location

**Endpoint**: `DELETE /location/{id}`

**Response**:
```json
{
  "success": true,
  "message": "Location removed successfully"
}
```

**Status Codes**:
- `200 OK`: Location removed
- `404 Not Found`: Location doesn't exist

---

### 5. Find Nearby Locations

**Endpoint**: `POST /find-nearby`

**Request**:
```json
{
  "latitude": 48.8566,
  "longitude": 2.3522,
  "radiusMeters": 10000
}
```

**Response**:
```json
{
  "locations": [
    {
      "id": "loc2",
      "name": "London",
      "latitude": 51.5074,
      "longitude": -0.1278,
      "distance": 340000
    }
  ],
  "count": 1
}
```

**Status Codes**:
- `200 OK`: Success
- `400 Bad Request`: Invalid coordinates or radius

---

### 6. Find Locations in Bounding Box

**Endpoint**: `POST /find-in-bounds`

**Request**:
```json
{
  "minLatitude": 40.0,
  "maxLatitude": 50.0,
  "minLongitude": -5.0,
  "maxLongitude": 10.0
}
```

**Response**:
```json
{
  "locations": [
    {
      "id": "loc1",
      "name": "Paris",
      "latitude": 48.8566,
      "longitude": 2.3522
    }
  ],
  "count": 1
}
```

**Status Codes**:
- `200 OK`: Success
- `400 Bad Request`: Invalid bounds

---

### 7. Find Nearest Locations

**Endpoint**: `POST /find-nearest`

**Request**:
```json
{
  "latitude": 48.8566,
  "longitude": 2.3522,
  "count": 3
}
```

**Response**:
```json
{
  "locations": [
    {
      "id": "loc2",
      "name": "London",
      "latitude": 51.5074,
      "longitude": -0.1278,
      "distance": 340000
    }
  ],
  "count": 1
}
```

**Status Codes**:
- `200 OK`: Success
- `400 Bad Request`: Invalid K value

---

### 8. Calculate Distance

**Endpoint**: `POST /calculate-distance`

**Request**:
```json
{
  "fromLatitude": 48.8566,
  "fromLongitude": 2.3522,
  "toLatitude": 51.5074,
  "toLongitude": -0.1278
}
```

**Response**:
```json
{
  "distanceMeters": 340000,
  "distanceKilometers": 340.0
}
```

**Status Codes**:
- `200 OK`: Success
- `400 Bad Request`: Invalid coordinates

---

### 9. Database Statistics

**Endpoint**: `GET /stats`

**Response**:
```json
{
  "databaseName": "restaurants",
  "locationCount": 25
}
```

**Status Codes**:
- `200 OK`: Success

---

## Coordinate System

### Valid Ranges
- **Latitude**: [-90, 90] degrees (South/North pole)
- **Longitude**: [-180, 180] degrees (International Date Line)

### Examples
```
Paris:       (48.8566, 2.3522)
London:      (51.5074, -0.1278)
New York:    (40.7128, -74.0060)
Sydney:      (-33.8688, 151.2093)
Tokyo:       (35.6762, 139.6503)
```

## Distance Calculations

### Haversine Formula

The module uses the Haversine formula for accurate geodetic distance calculations:

```
a = sin²(Δφ/2) + cos φ1 ⋅ cos φ2 ⋅ sin²(Δλ/2)
c = 2 ⋅ atan2( √a, √(1−a) )
d = R ⋅ c
```

Where:
- `φ` = latitude, `λ` = longitude
- `R` = Earth's radius (6,371,000 meters)
- `d` = distance in meters

### Example: Paris to London
- Distance: ~340 km
- Accuracy: Within 0.5% of geodetic distance

## Advanced Usage

### Proximity Alerts

```d
double alertRadius = 5000;  // 5 km
auto userLocation = GeoPoint(48.8566, 2.3522);
auto nearby = db.findNearby(userLocation, alertRadius);

foreach (location; nearby) {
  double distance = location.distanceToPoint(userLocation);
  writeln("Alert: " ~ location.name() ~ " is " ~ 
    to!string(distance/1000) ~ " km away");
}
```

### Multi-Criteria Filtering

```d
auto allLocations = db.getAllLocations();
auto filtered = allLocations
  .filter!(loc => loc.metadata()["rating"].get!double >= 4.5)
  .filter!(loc => loc.distanceToPoint(center) <= 5000)
  .array();
```

### Distance Matrix

```d
auto locations = db.getAllLocations();
double[][] distances;

foreach (loc1; locations) {
  double[] row;
  foreach (loc2; locations) {
    row ~= loc1.distanceToPoint(loc2.point());
  }
  distances ~= row;
}
```

## Performance Characteristics

| Operation | Time Complexity | Notes |
|-----------|-----------------|-------|
| Add Location | O(1) | Constant time insertion |
| Get Location | O(1) | Direct hash lookup |
| Remove Location | O(1) | Direct hash removal |
| Find Nearby | O(n) | Linear scan, bounding box optimized |
| Find In Bounds | O(n) | Linear scan with bounds check |
| Find Nearest | O(n log k) | Partial sort for K elements |
| Calculate Distance | O(1) | Haversine computation |

### Optimization Notes
- Bounding box pre-filtering reduces distance calculations by ~90%
- K-nearest uses partial heap sort (faster than full sort for small K)
- Spatial index designed for next optimization phase (R-tree, QuadTree)

## Use Cases

### 1. Location-Based Services
- Find restaurants/shops near user
- Proximity-based notifications
- Check-in services

### 2. Logistics & Delivery
- Route optimization
- Service area coverage
- Fleet management

### 3. Real Estate
- Property searches by location
- Neighborhood analysis
- Market area definition

### 4. Travel & Tourism
- Attraction discovery
- Itinerary planning
- Distance calculation

### 5. Emergency Services
- Nearest facility location
- Response time estimation
- Coverage analysis

## Error Handling

### InvalidCoordinatesException
Thrown when coordinates are outside valid ranges:
```d
try {
  auto loc = new GeoLocation("loc1", "Invalid", 
    GeoPoint(95.0, 200.0), Json());  // Invalid!
} catch (InvalidCoordinatesException e) {
  writeln("Error: " ~ e.msg);
}
```

### LocationNotFoundException
Thrown when querying non-existent locations:
```d
try {
  auto loc = db.getLocation("nonexistent");
} catch (LocationNotFoundException e) {
  writeln("Location not found");
}
```

### GeoOperationException
Thrown during invalid operations:
```d
try {
  auto result = db.findNearest(GeoPoint(48.8, 2.3), 0);  // Invalid K
} catch (GeoOperationException e) {
  writeln("Operation failed");
}
```

## Dependencies

- **D Language**: Version 2.101.0 or later
- **vibe.d**: ~0.9.0 (REST framework)
- **uim-framework**: ~26.2.2 (Core utilities)

## File Structure

```
geodb/
├── dub.sdl                    # Build configuration
├── dub.selections.json        # Locked dependencies
├── LICENSE                    # Apache 2.0
├── README.md                  # This file
├── GETTING-STARTED.md         # Quick start guide
├── geodb-example.d            # Basic examples
├── geodb-advanced-example.d   # Advanced patterns
├── source/
│   ├── app.d                  # Server entry point
│   └── uim/
│       └── databases/
│           └── geodb/
│               ├── package.d
│               ├── interfaces/
│               │   └── geo.d
│               ├── errors/
│               │   └── exceptions.d
│               ├── classes/
│               │   ├── location.d
│               │   ├── index.d
│               │   └── database.d
│               └── api/
│                   └── rest.d
```

## Testing

Run the example files:

```bash
# Basic examples
dub run :geodb-example

# Advanced examples
dub run :geodb-advanced-example
```

## Integration with UIM Framework

GeoDatabase follows UIM design patterns:
- Interface-based architecture (IGeoDatabase, IGeoIndex, IGeoLocation)
- Consistent error handling and exceptions
- Modular package structure
- JSON-based REST API
- @safe annotations throughout

## License

Licensed under the Apache License 2.0. See LICENSE file for details.

## Examples

See:
- `geodb-example.d` - 10 basic usage examples
- `geodb-advanced-example.d` - 10 advanced and real-world patterns
