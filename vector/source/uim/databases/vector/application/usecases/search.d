/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.application.usecases.search;

import uim.databases.vector.application.dtos;
import uim.databases.vector.application.usecases.support;
import uim.databases.vector.domain;
import uim.databases.vector.ports;
import std.algorithm : map;
import std.array : array;

@safe:

/// Interactor for nearest-neighbour search; ranking itself is done by the domain.
final class SearchInteractor : ISearchUseCase {
  private ICollectionRepository _repository;

  this(ICollectionRepository repository) {
    assert(repository !is null, "SearchInteractor needs a repository");
    _repository = repository;
  }

  SearchMatch[] search(string collectionName, SearchQuery query) {
    auto collection = requireCollection(_repository, collectionName);
    return collection.search(Embedding(query.vector), query.k, query.filter).map!(h => SearchMatch.from(h)).array;
  }

  SearchMatch[] searchSimilar(string collectionName, SimilarQuery query) {
    auto collection = requireCollection(_repository, collectionName);
    return collection.searchSimilar(query.id, query.k, query.filter).map!(h => SearchMatch.from(h)).array;
  }
}

unittest {
  import uim.databases.vector.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : assertThrown;

  auto repository = new FakeCollectionRepository;
  auto docs = new VectorCollection("docs", 2);
  docs.addAll([
    VectorRecord("a", Embedding([0.0, 0.0])), VectorRecord("b", Embedding([1.0, 1.0]), ["lang": "de"]),
    VectorRecord("c", Embedding([5.0, 5.0]), ["lang": "de"])
  ]);
  repository.save(docs);
  auto search = new SearchInteractor(repository);

  auto hits = search.search("docs", SearchQuery([0.0, 0.1], 2));
  assert(hits.map!(h => h.vector.id).array == ["a", "b"] && hits[0].distance < hits[1].distance);
  assert(search.search("docs", SearchQuery([0.0, 0.0], 5, ["lang": "de"])).map!(h => h.vector.id).array == ["b", "c"]);
  assert(search.searchSimilar("docs", SimilarQuery("b", 1))[0].vector.id == "a");

  assertThrown!DimensionMismatchException(search.search("docs", SearchQuery([1.0], 1)));
  assertThrown!ValidationException(search.search("docs", SearchQuery([1.0, 1.0], 0)));
  assertThrown!VectorNotFoundException(search.searchSimilar("docs", SimilarQuery("z", 1)));
  assertThrown!CollectionNotFoundException(search.search("nope", SearchQuery([1.0], 1)));
}
