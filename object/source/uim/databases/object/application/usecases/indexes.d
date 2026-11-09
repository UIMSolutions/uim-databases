module uim.databases.object.application.usecases.indexes;

import uim.databases.object.application.usecases.support;
import uim.databases.object.domain;
import uim.databases.object.ports;

@safe:

/// Interactor for index management.
final class IndexInteractor : IIndexUseCase {
  private ICollectionRepository _repository;

  this(ICollectionRepository repository) {
    assert(repository !is null, "IndexInteractor needs a repository");
    _repository = repository;
  }

  string createIndex(string collection, string field) {
    auto target = requireCollection(_repository, collection);
    auto path = FieldPath(field);
    target.createIndex(path);
    _repository.save(target);
    return path.toString;
  }

  void dropIndex(string collection, string field) {
    auto target = requireCollection(_repository, collection);
    target.dropIndex(FieldPath(field));
    _repository.save(target);
  }

  string[] listIndexes(string collection) {
    return requireCollection(_repository, collection).indexedFields;
  }
}

unittest {
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : assertThrown;

  auto repository = new FakeCollectionRepository;
  repository.save(new DocumentCollection("users"));
  auto indexes = new IndexInteractor(repository);

  assert(indexes.createIndex("users", "address.city") == "address.city");
  indexes.createIndex("users", "age");
  assert(indexes.listIndexes("users") == ["address.city", "age"]);
  assertThrown!IndexAlreadyExistsException(indexes.createIndex("users", "age"));
  assertThrown!ValidationException(indexes.createIndex("users", ""));

  indexes.dropIndex("users", "age");
  assertThrown!IndexNotFoundException(indexes.dropIndex("users", "age"));
  assertThrown!CollectionNotFoundException(indexes.listIndexes("nope"));
}
