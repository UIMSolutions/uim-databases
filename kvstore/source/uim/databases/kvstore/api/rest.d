/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.kvstore.api.rest;

import uim.databases.kvstore;
import vibe.d;

@safe:

/// Request/Response structs for REST API
struct GetResponse {
  bool success;
  string key;
  string value;
  string error;
}

struct SetRequest {
  string key;
  string value;
}

struct DeleteResponse {
  bool success;
  string key;
  string error;
}

struct ExistsResponse {
  bool exists;
  string key;
}

struct KeysResponse {
  string[] keys;
  size_t count;
}

struct StatsResponse {
  size_t totalKeys;
  size_t availableKeys;
}

struct MultiSetRequest {
  string[string] pairs;
}

struct MultiGetResponse {
  string[string] values;
  size_t found;
  size_t requested;
}

/// REST API endpoint handler
class KVStoreAPI {
  private IKVStore store;

  this(IKVStore store) {
    this.store = store;
  }

  // GET /kvstore/:key - Get a value
  @method(HTTPMethod.GET)
  @path("/kvstore/:key")
  GetResponse get(string _key) {
    GetResponse response;
    response.key = _key;
    try {
      response.value = store.get(_key);
      response.success = true;
    } catch (KeyNotFoundException e) {
      response.success = false;
      response.error = e.msg;
    }
    return response;
  }

  // POST /kvstore - Set a value
  @method(HTTPMethod.POST)
  @path("/kvstore")
  Json set(SetRequest req) {
    Json response = Json.emptyObject;
    try {
      store.set(req.key, req.value);
      response["success"] = true;
      response["key"] = req.key;
      response["message"] = "Value stored successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // DELETE /kvstore/:key - Delete a value
  @method(HTTPMethod.DELETE)
  @path("/kvstore/:key")
  DeleteResponse remove(string _key) {
    DeleteResponse response;
    response.key = _key;
    try {
      store.remove(_key);
      response.success = true;
    } catch (KeyNotFoundException e) {
      response.success = false;
      response.error = e.msg;
    }
    return response;
  }

  // GET /kvstore/check/:key - Check if key exists
  @method(HTTPMethod.GET)
  @path("/kvstore/check/:key")
  ExistsResponse exists(string _key) {
    ExistsResponse response;
    response.key = _key;
    response.exists = store.exists(_key);
    return response;
  }

  // GET /kvstore/keys - Get all keys
  @method(HTTPMethod.GET)
  @path("/kvstore/keys")
  KeysResponse getKeys() {
    KeysResponse response;
    response.keys = store.keys();
    response.count = store.count();
    return response;
  }

  // GET /kvstore/stats - Get store statistics
  @method(HTTPMethod.GET)
  @path("/kvstore/stats")
  StatsResponse getStats() {
    StatsResponse response;
    response.totalKeys = store.count();
    response.availableKeys = store.keys().length;
    return response;
  }

  // POST /kvstore/multi - Set multiple values
  @method(HTTPMethod.POST)
  @path("/kvstore/multi")
  Json multiSet(MultiSetRequest req) {
    Json response = Json.emptyObject;
    try {
      store.multiSet(req.pairs);
      response["success"] = true;
      response["count"] = req.pairs.length;
      response["message"] = "Multiple values stored successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /kvstore/multi-get - Get multiple values
  @method(HTTPMethod.POST)
  @path("/kvstore/multi-get")
  MultiGetResponse multiGet(string[] keys) {
    MultiGetResponse response;
    response.values = store.multiGet(keys);
    response.found = response.values.length;
    response.requested = keys.length;
    return response;
  }

  // DELETE /kvstore - Clear all data
  @method(HTTPMethod.DELETE)
  @path("/kvstore")
  Json clear() {
    Json response = Json.emptyObject;
    try {
      store.clear();
      response["success"] = true;
      response["message"] = "Store cleared successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }
}
