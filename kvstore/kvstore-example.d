/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module kvstore.kvstore-example;

import uim.databases.kvstore;
import std.stdio;
import std.format;

void main() {
  writeln("=== Key-Value Store Examples ===\n");

  // Example 1: In-Memory Store
  writeln("Example 1: In-Memory Store");
  writeln("---------");
  auto memStore = new KVStore("main");

  memStore.set("username", "alice");
  memStore.set("email", "alice@example.com");
  memStore.set("age", "30");

  writeln("Stored 3 key-value pairs");
  writeln("Username: ", memStore.get("username"));
  writeln("Email: ", memStore.get("email"));
  writeln("Total keys: ", memStore.count());
  writeln("All keys: ", memStore.keys());
  writeln();

  // Example 2: Multi-set and Multi-get
  writeln("Example 2: Multi-set and Multi-get");
  writeln("---------");
  string[string] userData = [
    "name": "Bob",
    "surname": "Smith",
    "city": "New York",
    "country": "USA"
  ];
  memStore.multiSet(userData);
  writeln("Stored 4 user data pairs");

  string[] keysToRetrieve = ["name", "surname", "city", "country"];
  auto retrieved = memStore.multiGet(keysToRetrieve);
  foreach (key, value; retrieved) {
    writeln(format("  %s: %s", key, value));
  }
  writeln();

  // Example 3: Check existence and statistics
  writeln("Example 3: Check existence");
  writeln("---------");
  writeln("'username' exists: ", memStore.exists("username"));
  writeln("'nonexistent' exists: ", memStore.exists("nonexistent"));
  writeln("Total keys in store: ", memStore.count());
  writeln();

  // Example 4: Exception handling
  writeln("Example 4: Exception Handling");
  writeln("---------");
  try {
    string value = memStore.get("does_not_exist");
  } catch (KeyNotFoundException e) {
    writeln("Caught exception: ", e.msg);
  }
  writeln();

  // Example 5: Remove operations
  writeln("Example 5: Remove Operations");
  writeln("---------");
  writeln("Keys before: ", memStore.keys());
  writeln("Removing 'age'...");
  memStore.remove("age");
  writeln("Keys after: ", memStore.keys());
  writeln("Total keys: ", memStore.count());
  writeln();

  // Example 6: Persistent Store
  writeln("Example 6: Persistent Store");
  writeln("---------");
  auto persistStore = new PersistentKVStore("./example_kvstore.json");
  
  persistStore.set("config_db_host", "localhost");
  persistStore.set("config_db_port", "5432");
  persistStore.set("config_api_key", "secret123");
  
  writeln("Stored persistent data");
  writeln("Config DBHost: ", persistStore.get("config_db_host"));
  writeln("Persistent store saved to: ", persistStore.storagePath());
  writeln();

  // Example 7: Clear store
  writeln("Example 7: Clear Store");
  writeln("---------");
  auto tempStore = new KVStore("temp");
  tempStore.set("temp1", "value1");
  tempStore.set("temp2", "value2");
  writeln("Temp store keys before clear: ", tempStore.count());
  tempStore.clear();
  writeln("Temp store keys after clear: ", tempStore.count());
  writeln();

  writeln("=== Examples Complete ===");
}
