/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driven port: storage of collections. Implemented in persistence/repositories.
module uim.databases.vector.ports.repositories.collections;

import uim.databases.vector.domain.entities : VectorCollection;

interface ICollectionRepository {
@safe:
  /// Inserts the collection or stores its new state. Interactors call it after every change.
  void save(VectorCollection collection);

  /// null when there is no such collection.
  VectorCollection find(string name);

  /// False if there was nothing to remove.
  bool remove(string name);

  bool exists(string name);

  /// All collections, ordered by name.
  VectorCollection[] all();
}
