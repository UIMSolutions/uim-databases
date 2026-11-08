/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.domain.entities.collection;

import uim.databases.vector.domain.entities.record;
import uim.databases.vector.domain.enumerations;
import uim.databases.vector.domain.exceptions;
import uim.databases.vector.domain.services.distance : distance;
import uim.databases.vector.domain.types;
import std.algorithm : filter, map, sort, topN;
import std.array : array;
import std.typecons : Nullable;

@safe:

/// Entity and aggregate root: a named set of vectors sharing one dimension and distance metric.
///
/// Search is exact (brute force, O(n · dimension) per query). Batch changes are all-or-nothing.
final class VectorCollection {
  private {
    string _name;
    size_t _dimension;
    DistanceMetric _metric;
    VectorRecord[string] _records;
  }

  /// Throws: ValidationException for an invalid name or a dimension outside 1 .. maxDimension.
  this(string name, size_t dimension, DistanceMetric metric = DistanceMetric.EUCLIDEAN) {
    requireCollectionName(name);
    if (dimension == 0 || dimension > maxDimension) {
      throw new ValidationException("Dimension must be between 1 and 65536");
    }
    _name = name;
    _dimension = dimension;
    _metric = metric;
  }

  string name() const pure nothrow @nogc {
    return _name;
  }

  size_t dimension() const pure nothrow @nogc {
    return _dimension;
  }

  DistanceMetric metric() const pure nothrow @nogc {
    return _metric;
  }

  size_t count() const pure nothrow @nogc {
    return _records.length;
  }

  bool contains(string id) const pure nothrow @nogc {
    return (id in _records) !is null;
  }

  /// Throws: DimensionMismatchException, VectorAlreadyExistsException.
  void add(VectorRecord record) {
    addAll([record]);
  }

  /// Adds all records or none. Throws: DimensionMismatchException, VectorAlreadyExistsException.
  void addAll(VectorRecord[] records) {
    bool[string] batch;
    foreach (record; records) {
      requireDimension(record.embedding);
      if (record.id in _records || record.id in batch) {
        throw new VectorAlreadyExistsException(_name, record.id);
      }
      batch[record.id] = true;
    }
    foreach (record; records) {
      _records[record.id] = record;
    }
  }

  /// Throws: VectorNotFoundException.
  VectorRecord get(string id) const {
    if (auto found = id in _records) {
      return VectorRecord(found.id, found.embedding, found.metadata);
    }
    throw new VectorNotFoundException(_name, id);
  }

  /// Replaces the embedding and/or the metadata; a null argument keeps the current value.
  /// Throws: VectorNotFoundException, DimensionMismatchException.
  VectorRecord update(string id, Nullable!Embedding embedding, Nullable!Metadata metadata) {
    auto found = id in _records;
    if (found is null) {
      throw new VectorNotFoundException(_name, id);
    }
    if (!embedding.isNull) {
      requireDimension(embedding.get); // before any change
      found.replaceEmbedding(embedding.get);
    }
    if (!metadata.isNull) {
      found.replaceMetadata(metadata.get);
    }
    return get(id);
  }

  /// Throws: VectorNotFoundException.
  void remove(string id) {
    if (!_records.remove(id)) {
      throw new VectorNotFoundException(_name, id);
    }
  }

  void clear() pure nothrow {
    _records = null;
  }

  /// All ids in ascending order.
  string[] ids() const {
    return _records.keys.sort.release;
  }

  /// Records whose metadata contains every pair of `criteria`, ordered by id.
  VectorRecord[] filterByMetadata(const Metadata criteria) const {
    return ids().filter!(id => _records[id].matches(criteria)).map!(id => get(id)).array;
  }

