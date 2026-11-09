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
