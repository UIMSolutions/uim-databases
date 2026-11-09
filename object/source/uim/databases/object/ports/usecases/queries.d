/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
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
