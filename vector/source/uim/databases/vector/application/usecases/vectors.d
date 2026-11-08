/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.application.usecases.vectors;

import uim.databases.vector.application.dtos;
import uim.databases.vector.application.usecases.support;
import uim.databases.vector.domain;
import uim.databases.vector.ports;
import std.algorithm : map;
import std.array : array;
import std.typecons : Nullable, nullable;

@safe:

/// Interactor for the vectors of a collection.
final class VectorInteractor : IVectorUseCase {
  private ICollectionRepository _repository;

  this(ICollectionRepository repository) {
    assert(repository !is null, "VectorInteractor needs a repository");
    _repository = repository;
  }

  VectorData[] addVectors(string collectionName, AddVectorCommand[] commands) {
    auto collection = requireCollection(_repository, collectionName);
    auto records = commands.map!(c => VectorRecord(c.id, Embedding(c.values), c.metadata)).array;
    collection.addAll(records);
    _repository.save(collection);
    return records.map!(r => VectorData.from(r)).array;
  }

  VectorData getVector(string collectionName, string id) {
    return VectorData.from(requireCollection(_repository, collectionName).get(id));
  }

  VectorData updateVector(string collectionName, string id, UpdateVectorCommand command) {
    auto collection = requireCollection(_repository, collectionName);
    auto embedding = command.values.isNull ? Nullable!Embedding.init : nullable(Embedding(command.values.get));
    auto metadata = command.metadata.isNull ? Nullable!Metadata.init : nullable(command.metadata.get);
    auto updated = collection.update(id, embedding, metadata);
    _repository.save(collection);
    return VectorData.from(updated);
  }

  void removeVector(string collectionName, string id) {
    auto collection = requireCollection(_repository, collectionName);
    collection.remove(id);
    _repository.save(collection);
  }

  string[] listIds(string collectionName) {
    return requireCollection(_repository, collectionName).ids();
  }

  VectorData[] filterByMetadata(string collectionName, string[string] criteria) {
    return requireCollection(_repository, collectionName).filterByMetadata(criteria)
      .map!(r => VectorData.from(r)).array;
  }
}

unittest {
  import uim.databases.vector.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : assertThrown;

  auto repository = new FakeCollectionRepository;
  repository.save(new VectorCollection("docs", 2));
  auto vectors = new VectorInteractor(repository);

  vectors.addVectors("docs", [AddVectorCommand("a", [1, 2], ["lang": "de"]), AddVectorCommand("b", [3, 4])]);
  assert(vectors.listIds("docs") == ["a", "b"]);
  assert(vectors.getVector("docs", "a") == VectorData("a", [1, 2], ["lang": "de"]));

  auto updated = vectors.updateVector("docs", "b", UpdateVectorCommand(Nullable!(double[]).init, nullable(["lang": "en"])));
  assert(updated.values == [3, 4] && updated.metadata == ["lang": "en"]);
  assert(vectors.filterByMetadata("docs", ["lang": "en"]).map!(v => v.id).array == ["b"]);

  assertThrown!DimensionMismatchException(vectors.addVectors("docs", [AddVectorCommand("c", [1])]));
  assertThrown!ValidationException(vectors.addVectors("docs", [AddVectorCommand("", [1, 1])]));
  assertThrown!VectorAlreadyExistsException(vectors.addVectors("docs", [AddVectorCommand("a", [1, 1])]));
  assertThrown!DimensionMismatchException(vectors.updateVector("docs", "a", UpdateVectorCommand(nullable([1.0]))));

  vectors.removeVector("docs", "a");
  assertThrown!VectorNotFoundException(vectors.getVector("docs", "a"));
  assertThrown!CollectionNotFoundException(vectors.listIds("nope"));
}
