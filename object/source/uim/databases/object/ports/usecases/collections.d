/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: collection management.
module uim.databases.object.ports.usecases.collections;

import uim.databases.object.application.dtos;

interface ICollectionUseCase {
@safe:
  /// Throws: ValidationException, CollectionAlreadyExistsException.
  CollectionInfo createCollection(string name);

  /// Deletes the collection with all its documents and indexes.
  /// Throws: CollectionNotFoundException, ProtectedCollectionException.
  void dropCollection(string name);

  /// Ordered by name.
  CollectionInfo[] listCollections();

  /// Throws: CollectionNotFoundException.
  CollectionInfo describeCollection(string name);

  /// Removes every document; indexes stay defined. Throws: CollectionNotFoundException.
  CollectionInfo clearCollection(string name);
}
