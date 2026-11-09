/// Results leaving the driving ports.
module uim.databases.object.application.dtos.results;

import uim.databases.object.domain;
import std.json : JSONValue;

@safe:

struct CollectionInfo {
  string name;
  size_t documentCount;
  string[] indexes;

  static CollectionInfo from(const DocumentCollection collection) {
    return CollectionInfo(collection.name, collection.count, collection.indexedFields);
  }
}

struct DocumentData {
  string id;
  JSONValue data;
  /// ISO 8601.
  string createdAt;
  string updatedAt;

  static DocumentData from(const Document document) {
    return DocumentData(document.id, document.data, document.createdAt.toISOExtString(),
      document.updatedAt.toISOExtString());
  }
}

struct DatabaseStatistics {
  string name;
  size_t collectionCount;
  size_t documentCount;
  CollectionInfo[] collections;
}

struct HealthStatus {
  string status;
  string type;
  size_t collectionCount;
}
