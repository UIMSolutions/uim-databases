/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Test double for the repository port, so application and presentation tests never depend on persistence.
module uim.databases.vector.ports.repositories.fakes;

version (unittest):

import uim.databases.vector.domain.entities : VectorCollection;
import uim.databases.vector.ports.repositories.collections;
import std.algorithm : map, sort;
import std.array : array;

@safe:

final class FakeCollectionRepository : ICollectionRepository {
  private VectorCollection[string] _collections;
  size_t saves;

  void save(VectorCollection collection) {
    saves++;
    _collections[collection.name] = collection;
  }

  VectorCollection find(string name) {
    auto found = name in _collections;
    return found is null ? null : *found;
  }

  bool remove(string name) {
    return _collections.remove(name);
  }

  bool exists(string name) {
    return (name in _collections) !is null;
  }

  VectorCollection[] all() {
    return _collections.keys.sort.map!(n => _collections[n]).array;
  }
}
