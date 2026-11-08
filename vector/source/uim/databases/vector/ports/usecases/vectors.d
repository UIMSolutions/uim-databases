/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: the vectors of one collection. Every method throws CollectionNotFoundException for unknown collections.
module uim.databases.vector.ports.usecases.vectors;

import uim.databases.vector.application.dtos;

interface IVectorUseCase {
@safe:
  /// Adds all vectors or none. Throws: ValidationException, VectorAlreadyExistsException.
  VectorData[] addVectors(string collection, AddVectorCommand[] commands);

  /// Throws: VectorNotFoundException.
  VectorData getVector(string collection, string id);

  /// Throws: VectorNotFoundException, ValidationException.
  VectorData updateVector(string collection, string id, UpdateVectorCommand command);

  /// Throws: VectorNotFoundException.
  void removeVector(string collection, string id);

  /// Ids in ascending order.
  string[] listIds(string collection);

  /// Vectors whose metadata contains every pair of `criteria`, ordered by id.
  VectorData[] filterByMetadata(string collection, string[string] criteria);
}
