/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.application.usecases.collections;

import uim.databases.vector.application.dtos;
import uim.databases.vector.application.usecases.support;
import uim.databases.vector.domain;
import uim.databases.vector.ports;
import std.algorithm : map;
import std.array : array;

@safe:

/// Interactor for collection management.
final class CollectionInteractor : ICollectionUseCase {
  private ICollectionRepository _repository;

  this(ICollectionRepository repository) {
    assert(repository !is null, "CollectionInteractor needs a repository");
    _repository = repository;
  }

  CollectionInfo createCollection(CreateCollectionCommand command) {
    immutable metric = command.metric.length == 0 ? DistanceMetric.EUCLIDEAN : parseDistanceMetric(command.metric);
    auto collection = new VectorCollection(command.name, command.dimension, metric);
    if (_repository.exists(collection.name)) {
      throw new CollectionAlreadyExistsException(collection.name);
    }
    _repository.save(collection);
    return CollectionInfo.from(collection);
  }

  void dropCollection(string name) {
    requireCollection(_repository, name);
    _repository.remove(name);
  }

  CollectionInfo[] listCollections() {
    return _repository.all().map!(c => CollectionInfo.from(c)).array;
  }

  CollectionInfo describeCollection(string name) {
    return CollectionInfo.from(requireCollection(_repository, name));
  }
}

unittest {
  import uim.databases.vector.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : assertThrown;

  auto collections = new CollectionInteractor(new FakeCollectionRepository);
  assert(collections.createCollection(CreateCollectionCommand("docs", 3)) == CollectionInfo("docs", 3, "EUCLIDEAN", 0));
  collections.createCollection(CreateCollectionCommand("images", 2, "cosine"));
  assert(collections.listCollections().map!(c => c.name).array == ["docs", "images"]);
  assert(collections.describeCollection("images").metric == "COSINE");

  assertThrown!CollectionAlreadyExistsException(collections.createCollection(CreateCollectionCommand("docs", 3)));
  assertThrown!ValidationException(collections.createCollection(CreateCollectionCommand("x", 0)));
  assertThrown!ValidationException(collections.createCollection(CreateCollectionCommand("x", 2, "hamming")));

  collections.dropCollection("docs");
  assertThrown!CollectionNotFoundException(collections.dropCollection("docs"));
  assertThrown!CollectionNotFoundException(collections.describeCollection("docs"));
}
