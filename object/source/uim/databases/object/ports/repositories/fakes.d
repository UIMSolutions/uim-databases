/// Test double for the repository port, so application and presentation tests never depend on persistence.
module uim.databases.object.ports.repositories.fakes;

version (unittest):

import uim.databases.object.domain.entities : DocumentCollection;
import uim.databases.object.ports.repositories.collections;
import std.algorithm : map, sort;
import std.array : array;

@safe:

final class FakeCollectionRepository : ICollectionRepository {
  private DocumentCollection[string] _collections;
  size_t saves;

  void save(DocumentCollection collection) {
    saves++;
    _collections[collection.name] = collection;
  }

  DocumentCollection find(string name) {
    auto found = name in _collections;
    return found is null ? null : *found;
  }

  bool remove(string name) {
    return _collections.remove(name);
  }

  bool exists(string name) {
    return (name in _collections) !is null;
  }

  DocumentCollection[] all() {
    return _collections.keys.sort.map!(n => _collections[n]).array;
  }
}
