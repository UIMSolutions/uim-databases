/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes;

import uim.databases.relational;

@safe:

/// Row with metadata
struct Row {
  Json data;
  SysTime createdAt;
  SysTime updatedAt;

  this(Json data) {
    this.data = data;
    this.createdAt = Clock.currTime();
    this.updatedAt = Clock.currTime();
  }

  void update(Json newData) {
    this.data = newData;
    this.updatedAt = Clock.currTime();
  }
}
