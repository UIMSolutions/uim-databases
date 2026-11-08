/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.domain.entities.record;

import uim.databases.vector.domain.types;

@safe:

/// Entity: a vector identified by `id`, with its embedding and metadata.
/// It is a struct holding its own metadata copy, so records handed out never alias stored ones.
struct VectorRecord {
  private {
    string _id;
    Embedding _embedding;
    Metadata _metadata;
  }

  /// Throws: ValidationException for an invalid id.
  this(string id, Embedding embedding, const Metadata metadata = null) {
    requireVectorId(id);
    _id = id;
    _embedding = embedding;
    _metadata = copyMetadata(metadata);
  }

  string id() const pure nothrow @nogc {
    return _id;
  }

  Embedding embedding() const pure nothrow @nogc {
    return _embedding;
  }

  size_t dimension() const pure nothrow @nogc {
    return _embedding.dimension;
  }

  Metadata metadata() const pure nothrow {
    return copyMetadata(_metadata);
  }

  bool matches(const Metadata criteria) const pure nothrow @nogc {
    return matchesMetadata(_metadata, criteria);
  }

  void replaceEmbedding(Embedding embedding) pure nothrow @nogc {
    _embedding = embedding;
  }

  void replaceMetadata(const Metadata metadata) pure nothrow {
    _metadata = copyMetadata(metadata);
  }
}

/// A record with its distance to a query.
struct SearchHit {
  VectorRecord record;
  double distance;
}

unittest {
  Metadata m = ["k": "v"];
  auto r = VectorRecord("a", Embedding([1.0]), m);
  m["k"] = "changed";
  assert(r.metadata["k"] == "v");
  auto copy = r.metadata;
  copy["k"] = "x";
  assert(r.matches(["k": "v"]));
}
