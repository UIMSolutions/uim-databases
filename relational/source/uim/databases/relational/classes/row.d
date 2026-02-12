/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes.row;

import uim.databases.relational;

@safe:

/// Row with metadata
class RDBRow : UIMObject, IRDBRow {
  this(Json data) {
    this.data = data;
    this.createdAt = Clock.currTime();
    this.updatedAt = Clock.currTime();
  }

  protected Json _data;
  Json data() {
    return _data; 
  }
  
  IRDBRow data(Json value) {
    this._data = value;
    this.updatedAt = Clock.currTime();
    return this;
  }

  Json data(string key) {
    return _data.hasKey(key) ? _data[key] : Json(null);
  }

  IRDBRow data(string key, Json value) {
    _data[key] = value;
    _updatedAt = Clock.currTime();
    return this;
  }

  protected SysTime _createdAt;
  @property SysTime createdAt() {
    return _createdAt;
  }

  protected SysTime _updatedAt;
  @property SysTime updatedAt() {
    return _updatedAt;
  }

  IRDBRow update(Json newData) {
    this.data = newData;
    _updatedAt = Clock.currTime();
    return this;
  }

  static RDBRow opCall(string jsonString) {
    auto data = parseJsonString(jsonString);
    return RDBRow(data);
  }

  static RDBRow opCall(Json data) {
    return new RDBRow(data);
  }
}
///
unittest {
  import std.stdio;
  import std.json;
  import std.datetime;
  
  void testRow() {
    auto row = RDBRow(`{ "id": 1, "name": "Alice" }`);
    assert(row.data["id"] == 1);
    assert(row.data["name"] == "Alice");
    
    auto createdAt = row.createdAt;
    auto updatedAt = row.updatedAt;
    
    // Wait a bit and update the row
    Thread.sleep(100.msecs);
    row.update(`{ "id": 1, "name": "Bob" }`);
    
    assert(row.data["id"] == 1);
    assert(row.data["name"] == "Bob");
    assert(row.createdAt == createdAt); // createdAt should not change
    assert(row.updatedAt > updatedAt); // updatedAt should be newer
  }
}
