/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Wire format of the REST API, kept apart from the application DTOs so the HTTP contract can evolve on its own.
module uim.databases.vector.presentation.rest.models;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

// --- Requests ---

struct RestCreateCollection {
  string name;
  ulong dimension;
  /// EUCLIDEAN (default), COSINE, MANHATTAN or DOT_PRODUCT.
  @optional string metric;
}

struct RestVectorInput {
  string id;
  double[] values;
  @optional string[string] metadata;
}

struct RestVectorBatch {
  RestVectorInput[] vectors;
}

/// An absent (or null) field keeps the current value.
struct RestVectorUpdate {
  @optional Nullable!(double[]) values;
  @optional Nullable!(string[string]) metadata;
}

struct RestSearchRequest {
  double[] vector;
  @optional ulong k = 10;
  @optional string[string] filter;
  @optional bool includeValues;
}

struct RestSimilarRequest {
  @optional ulong k = 10;
  @optional string[string] filter;
  @optional bool includeValues;
}

struct RestFilterRequest {
  string[string] metadata;
}

// --- Responses ---

struct RestHealth {
  string status;
  string type;
  ulong collectionCount;
}

struct RestCollection {
  string name;
  ulong dimension;
  string metric;
  ulong count;
}

struct RestCollectionList {
  RestCollection[] collections;
  ulong count;
}

struct RestStats {
  string name;
  ulong collectionCount;
  ulong vectorCount;
  RestCollection[] collections;
}

struct RestVector {
  string id;
  double[] values;
  string[string] metadata;
}

struct RestVectorList {
  RestVector[] vectors;
  ulong count;
}

struct RestIdList {
  string[] ids;
  ulong count;
}

struct RestHit {
  string id;
  double distance;
  string[string] metadata;
  /// null unless `includeValues` was set.
  Nullable!(double[]) values;
}

struct RestSearchResponse {
  RestHit[] results;
  ulong count;
}

struct RestMessage {
  string message;
}
