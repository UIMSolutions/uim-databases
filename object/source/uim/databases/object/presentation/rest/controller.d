/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.presentation.rest.controller;

import uim.databases.object.application.dtos;
import uim.databases.object.domain.exceptions;
import uim.databases.object.ports;
import uim.databases.object.presentation.rest.interfaces;
import uim.databases.object.presentation.rest.mappers;
import uim.databases.object.presentation.rest.models;
import std.algorithm : map;
import std.array : array;
import vibe.data.json : Json;
import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;

@safe:

/// Inbound adapter: maps HTTP/JSON onto the driving ports and business errors onto status codes.
/// It holds no business logic.
final class ObjectRestController : IObjectRestApi {
  private {
    ICollectionUseCase _collections;
    IDocumentUseCase _documents;
    IQueryUseCase _queries;
    IIndexUseCase _indexes;
    IDatabaseInfoService _info;
  }

  this(ICollectionUseCase collections, IDocumentUseCase documents, IQueryUseCase queries, IIndexUseCase indexes,
    IDatabaseInfoService info) {
    assert(collections !is null && documents !is null && queries !is null && indexes !is null && info !is null);
    _collections = collections;
    _documents = documents;
    _queries = queries;
    _indexes = indexes;
    _info = info;
  }

  RestHealth getHealth() {
    auto health = translate(() => _info.health());
    return RestHealth(health.status, health.type, health.collectionCount);
  }

  RestStats getStats() {
    auto stats = translate(() => _info.statistics());
    return RestStats(stats.name, stats.collectionCount, stats.documentCount, stats.collections.map!(c => toRest(c)).array);
  }

  // --- Collections ---

  RestCollectionList getCollections() {
    auto all = translate(() => _collections.listCollections());
    return RestCollectionList(all.map!(c => toRest(c)).array, all.length);
  }

  RestCollection createCollection(string _name, out int status) {
    auto created = translate(() => _collections.createCollection(_name));
    status = HTTPStatus.created;
    return toRest(created);
  }

  RestCollection getCollection(string _name) {
    return toRest(translate(() => _collections.describeCollection(_name)));
  }

  RestCollection getCollectionStats(string _name) {
    return getCollection(_name);
  }

  RestMessage dropCollection(string _name) {
    translate(() => _collections.dropCollection(_name));
    return RestMessage("Collection dropped successfully");
  }

  RestMessage clearCollection(string _name) {
    translate(() => _collections.clearCollection(_name));
    return RestMessage("Collection cleared successfully");
  }

  // --- Documents ---

  RestDocument insertDocument(string _name, Json document, out int status) {
    auto inserted = translate(() => _documents.insertDocument(_name, InsertDocumentCommand(toJSONValue(document))));
    status = HTTPStatus.created;
    return toRest(inserted);
  }

  RestBulkResult insertDocuments(string _name, RestBulkInsert request, out int status) {
    auto inserted = translate(() => _documents.insertDocuments(_name,
        request.documents.map!(d => InsertDocumentCommand(toJSONValue(d))).array));
    status = HTTPStatus.created;
    return RestBulkResult(inserted.length, inserted.map!(d => d.id).array);
  }

  RestDocumentList getDocuments(string _name) {
    return toRest(translate(() => _documents.listDocuments(_name)));
  }

  RestDocumentList getAllDocuments(string _name) {
    return getDocuments(_name);
  }

  RestDocument getDocument(string _name, string _id) {
    return toRest(translate(() => _documents.getDocument(_name, _id)));
  }

  RestDocument replaceDocument(string _name, string _id, Json document) {
    return toRest(translate(() => _documents.replaceDocument(_name, _id, ReplaceDocumentCommand(toJSONValue(document)))));
  }

  RestMessage removeDocument(string _name, string _id) {
    translate(() => _documents.removeDocument(_name, _id));
    return RestMessage("Document removed successfully");
  }

  // --- Queries ---

  RestDocumentList find(string _name, RestFindRequest request) {
    return toRest(translate(() {
        FindQuery query;
        query.where = toConditions(request.where);
        if (!request.sort.isNull) {
          query.sortField = request.sort.get.field;
          query.descending = !request.sort.get.ascending;
        }
        query.skip = cast(size_t) request.skip;
        query.limit = cast(size_t) request.limit;
        return _queries.find(_name, query);
      }));
  }

  RestCount count(string _name, RestCountRequest request) {
    return RestCount(translate(() => _queries.count(_name, CountQuery(toConditions(request.where)))));
  }

