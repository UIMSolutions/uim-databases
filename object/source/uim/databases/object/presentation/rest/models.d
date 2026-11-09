/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Wire format of the REST API, kept apart from the application DTOs so the HTTP contract can evolve on its own.
module uim.databases.object.presentation.rest.models;

import std.typecons : Nullable;
import vibe.data.json : Json;
import vibe.data.serialization : name, optional;

@safe:

// --- Requests ---

struct RestCondition {
  /// Dot-separated path, e.g. `address.city`.
  string field;
  /// ==, !=, >, <, >=, <=, contains, in, exists (also eq, ne, gt, lt, gte, lte).
  @optional string op = "==";
  /// Absent means null; `exists` treats null as true.
  @optional Json value;
}

struct RestSort {
  string field;
  @optional bool ascending = true;
}

struct RestFindRequest {
  @optional RestCondition[] where;
  @optional Nullable!RestSort sort;
  @optional ulong skip;
  /// 0 means no limit.
  @optional ulong limit;
}

struct RestCountRequest {
  @optional RestCondition[] where;
}

struct RestBulkInsert {
  Json[] documents;
}

struct RestCreateIndex {
  string field;
}

// --- Responses ---

struct RestHealth {
  string status;
  string type;
  ulong collectionCount;
}

struct RestCollection {
  string name;
  ulong documentCount;
  ulong indexCount;
  string[] indexes;
}

struct RestCollectionList {
  RestCollection[] collections;
  ulong count;
}

struct RestStats {
  string name;
  ulong collectionCount;
  ulong documentCount;
  RestCollection[] collections;
}

struct RestDocument {
  @name("_id") string id;
  Json data;
  string createdAt;
  string updatedAt;
}

struct RestDocumentList {
  RestDocument[] documents;
  ulong count;
}

struct RestBulkResult {
  ulong inserted;
  string[] ids;
}

struct RestCount {
  ulong count;
}

struct RestIndex {
  string field;
}

struct RestIndexList {
  string[] indexes;
  ulong count;
}

struct RestMessage {
  string message;
}
