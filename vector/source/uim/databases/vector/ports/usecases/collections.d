/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: collection management.
module uim.databases.vector.ports.usecases.collections;

import uim.databases.vector.application.dtos;

interface ICollectionUseCase {
@safe:
  /// Throws: ValidationException, CollectionAlreadyExistsException.
  CollectionInfo createCollection(CreateCollectionCommand command);

  /// Deletes the collection with all its vectors. Throws: CollectionNotFoundException.
  void dropCollection(string name);

  /// Ordered by name.
  CollectionInfo[] listCollections();

  /// Throws: CollectionNotFoundException.
  CollectionInfo describeCollection(string name);
}
