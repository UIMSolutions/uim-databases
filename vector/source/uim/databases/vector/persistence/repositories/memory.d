/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.persistence.repositories.memory;

import uim.databases.vector.domain.entities : VectorCollection;
import uim.databases.vector.ports.repositories : ICollectionRepository;
import std.algorithm : map, sort;
import std.array : array;

@safe:

/// Driven adapter: keeps collections in process memory. Data is lost on restart.
///
/// Collections are held by reference, so `save` has nothing to copy; it exists so that durable adapters
/// (files, an external store via persistence/storages + mappers + records) can be swapped in without
/// touching the interactors. No method yields to the vibe.d event loop, so every call is atomic for
/// fibers on one thread; share an instance across threads only behind a lock.
final class InMemoryCollectionRepository : ICollectionRepository {
  private VectorCollection[string] _collections;

  void save(VectorCollection collection) {
    assert(collection !is null);
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

unittest {
  auto repository = new InMemoryCollectionRepository;
  auto b = new VectorCollection("b", 1);
  auto a = new VectorCollection("a", 1);
  repository.save(b);
  repository.save(a);
  assert(repository.all == [a, b]);
  assert(repository.find("b") is b && repository.find("c") is null);
  assert(repository.remove("a") && !repository.remove("a") && !repository.exists("a"));
}
