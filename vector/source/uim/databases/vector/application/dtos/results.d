/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Results leaving the driving ports.
module uim.databases.vector.application.dtos.results;

import uim.databases.vector.domain;
import std.conv : to;

@safe:

struct CollectionInfo {
  string name;
  size_t dimension;
  string metric;
  size_t count;

  static CollectionInfo from(const VectorCollection collection) {
    return CollectionInfo(collection.name, collection.dimension, collection.metric.to!string, collection.count);
  }
}

struct VectorData {
  string id;
  double[] values;
  string[string] metadata;

  static VectorData from(const VectorRecord record) {
    return VectorData(record.id, record.embedding.values.dup, record.metadata);
  }
}

struct SearchMatch {
  VectorData vector;
  double distance;

  static SearchMatch from(const SearchHit hit) {
    return SearchMatch(VectorData.from(hit.record), hit.distance);
  }
}

struct DatabaseStatistics {
  string name;
  size_t collectionCount;
  size_t vectorCount;
  CollectionInfo[] collections;
}

struct HealthStatus {
  string status;
  string type;
  size_t collectionCount;
}
