/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: nearest-neighbour search.
module uim.databases.vector.ports.usecases.search;

import uim.databases.vector.application.dtos;

interface ISearchUseCase {
@safe:
  /// The k nearest vectors to `query.vector`, nearest first.
  /// Throws: CollectionNotFoundException, ValidationException.
  SearchMatch[] search(string collection, SearchQuery query);

  /// The k nearest vectors to a stored vector, excluding that vector.
  /// Throws: CollectionNotFoundException, VectorNotFoundException, ValidationException.
  SearchMatch[] searchSimilar(string collection, SimilarQuery query);
}
