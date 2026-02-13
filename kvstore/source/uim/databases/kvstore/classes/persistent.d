/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.kvstore.classes.persistent;

import uim.databases.kvstore;
import std.file;
import std.json;
import std.path;

@safe:

/// File-based persistent key-value store
class PersistentKVStore : IKVStore {
  this(string storagePath = "./kvstore.json") {
    _storagePath = storagePath;
    _data = new string[string];
    load();
  }

  private {
    string _storagePath;
    string[string] _data;
  }

  /// Load data from disk
  void load() {
    if (exists(_storagePath)) {
      try {
        auto content = readText(_storagePath);
        auto json = parseJson(content);
        if (json.type == Json.Type.object) {
          foreach (key, value; json.byKeyValue()) {
            if (value.type == Json.Type.string) {
              _data[key] = value.get!string;
            }
          }
        }
      } catch (Exception e) {
        throw new StoreException("Failed to load store: " ~ e.msg);
      }
    }
  }

  /// Save data to disk
  void save() {
    try {
      ensureDir(dirName(_storagePath));
      JSONValue json = JSONValue.emptyObject;
      foreach (key, value; _data) {
        json[key] = value;
      }
      write(_storagePath, json.toPrettyString());
    } catch (Exception e) {
      throw new StoreException("Failed to save store: " ~ e.msg);
    }
  }

  override string get(string key) {
    if (key !in _data) {
      throw new KeyNotFoundException(key);
    }
    return _data[key];
  }

  override void set(string key, string value) {
    _data[key] = value;
    save();
  }

  override void remove(string key) {
    if (key !in _data) {
      throw new KeyNotFoundException(key);
    }
    _data.remove(key);
    save();
  }

  override bool exists(string key) const {
    return (key in _data) !is null;
  }

  override string[] keys() const {
    return _data.keys;
  }

  override size_t count() const {
    return _data.length;
  }

  override void clear() {
    _data.clear();
    save();
  }

  override string[string] multiGet(string[] keys) {
    string[string] result;
    foreach (key; keys) {
      try {
        result[key] = get(key);
      } catch (KeyNotFoundException) {}
    }
    return result;
  }

  override void multiSet(string[string] pairs) {
    foreach (key, value; pairs) {
      _data[key] = value;
    }
    save();
  }

  /// Get storage path
  string storagePath() const {
    return _storagePath;
  }
}
