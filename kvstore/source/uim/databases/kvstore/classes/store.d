/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.kvstore.classes.store;

import uim.databases.kvstore;
import std.datetime;

@safe:

/// In-memory key-value store with optional persistence
class KVStore : IKVStore {
  this(string name = "default") {
    _name = name;
    _data = new string[string];
    _metadata = new KVMetadata[string];
  }

  private {
    string _name;
    string[string] _data;
    KVMetadata[string] _metadata;
  }

  /// Store name
  string name() const {
    return _name;
  }

  /// Get a value by key
  override string get(string key) {
    if (key !in _data) {
      throw new KeyNotFoundException(key);
    }
    auto meta = _metadata[key];
    meta.lastAccess = Clock.currTime();
    _metadata[key] = meta;
    return _data[key];
  }

  /// Set a key-value pair
  override void set(string key, string value) {
    _data[key] = value;
    _metadata[key] = KVMetadata(Clock.currTime(), Clock.currTime());
  }

  /// Delete a key
  override void remove(string key) {
    if (key !in _data) {
      throw new KeyNotFoundException(key);
    }
    _data.remove(key);
    _metadata.remove(key);
  }

  /// Check if key exists
  override bool exists(string key) const {
    return (key in _data) !is null;
  }

  /// Get all keys
  override string[] keys() const {
    return _data.keys;
  }

  /// Get key count
  override size_t count() const {
    return _data.length;
  }

  /// Clear all data
  override void clear() {
    _data.clear();
    _metadata.clear();
  }

  /// Get multiple values
  override string[string] multiGet(string[] keys) {
    string[string] result;
    foreach (key; keys) {
      try {
        result[key] = get(key);
      } catch (KeyNotFoundException) {
        // Skip missing keys
      }
    }
    return result;
  }

  /// Set multiple values
  override void multiSet(string[string] pairs) {
    foreach (key, value; pairs) {
      set(key, value);
    }
  }

  /// Get metadata for a key
  KVMetadata getMetadata(string key) const {
    if (key !in _metadata) {
      throw new KeyNotFoundException(key);
    }
    return _metadata[key];
  }

  /// Get store statistics
  StoreStats getStats() const {
    StoreStats stats;
    stats.totalKeys = _data.length;
    foreach (meta; _metadata) {
      if (!stats.oldestAccess.isNull || meta.lastAccess < stats.oldestAccess) {
        stats.oldestAccess = meta.lastAccess;
      }
      if (stats.newestAccess.isNull || meta.lastAccess > stats.newestAccess) {
        stats.newestAccess = meta.lastAccess;
      }
    }
    return stats;
  }
}

/// Metadata for each key-value entry
struct KVMetadata {
  SysTime created;
  SysTime lastAccess;
}

/// Store statistics
struct StoreStats {
  size_t totalKeys;
  Nullable!SysTime oldestAccess;
  Nullable!SysTime newestAccess;
}
