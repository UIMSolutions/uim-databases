/****************************************************************************************************************
* Advanced Key-Value Store Usage Examples
* Demonstrates real-world scenarios and patterns
*****************************************************************************************************************/
module kvstore.kvstore-advanced-example;

import uim.databases.kvstore;
import std.stdio;
import std.format;
import std.json;
import std.conv;

/// Example 1: Session Storage
void sessionStorageExample() {
  writeln("=== Example 1: Session Storage ===");
  auto sessions = new KVStore("sessions");
  
  // Create session
  string sessionId = "sess_12345";
  sessions.set(sessionId, `{"user":"john","ip":"192.168.1.1","created":1702000000}`);
  
  writeln("Session created: ", sessionId);
  writeln("Session data: ", sessions.get(sessionId));
  writeln();
}

/// Example 2: Cache Layer
void cacheExample() {
  writeln("=== Example 2: Cache Layer ===");
  auto cache = new KVStore("cache");
  
  // Function to get user data with caching
  auto getCachedUser = (int userId) {
    string key = format("user_%d", userId);
    
    if (cache.exists(key)) {
      writeln("Cache HIT for user ", userId);
      return cache.get(key);
    }
    
    // Simulate database lookup
    writeln("Cache MISS - fetching from database...");
    string userData = format(`{"id":%d,"name":"User %d","email":"user%d@example.com"}`, 
                             userId, userId, userId);
    cache.set(key, userData);
    return userData;
  };
  
  writeln("First call (cache miss):");
  getCachedUser(1);
  
  writeln("\nSecond call (cache hit):");
  getCachedUser(1);
  writeln();
}

/// Example 3: Configuration Management
void configurationExample() {
  writeln("=== Example 3: Configuration Management ===");
  auto config = new PersistentKVStore("./app_config.json");
  
  // Set configuration values
  config.multiSet([
    "app.name": "MyApplication",
    "app.version": "1.0.0",
    "database.host": "localhost",
    "database.port": "5432",
    "database.name": "mydb",
    "api.timeout": "30000",
    "api.max_retries": "3",
    "logging.level": "INFO",
    "logging.format": "json"
  ]);
  
  writeln("Configuration saved to: ", config.storagePath());
  writeln("Database host: ", config.get("database.host"));
  writeln("API timeout: ", config.get("api.timeout"));
  writeln();
}

/// Example 4: Feature Flags
void featureFlagsExample() {
  writeln("=== Example 4: Feature Flags ===");
  auto flags = new KVStore("features");
  
  // Set feature flags
  flags.multiSet([
    "feature.dark_mode": "true",
    "feature.beta_api": "false",
    "feature.new_ui": "true",
    "feature.analytics": "true",
    "feature.experimental": "false"
  ]);
  
  // Check features
  string[] enabledFeatures;
  foreach (key; flags.keys()) {
    if (flags.get(key) == "true") {
      enabledFeatures ~= key.replace("feature.", "");
    }
  }
  
  writeln("Enabled features: ", enabledFeatures);
  writeln();
}

/// Example 5: Rate Limiting
void rateLimitingExample() {
  writeln("=== Example 5: Rate Limiting ===");
  auto limits = new KVStore("rate_limits");
  
  // Function to track API calls
  auto trackAPICall = (string clientId) {
    string key = format("api_calls_%s", clientId);
    int count = 0;
    
    if (limits.exists(key)) {
      count = to!int(limits.get(key));
    }
    
    count++;
    limits.set(key, to!string(count));
    
    int limit = 100;
    if (count > limit) {
      return format("Rate limit exceeded for %s (%d/%d)", clientId, count, limit);
    }
    return format("API call %d/%d for %s - OK", count, limit, clientId);
  };
  
  writeln(trackAPICall("client_1"));
  writeln(trackAPICall("client_1"));
  writeln(trackAPICall("client_2"));
  writeln();
}

/// Example 6: User Preferences
void userPreferencesExample() {
  writeln("=== Example 6: User Preferences ===");
  auto prefs = new PersistentKVStore("./user_prefs.json");
  
  // User 1 preferences
  prefs.multiSet([
    "user_1::theme": "dark",
    "user_1::language": "en",
    "user_1::notifications": "true",
    "user_1::timezone": "UTC",
    "user_1::date_format": "yyyy-MM-dd"
  ]);
  
  // User 2 preferences
  prefs.multiSet([
    "user_2::theme": "light",
    "user_2::language": "de",
    "user_2::notifications": "false",
    "user_2::timezone": "CET",
    "user_2::date_format": "dd.MM.yyyy"
  ]);
  
  writeln("User 1 theme: ", prefs.get("user_1::theme"));
  writeln("User 2 theme: ", prefs.get("user_2::theme"));
  writeln("User 2 language: ", prefs.get("user_2::language"));
  writeln();
}

/// Example 7: Visitor Analytics
void analyticsExample() {
  writeln("=== Example 7: Visitor Analytics ===");
  auto stats = new KVStore("analytics");
  
  // Track page visits
  auto trackPageView = (string page) {
    string key = format("pageview_%s", page);
    int count = 0;
    if (stats.exists(key)) {
      count = to!int(stats.get(key));
    }
    stats.set(key, to!string(count + 1));
  };
  
  // Simulate page visits
  trackPageView("home");
  trackPageView("about");
  trackPageView("home");
  trackPageView("products");
  trackPageView("home");
  trackPageView("products");
  
  writeln("Page views:");
  foreach (key; stats.keys()) {
    string page = key.replace("pageview_", "");
    int count = to!int(stats.get(key));
    writeln(format("  %s: %d views", page, count));
  }
  writeln();
}

/// Example 8: Error Handling Patterns
void errorHandlingExample() {
  writeln("=== Example 8: Error Handling Patterns ===");
  auto store = new KVStore("error_demo");
  
  // Pattern 1: Safe get with default
  auto safeGet = (string key, string defaultValue = "") {
    try {
      return store.get(key);
    } catch (KeyNotFoundException) {
      return defaultValue;
    }
  };
  
  store.set("existing_key", "value123");
  writeln("Existing key: ", safeGet("existing_key"));
  writeln("Missing key (with default): ", safeGet("missing_key", "N/A"));
  
  // Pattern 2: Batch get with error checking
  auto keys = ["existing_key", "missing_key", "another_missing"];
  writeln("Batch get (non-throwing):");
  auto results = store.multiGet(keys);
  foreach (key; keys) {
    if (key in results) {
      writeln(format("  %s: %s", key, results[key]));
    } else {
      writeln(format("  %s: (not found)", key));
    }
  }
  writeln();
}

void main() {
  writeln("\n╔════════════════════════════════════════════════════════╗");
  writeln("║    Advanced Key-Value Store Usage Examples            ║");
  writeln("╚════════════════════════════════════════════════════════╝\n");

  sessionStorageExample();
  cacheExample();
  configurationExample();
  featureFlagsExample();
  rateLimitingExample();
  userPreferencesExample();
  analyticsExample();
  errorHandlingExample();

  writeln("╔════════════════════════════════════════════════════════╗");
  writeln("║    All Examples Completed Successfully                ║");
  writeln("╚════════════════════════════════════════════════════════╝\n");
}