  /// The `k` records nearest to `query` (ties broken by id), optionally restricted by metadata
  /// and excluding one id (used for "more like this").
  /// Throws: DimensionMismatchException, ValidationException for k == 0.
  SearchHit[] search(Embedding query, size_t k, const Metadata criteria = null, string excludeId = null) const {
    requireDimension(query);
    if (k == 0) {
      throw new ValidationException("k must be at least 1");
    }

    SearchHit[] hits;
    foreach (record; _records.byValue) {
      if (record.id != excludeId && record.matches(criteria)) {
        hits ~= SearchHit(VectorRecord(record.id, record.embedding, record.metadata),
          distance(query.values, record.embedding.values, _metric));
      }
    }

    alias closer = (a, b) => a.distance < b.distance || (a.distance == b.distance && a.record.id < b.record.id);
    if (k < hits.length) {
      hits.topN!closer(k);
      hits = hits[0 .. k];
    }
    hits.sort!closer;
    return hits;
  }

  /// Search with a stored vector as the query; the vector itself is not part of the result.
  /// Throws: VectorNotFoundException, ValidationException.
  SearchHit[] searchSimilar(string id, size_t k, const Metadata criteria = null) const {
    return search(get(id).embedding, k, criteria, id);
  }

  private void requireDimension(const Embedding embedding) const {
    if (embedding.dimension != _dimension) {
      throw new DimensionMismatchException(_dimension, embedding.dimension);
    }
  }
}

unittest {
  import std.exception : assertThrown;
  import std.typecons : nullable;

  auto docs = new VectorCollection("docs", 2);
  docs.addAll([
    VectorRecord("a", Embedding([0.0, 0.0]), ["lang": "de"]),
    VectorRecord("b", Embedding([1.0, 0.0]), ["lang": "en"]),
    VectorRecord("c", Embedding([0.0, 2.0]), ["lang": "de"]),
    VectorRecord("d", Embedding([1.0, 0.0])),
  ]);
  assert(docs.count == 4 && docs.ids == ["a", "b", "c", "d"]);

  // Batches are all-or-nothing.
  assertThrown!VectorAlreadyExistsException(docs.addAll([VectorRecord("e", Embedding([1.0, 1.0])), VectorRecord("a", Embedding([1.0, 1.0]))]));
  assertThrown!VectorAlreadyExistsException(docs.addAll([VectorRecord("e", Embedding([1.0, 1.0])), VectorRecord("e", Embedding([1.0, 1.0]))]));
  assertThrown!DimensionMismatchException(docs.addAll([VectorRecord("e", Embedding([1.0, 1.0])), VectorRecord("f", Embedding([1.0]))]));
  assert(docs.count == 4);

  auto near = docs.search(Embedding([0.9, 0.0]), 2);
  assert(near.map!(h => h.record.id).array == ["b", "d"]); // tie broken by id
  assert(docs.search(Embedding([0.9, 0.0]), 10).length == 4);
  assert(docs.search(Embedding([0.0, 0.0]), 5, ["lang": "de"]).map!(h => h.record.id).array == ["a", "c"]);
  assert(docs.searchSimilar("b", 1)[0].record.id == "d");
  assertThrown!ValidationException(docs.search(Embedding([0.0, 0.0]), 0));
  assertThrown!DimensionMismatchException(docs.search(Embedding([0.0]), 1));

  auto updated = docs.update("c", nullable(Embedding([5.0, 5.0])), Nullable!Metadata.init);
  assert(updated.embedding.values == [5.0, 5.0] && updated.metadata["lang"] == "de");
  assertThrown!DimensionMismatchException(docs.update("c", nullable(Embedding([1.0])), nullable(Metadata.init)));
  assert(docs.get("c").metadata["lang"] == "de"); // failed update changed nothing
  docs.update("c", Nullable!Embedding.init, nullable(["lang": "fr"]));
  assert(docs.filterByMetadata(["lang": "fr"]).length == 1);

  docs.remove("c");
  assertThrown!VectorNotFoundException(docs.get("c"));
  assertThrown!VectorNotFoundException(docs.remove("c"));

  auto cosine = new VectorCollection("cos", 2, DistanceMetric.COSINE);
  cosine.addAll([VectorRecord("x", Embedding([1.0, 0.0])), VectorRecord("y", Embedding([10.0, 1.0]))]);
  assert(cosine.search(Embedding([5.0, 0.0]), 1)[0].record.id == "x");

  assertThrown!ValidationException(new VectorCollection("bad name", 2));
  assertThrown!ValidationException(new VectorCollection("ok", 0));
}
