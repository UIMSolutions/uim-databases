/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.application.services.databaseinfo;

import uim.databases.object.application.dtos;
import uim.databases.object.ports;
import std.algorithm : map, sum;
import std.array : array;

@safe:

/// Application-wide service: health and statistics of the whole database.
final class DatabaseInfoService : IDatabaseInfoService {
  private {
    ICollectionRepository _repository;
    string _databaseName;
  }

  this(ICollectionRepository repository, string databaseName) {
    assert(repository !is null, "DatabaseInfoService needs a repository");
    _repository = repository;
    _databaseName = databaseName;
  }

  HealthStatus health() {
    return HealthStatus("healthy", "object-database", _repository.all().length);
  }

  DatabaseStatistics statistics() {
    auto collections = _repository.all().map!(c => CollectionInfo.from(c)).array;
    return DatabaseStatistics(_databaseName, collections.length,
      collections.map!(c => c.documentCount).sum(size_t(0)), collections);
  }
}

unittest {
  import uim.databases.object.domain;
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.datetime.systime : SysTime;
  import std.json : parseJSON;

  auto repository = new FakeCollectionRepository;
  auto users = new DocumentCollection("users");
  users.insertAll([Document("a", parseJSON("{}"), SysTime(0)), Document("b", parseJSON("{}"), SysTime(0))]);
  users.createIndex(FieldPath("name"));
  repository.save(users);
  repository.save(new DocumentCollection("empty"));

  auto info = new DatabaseInfoService(repository, "main");
  assert(info.health() == HealthStatus("healthy", "object-database", 2));
  assert(info.statistics() == DatabaseStatistics("main", 2, 2,
      [CollectionInfo("empty", 0, null), CollectionInfo("users", 2, ["name"])]));
}
