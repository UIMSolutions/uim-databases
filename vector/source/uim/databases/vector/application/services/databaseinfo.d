/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.application.services.databaseinfo;

import uim.databases.vector.application.dtos;
import uim.databases.vector.ports;
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
    return HealthStatus("healthy", "vector-database", _repository.all().length);
  }

  DatabaseStatistics statistics() {
    auto collections = _repository.all().map!(c => CollectionInfo.from(c)).array;
    return DatabaseStatistics(_databaseName, collections.length, collections.map!(c => c.count).sum(size_t(0)),
      collections);
  }
}

unittest {
  import uim.databases.vector.domain;
  import uim.databases.vector.ports.repositories.fakes : FakeCollectionRepository;

  auto repository = new FakeCollectionRepository;
  auto docs = new VectorCollection("docs", 1);
  docs.addAll([VectorRecord("a", Embedding([1.0])), VectorRecord("b", Embedding([2.0]))]);
  repository.save(docs);
  repository.save(new VectorCollection("empty", 4, DistanceMetric.COSINE));

  auto info = new DatabaseInfoService(repository, "main");
  assert(info.health() == HealthStatus("healthy", "vector-database", 2));
  assert(info.statistics() == DatabaseStatistics("main", 2, 2,
      [CollectionInfo("docs", 1, "EUCLIDEAN", 2), CollectionInfo("empty", 4, "COSINE", 0)]));
}
