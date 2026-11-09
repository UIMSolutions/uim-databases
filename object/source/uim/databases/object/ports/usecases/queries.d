/// Driving port: queries.
module uim.databases.object.ports.usecases.queries;

import uim.databases.object.application.dtos;

interface IQueryUseCase {
@safe:
  /// Throws: CollectionNotFoundException, ValidationException.
  DocumentData[] find(string collection, FindQuery query);

  /// Throws: CollectionNotFoundException, ValidationException.
  size_t count(string collection, CountQuery query);
}
