/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.application.usecases.join;

import uim.databases.relational.application.dtos;
import uim.databases.relational.application.usecases.conversions;
import uim.databases.relational.domain;
import uim.databases.relational.ports;

@safe:

/// Interactor for joins; the join algorithm itself is a domain service.
final class JoinInteractor : IJoinUseCase {
  private ITableRepository _repository;

  this(ITableRepository repository) {
    assert(repository !is null, "JoinInteractor needs a repository");
    _repository = repository;
  }

  QueryResult innerJoin(JoinRequest request) {
    auto left = requireTable(_repository, request.leftTable);
    auto right = requireTable(_repository, request.rightTable);
    return uim.databases.relational.domain.services.join.innerJoin(left, request.leftColumn,
      toConditions(request.leftWhere), right, request.rightColumn, toConditions(request.rightWhere));
  }
}

unittest {
  import uim.databases.relational.ports.repositories.fakes : FakeTableRepository;
  import std.exception : assertThrown;

  auto repository = new FakeTableRepository;
  auto users = new Table(TableSchema("users", [ColumnDefinition("id", ColumnType.INTEGER, false, true)]));
  auto orders = new Table(TableSchema("orders", [ColumnDefinition("user_id", ColumnType.INTEGER)]));
  users.insertAll([["id": Value.integer(1)], ["id": Value.integer(2)]]);
  orders.insertAll([["user_id": Value.integer(2)], ["user_id": Value.integer(2)]]);
  repository.save(users);
  repository.save(orders);

  auto join = new JoinInteractor(repository);
  assert(join.innerJoin(JoinRequest("users", "orders", "id", "user_id")).count == 2);
  assert(join.innerJoin(JoinRequest("users", "orders", "id", "user_id",
      [ConditionSpec("id", "=", Value.integer(1))])).count == 0);
  assertThrown!TableNotFoundException(join.innerJoin(JoinRequest("users", "nope", "id", "x")));
}
