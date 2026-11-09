/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.application.usecases.queries;

import uim.databases.object.application.dtos;
import uim.databases.object.application.usecases.support;
import uim.databases.object.domain;
import uim.databases.object.ports;
import std.algorithm : map;
import std.array : array;
import std.typecons : nullable;

@safe:

/// Interactor for queries.
final class QueryInteractor : IQueryUseCase {
  private ICollectionRepository _repository;

  this(ICollectionRepository repository) {
    assert(repository !is null, "QueryInteractor needs a repository");
    _repository = repository;
  }

  DocumentData[] find(string collection, FindQuery input) {
    auto target = requireCollection(_repository, collection);
    DocumentQuery query;
    query.conditions = toConditions(input.where);
    if (input.sortField.length > 0) {
      query.sort = nullable(SortOrder(FieldPath(input.sortField),
          input.descending ? SortDirection.DESCENDING : SortDirection.ASCENDING));
    }
    query.skip = input.skip;
    query.limit = input.limit;
    return target.find(query).map!(d => DocumentData.from(d)).array;
  }

  size_t count(string collection, CountQuery input) {
    auto target = requireCollection(_repository, collection);
    return target.count(DocumentQuery(toConditions(input.where)));
  }
}

unittest {
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.datetime.systime : SysTime;
  import std.exception : assertThrown;
  import std.json : parseJSON;

  auto repository = new FakeCollectionRepository;
  auto users = new DocumentCollection("users");
  users.insertAll([
    Document("a", parseJSON(`{"age":36,"city":"London"}`), SysTime(0)),
    Document("b", parseJSON(`{"age":25,"city":"Rome"}`), SysTime(0)),
    Document("c", parseJSON(`{"age":30,"city":"Rome"}`), SysTime(0)),
  ]);
  repository.save(users);
  auto queries = new QueryInteractor(repository);
  auto ids = (DocumentData[] docs) => docs.map!(d => d.id).array;

  auto rome = [ConditionInput("city", "", parseJSON(`"Rome"`))];
  assert(ids(queries.find("users", FindQuery(rome))) == ["b", "c"]);
  assert(ids(queries.find("users", FindQuery(rome, "age", true))) == ["c", "b"]);
  assert(ids(queries.find("users", FindQuery(null, "age", false, 1, 1))) == ["c"]);
  assert(queries.count("users", CountQuery([ConditionInput("age", ">=", parseJSON("30"))])) == 2);
  assert(queries.count("users", CountQuery()) == 3);

  assertThrown!ValidationException(queries.find("users", FindQuery([ConditionInput("age", "~", parseJSON("1"))])));
  assertThrown!ValidationException(queries.find("users", FindQuery(null, "a..b")));
  assertThrown!CollectionNotFoundException(queries.count("nope", CountQuery()));
}
