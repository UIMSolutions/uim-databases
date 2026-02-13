/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.kvstore.interfaces.store;

@safe:

/// Key-Value Store Interface
interface IKVStore {
  /// Get a value by key
  string get(string key);
  
  /// Set a key-value pair
  void set(string key, string value);
  
  /// Delete a key
  void remove(string key);
  
  /// Check if key exists
  bool exists(string key);
  
  /// Get all keys
  string[] keys();
  
  /// Get key count
  size_t count();
  
  /// Clear all data
  void clear();
  
  /// Get multiple values
  string[string] multiGet(string[] keys);
  
  /// Set multiple values
  void multiSet(string[string] pairs);
}
