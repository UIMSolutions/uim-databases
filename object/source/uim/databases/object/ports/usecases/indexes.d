/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: index management.
module uim.databases.object.ports.usecases.indexes;

interface IIndexUseCase {
@safe:
  /// Returns the normalised field path.
  /// Throws: CollectionNotFoundException, ValidationException, IndexAlreadyExistsException.
  string createIndex(string collection, string field);

  /// Throws: CollectionNotFoundException, ValidationException, IndexNotFoundException.
  void dropIndex(string collection, string field);

  /// Ordered. Throws: CollectionNotFoundException.
  string[] listIndexes(string collection);
}