  // --- Indexes ---

  RestIndexList getIndexes(string _name) {
    auto fields = translate(() => _indexes.listIndexes(_name));
    return RestIndexList(fields, fields.length);
  }

  RestIndex createIndex(string _name, RestCreateIndex request, out int status) {
    auto field = translate(() => _indexes.createIndex(_name, request.field));
    status = HTTPStatus.created;
    return RestIndex(field);
  }

  RestMessage dropIndex(string _name, string _field) {
    translate(() => _indexes.dropIndex(_name, _field));
    return RestMessage("Index dropped successfully");
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

private ConditionInput[] toConditions(RestCondition[] conditions) {
  return conditions.map!(c => ConditionInput(c.field, c.op, toJSONValue(c.value))).array;
}

private RestCollection toRest(CollectionInfo info) {
  return RestCollection(info.name, info.documentCount, info.indexes.length, info.indexes);
}

private RestDocument toRest(DocumentData data) {
  return RestDocument(data.id, toJson(data.data), data.createdAt, data.updatedAt);
}

private RestDocumentList toRest(DocumentData[] data) {
  return RestDocumentList(data.map!(d => toRest(d)).array, data.length);
}

unittest {
  import uim.databases.object.application.services : DatabaseInfoService;
  import uim.databases.object.application.usecases;
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.exception : collectException;
  import std.typecons : nullable;
  import vibe.data.json : parseJsonString;

  auto repository = new FakeCollectionRepository;
  auto api = new ObjectRestController(new CollectionInteractor(repository, ["default"]),
    new DocumentInteractor(repository), new QueryInteractor(repository), new IndexInteractor(repository),
    new DatabaseInfoService(repository, "main"));

  HTTPStatus statusOf(void delegate() @safe call) {
    auto e = collectException!HTTPStatusException(call());
    assert(e !is null, "expected an HTTPStatusException");
    return cast(HTTPStatus) e.status;
  }

  int status;
  api.createCollection("default", status);
  assert(api.createCollection("users", status) == RestCollection("users", 0, 0, null) && status == HTTPStatus.created);

  auto ada = api.insertDocument("users", parseJsonString(`{"_id":"ada","name":"Ada","age":36}`), status);
  assert(status == HTTPStatus.created && ada.id == "ada" && ada.data == parseJsonString(`{"name":"Ada","age":36}`));
  auto bulk = api.insertDocuments("users", RestBulkInsert([parseJsonString(`{"_id":"bob","age":25}`),
      parseJsonString(`{"_id":"cy","age":30}`)]), status);
  assert(bulk == RestBulkResult(2, ["bob", "cy"]));
  assert(api.getAllDocuments("users").count == 3);

  api.createIndex("users", RestCreateIndex("age"), status);
  assert(api.getIndexes("users") == RestIndexList(["age"], 1));

  auto older = api.find("users", RestFindRequest([RestCondition("age", ">", Json(26))], nullable(RestSort("age", false))));
  assert(older.documents.map!(d => d.id).array == ["ada", "cy"]);
  assert(api.count("users", RestCountRequest([RestCondition("age", "==", Json(25))])) == RestCount(1));

  auto replaced = api.replaceDocument("users", "bob", parseJsonString(`{"age":26}`));
  assert(replaced.data["age"] == Json(26) && api.getDocument("users", "bob").createdAt == replaced.createdAt);

  // Wire format: documents serialise their id as `_id`.
  import vibe.data.json : serializeToJson;
  assert(serializeToJson(ada)["_id"] == Json("ada"));

  assert(statusOf({ api.createCollection("users", status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.insertDocument("users", parseJsonString(`{"_id":"ada"}`), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.createIndex("users", RestCreateIndex("age"), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.insertDocument("users", parseJsonString(`[1]`), status); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.find("users", RestFindRequest([RestCondition("age", "~", Json(1))])); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.dropCollection("default"); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.getDocument("users", "zz"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.dropIndex("users", "name"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.getCollection("nope"); }) == HTTPStatus.notFound);

  api.removeDocument("users", "ada");
  assert(api.getStats() == RestStats("main", 2, 2, [RestCollection("default", 0, 0, null),
      RestCollection("users", 2, 1, ["age"])]));
  api.clearCollection("users");
  assert(api.getCollectionStats("users") == RestCollection("users", 0, 1, ["age"]));
  api.dropCollection("users");
  assert(api.getHealth().collectionCount == 1);
}
