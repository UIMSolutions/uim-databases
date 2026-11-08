/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.presentation.rest.controller;

import uim.databases.vector.application.dtos;
import uim.databases.vector.domain.exceptions;
import uim.databases.vector.ports;
import uim.databases.vector.presentation.rest.interfaces;
import uim.databases.vector.presentation.rest.models;
import std.algorithm : map;
import std.array : array;
import std.typecons : Nullable, nullable;
import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;

@safe:

/// Inbound adapter: maps HTTP/JSON onto the driving ports and business errors onto status codes.
/// It holds no business logic.
final class VectorRestController : IVectorRestApi {
  private {
    ICollectionUseCase _collections;
    IVectorUseCase _vectors;
    ISearchUseCase _search;
    IDatabaseInfoService _info;
  }

  this(ICollectionUseCase collections, IVectorUseCase vectors, ISearchUseCase search, IDatabaseInfoService info) {
    assert(collections !is null && vectors !is null && search !is null && info !is null);
    _collections = collections;
    _vectors = vectors;
    _search = search;
    _info = info;
  }

  RestHealth getHealth() {
    auto health = translate(() => _info.health());
    return RestHealth(health.status, health.type, health.collectionCount);
  }

  RestStats getStats() {
    auto stats = translate(() => _info.statistics());
    return RestStats(stats.name, stats.collectionCount, stats.vectorCount, stats.collections.map!(c => toRest(c)).array);
  }

  RestCollectionList getCollections() {
    auto all = translate(() => _collections.listCollections());
    return RestCollectionList(all.map!(c => toRest(c)).array, all.length);
  }

  RestCollection createCollection(RestCreateCollection request, out int status) {
    auto command = CreateCollectionCommand(request.name, cast(size_t) request.dimension, request.metric);
    auto created = translate(() => _collections.createCollection(command));
    status = HTTPStatus.created;
    return toRest(created);
  }

  RestCollection getCollection(string _name) {
    return toRest(translate(() => _collections.describeCollection(_name)));
  }

  RestMessage dropCollection(string _name) {
    translate(() => _collections.dropCollection(_name));
    return RestMessage("Collection dropped successfully");
  }

  RestIdList getVectorIds(string _name) {
    auto ids = translate(() => _vectors.listIds(_name));
    return RestIdList(ids, ids.length);
  }

  RestVector addVector(string _name, RestVectorInput request, out int status) {
    auto added = translate(() => _vectors.addVectors(_name, [toCommand(request)]));
    status = HTTPStatus.created;
    return toRest(added[0]);
  }

  RestVectorList addVectors(string _name, RestVectorBatch request, out int status) {
    auto commands = request.vectors.map!(v => toCommand(v)).array;
    auto added = translate(() => _vectors.addVectors(_name, commands));
    status = HTTPStatus.created;
    return toRestList(added);
  }

  RestVector getVector(string _name, string _id) {
    return toRest(translate(() => _vectors.getVector(_name, _id)));
  }

  RestVector updateVector(string _name, string _id, RestVectorUpdate request) {
    auto command = UpdateVectorCommand(request.values, request.metadata);
    return toRest(translate(() => _vectors.updateVector(_name, _id, command)));
  }

  RestMessage removeVector(string _name, string _id) {
    translate(() => _vectors.removeVector(_name, _id));
    return RestMessage("Vector removed successfully");
  }

  RestVectorList filterVectors(string _name, RestFilterRequest request) {
    return toRestList(translate(() => _vectors.filterByMetadata(_name, request.metadata)));
  }

  RestSearchResponse search(string _name, RestSearchRequest request) {
    auto query = SearchQuery(request.vector, cast(size_t) request.k, request.filter);
    return toRest(translate(() => _search.search(_name, query)), request.includeValues);
  }

  RestSearchResponse searchSimilar(string _name, string _id, RestSimilarRequest request) {
    auto query = SimilarQuery(_id, cast(size_t) request.k, request.filter);
    return toRest(translate(() => _search.searchSimilar(_name, query)), request.includeValues);
  }
}

