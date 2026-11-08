/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.application.usecases.rows;

import uim.databases.relational.application.dtos;
import uim.databases.relational.application.usecases.conversions;
import uim.databases.relational.domain;
import uim.databases.relational.ports;

@safe:

/// Interactor for the rows of a table.
final class RowInteractor : IRowUseCase {
  private ITableRepository _repository;

  this(ITableRepository repository) {
    assert(repository !is null, "RowInteractor needs a repository");
    _repository = repository;
  }

  ulong[] insert(string tableName, RowData[] rows) {
    auto table = requireTable(_repository, tableName);
    auto ids = table.insertAll(rows);
    _repository.save(table);
    return ids;
  }

  QueryResult select(string tableName, SelectRequest request) {
    return requireTable(_repository, tableName).select(toQuery(request));
  }

  size_t update(string tableName, UpdateCommand command) {
    auto table = requireTable(_repository, tableName);
    immutable changed = table.update(command.changes, toConditions(command.where));
    if (changed > 0) {
      _repository.save(table);
    }
    return changed;
  }

  size_t remove(string tableName, DeleteCommand command) {
    auto table = requireTable(_repository, tableName);
    if (command.where.length == 0) {
      throw new ValidationException("DELETE without WHERE is not allowed");
    }
    immutable deleted = table.remove(toConditions(command.where));
    if (deleted > 0) {
      _repository.save(table);
    }
    return deleted;
  }

  size_t count(string tableName) {
    return requireTable(_repository, tableName).rowCount;
  }

  RowData findByPrimaryKey(string tableName, string key) {
    auto table = requireTable(_repository, tableName);
    immutable pk = table.schema.primaryKey;
    if (pk.length == 0) {
      throw new InvalidQueryException("Table '" ~ tableName ~ "' has no primary key");
    }
    auto found = table.findByPrimaryKey(parseLiteral(key, table.schema.column(pk).type));
    if (found.isNull) {
      throw new RowNotFoundException(tableName, key);
    }
    return found.get;
  }
}

unittest {
  import uim.databases.relational.ports.repositories.fakes : FakeTableRepository;
  import std.algorithm : map;
  import std.array : array;
  import std.exception : assertThrown;

  auto repository = new FakeTableRepository;
  repository.save(new Table(TableSchema("users", [
      ColumnDefinition("id", ColumnType.INTEGER, false, true),
      ColumnDefinition("name", ColumnType.STRING, false),
      ColumnDefinition("age", ColumnType.INTEGER),
    ])));
  auto rows = new RowInteractor(repository);

  RowData user(long id, string name, long age) {
    return ["id": Value.integer(id), "name": Value.text(name), "age": Value.integer(age)];
  }

  immutable savesBefore = repository.saves;
  assert(rows.insert("users", [user(1, "Ada", 36), user(2, "Bob", 25), user(3, "Cy", 41)]) == [1, 2, 3]);
  assert(repository.saves == savesBefore + 1);
  assert(rows.count("users") == 3);

  auto older = rows.select("users", SelectRequest(["name"], [ConditionSpec("age", ">", Value.integer(30))], "age", false));
  assert(older.rows.map!(r => r["name"].asText).array == ["Cy", "Ada"]);
  auto some = rows.select("users", SelectRequest(null, [ConditionSpec("id", "IN", Value.null_, [Value.integer(1), Value.integer(3)])]));
  assert(some.count == 2);

  assert(rows.update("users", UpdateCommand(["age": Value.integer(26)], [ConditionSpec("name", "=", Value.text("Bob"))])) == 1);
  assert(rows.findByPrimaryKey("users", "2")["age"] == Value.integer(26));

  assertThrown!ValidationException(rows.remove("users", DeleteCommand()));
  assert(rows.remove("users", DeleteCommand([ConditionSpec("name", "LIKE", Value.text("C%"))])) == 1);

  assertThrown!RowNotFoundException(rows.findByPrimaryKey("users", "3"));
  assertThrown!ValidationException(rows.findByPrimaryKey("users", "three"));
  assertThrown!InvalidQueryException(rows.select("users", SelectRequest(null, [ConditionSpec("age", "~", Value.integer(1))])));
  assertThrown!InvalidQueryException(rows.select("users", SelectRequest(null, [ConditionSpec("age", "=")])));
  assertThrown!TableNotFoundException(rows.count("nope"));
  assertThrown!ConstraintViolationException(rows.insert("users", [user(1, "Again", 1)]));
}
