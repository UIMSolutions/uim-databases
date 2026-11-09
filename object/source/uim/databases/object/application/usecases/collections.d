module uim.databases.object.application.usecases.collections;

import uim.databases.object.application.dtos;
import uim.databases.object.application.usecases.support;
import uim.databases.object.domain;
import uim.databases.object.ports;
import std.algorithm : canFind, map;
import std.array : array;

@safe:

/// Interactor for collection management.
final class CollectionInteractor : ICollectionUseCase {
  private {
    ICollectionRepository _repository;
    string[] _protected;
  }

  /// `protectedNames`: collections that cannot be dropped (e.g. the configured default collection).
  this(ICollectionRepository repository, string[] protectedNames = null) {
    assert(repository !is null, "CollectionInteractor needs a repository");
    _repository = repository;
    _protected = protectedNames.dup;
  }

  CollectionInfo createCollection(string name) {
    auto collection = new DocumentCollection(name);
    if (_repository.exists(collection.name)) {
      throw new CollectionAlreadyExistsException(collection.name);
    }
    _repository.save(collection);
    return CollectionInfo.from(collection);
  }

  void dropCollection(string name) {
    requireCollection(_repository, name);
    if (_protected.canFind(name)) {
      throw new ProtectedCollectionException(name);
    }
    _repository.remove(name);
  }

  CollectionInfo[] listCollections() {
    return _repository.all().map!(c => CollectionInfo.from(c)).array;
  }

  CollectionInfo describeCollection(string name) {
    return CollectionInfo.from(requireCollection(_repository, name));
  }

  CollectionInfo clearCollection(string name) {
    auto collection = requireCollection(_repository, name);
    collection.clear();
    _repository.save(collection);
    return CollectionInfo.from(collection);
  }
}

unittest {
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : assertThrown;

  auto collections = new CollectionInteractor(new FakeCollectionRepository, ["default"]);
  collections.createCollection("default");
  assert(collections.createCollection("users") == CollectionInfo("users", 0, null));
  assert(collections.listCollections().map!(c => c.name).array == ["default", "users"]);

  assertThrown!CollectionAlreadyExistsException(collections.createCollection("users"));
  assertThrown!ValidationException(collections.createCollection("bad name"));
  assertThrown!ProtectedCollectionException(collections.dropCollection("default"));

  collections.dropCollection("users");
  assertThrown!CollectionNotFoundException(collections.dropCollection("users"));
  assertThrown!CollectionNotFoundException(collections.describeCollection("users"));
  assertThrown!CollectionNotFoundException(collections.clearCollection("users"));
}