/// Runs a port call and maps business errors to HTTP errors; anything else stays a 500.
private T translate(T)(scope T delegate() @safe action) {
  try {
    return action();
  } catch (NotFoundException e) {
    throw new HTTPStatusException(HTTPStatus.notFound, e.msg);
  } catch (ConflictException e) {
    throw new HTTPStatusException(HTTPStatus.conflict, e.msg);
  } catch (ValidationException e) {
    throw new HTTPStatusException(HTTPStatus.badRequest, e.msg);
  }
}

private AddVectorCommand toCommand(RestVectorInput input) {
  return AddVectorCommand(input.id, input.values, input.metadata);
}

private RestCollection toRest(CollectionInfo info) {
  return RestCollection(info.name, info.dimension, info.metric, info.count);
}

private RestVector toRest(VectorData data) {
  return RestVector(data.id, data.values, data.metadata);
}

private RestVectorList toRestList(VectorData[] data) {
  return RestVectorList(data.map!(d => toRest(d)).array, data.length);
}

private RestSearchResponse toRest(SearchMatch[] matches, bool includeValues) {
  auto hits = matches.map!(m => RestHit(m.vector.id, m.distance, m.vector.metadata,
      includeValues ? nullable(m.vector.values) : Nullable!(double[]).init)).array;
  return RestSearchResponse(hits, hits.length);
}

unittest {
  import uim.databases.vector.application.services : DatabaseInfoService;
  import uim.databases.vector.application.usecases;
  import uim.databases.vector.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : collectException;

  auto repository = new FakeCollectionRepository;
  auto api = new VectorRestController(new CollectionInteractor(repository), new VectorInteractor(repository),
    new SearchInteractor(repository), new DatabaseInfoService(repository, "main"));

  HTTPStatus statusOf(void delegate() @safe call) {
    auto e = collectException!HTTPStatusException(call());
    assert(e !is null, "expected an HTTPStatusException");
    return cast(HTTPStatus) e.status;
  }

  int status;
  assert(api.createCollection(RestCreateCollection("docs", 2, "cosine"), status) == RestCollection("docs", 2, "COSINE", 0));
  assert(status == HTTPStatus.created);
  api.addVector("docs", RestVectorInput("a", [1, 0], ["lang": "de"]), status);
  api.addVectors("docs", RestVectorBatch([RestVectorInput("b", [0, 1]), RestVectorInput("c", [1, 0.1])]), status);
  assert(api.getVectorIds("docs") == RestIdList(["a", "b", "c"], 3));

  auto hits = api.search("docs", RestSearchRequest([2, 0], 2, null, true));
  assert(hits.count == 2 && hits.results[0].id == "a" && hits.results[0].values.get == [1, 0]);
  assert(api.search("docs", RestSearchRequest([2, 0], 1)).results[0].values.isNull);
  assert(api.searchSimilar("docs", "a", RestSimilarRequest(1)).results[0].id == "c");

  auto updated = api.updateVector("docs", "b", RestVectorUpdate(Nullable!(double[]).init, nullable(["lang": "en"])));
  assert(updated.values == [0, 1] && updated.metadata == ["lang": "en"]);
  assert(api.filterVectors("docs", RestFilterRequest(["lang": "en"])).count == 1);

  assert(statusOf({ api.createCollection(RestCreateCollection("docs", 2), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.addVector("docs", RestVectorInput("a", [1, 1]), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.addVector("docs", RestVectorInput("d", [1]), status); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.search("docs", RestSearchRequest([1, 1], 0)); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.getVector("docs", "zz"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.getCollection("nope"); }) == HTTPStatus.notFound);

  api.removeVector("docs", "a");
  assert(api.getStats() == RestStats("main", 1, 2, [RestCollection("docs", 2, "COSINE", 2)]));
  api.dropCollection("docs");
  assert(api.getHealth().collectionCount == 0);
}
