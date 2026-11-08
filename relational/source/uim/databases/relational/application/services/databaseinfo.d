/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.application.services.databaseinfo;

import uim.databases.relational.application.dtos;
import uim.databases.relational.ports;
import std.algorithm : map;
import std.array : array;

@safe:

/// Application-wide service: health and statistics of the whole database.
final class DatabaseInfoService : IDatabaseInfoService {
  private {
    ITableRepository _repository;
    string _databaseName;
  }

  this(ITableRepository repository, string databaseName) {
    assert(repository !is null, "DatabaseInfoService needs a repository");
    _repository = repository;
    _databaseName = databaseName;
  }

  HealthStatus health() {
    return HealthStatus("healthy", "relational-database", _repository.names().length);
  }

  DatabaseStatistics statistics() {
    auto tables = _repository.all()
      .map!(t => TableStatistics(t.name, t.rowCount, t.schema.columns.length))
      .array;
    return DatabaseStatistics(_databaseName, tables.length, tables);
  }
}

unittest {
  import uim.databases.relational.domain;
  import uim.databases.relational.ports.repositories.fakes : FakeTableRepository;

  auto repository = new FakeTableRepository;
  auto t = new Table(TableSchema("t", [ColumnDefinition("a", ColumnType.INTEGER), ColumnDefinition("b", ColumnType.STRING)]));
  t.insert(["a": Value.integer(1)]);
  repository.save(t);

  auto info = new DatabaseInfoService(repository, "main");
  assert(info.health() == HealthStatus("healthy", "relational-database", 1));
  assert(info.statistics() == DatabaseStatistics("main", 1, [TableStatistics("t", 1, 2)]));
}
