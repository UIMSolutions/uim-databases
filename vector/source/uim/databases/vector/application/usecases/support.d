/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Helpers shared by the interactors.
module uim.databases.vector.application.usecases.support;

import uim.databases.vector.domain;
import uim.databases.vector.ports.repositories;

package(uim.databases.vector.application) @safe:

/// Throws: CollectionNotFoundException.
VectorCollection requireCollection(ICollectionRepository repository, string name) {
  auto collection = repository.find(name);
  if (collection is null) {
    throw new CollectionNotFoundException(name);
  }
  return collection;
}
