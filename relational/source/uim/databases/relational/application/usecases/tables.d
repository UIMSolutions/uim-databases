/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.application.usecases.tables;

import uim.databases.relational.application.dtos;
import uim.databases.relational.application.usecases.conversions;
import uim.databases.relational.domain;
import uim.databases.relational.ports;

@safe:

/// Interactor for table definitions.
final class TableCatalogInteractor : ITableCatalogUseCase {
  private ITableRepository _repository;

  this(ITableRepository repository) {
    assert(repository !is null, "TableCatalogInteractor needs a repository");
    _repository = repository;
  }

  TableSchemaView createTable(CreateTableCommand command) {
    auto schema = toSchema(command);
    if (_repository.exists(schema.tableName)) {
      throw new TableAlreadyExistsException(schema.tableName);
    }
    foreach (fk; schema.foreignKeys) {
      immutable selfReference = fk.referencedTable == schema.tableName;
      if (!selfReference && !_repository.exists(fk.referencedTable)) {
        throw new SchemaException("Foreign key " ~ fk.column ~ " references unknown table '" ~ fk.referencedTable ~ "'");
      }
      auto target = selfReference ? schema : _repository.find(fk.referencedTable).schema;
      if (!target.hasColumn(fk.referencedColumn)) {
        throw new SchemaException("Foreign key " ~ fk.column ~ " references unknown column '"
            ~ fk.referencedTable ~ "." ~ fk.referencedColumn ~ "'");
      }
    }
    _repository.save(new Table(schema));
    return TableSchemaView.from(schema);
  }

  void dropTable(string name) {
    requireTable(_repository, name);
    foreach (other; _repository.all()) {
      if (other.name == name) {
        continue;
      }
      foreach (fk; other.schema.foreignKeys) {
        if (fk.referencedTable == name) {
          throw new ConstraintViolationException("Table '" ~ name ~ "' is referenced by "
              ~ other.name ~ "." ~ fk.column ~ "; drop that table first");
        }
      }
    }
    _repository.remove(name);
  }

  string[] listTables() {
    return _repository.names();
  }

  TableSchemaView describeTable(string name) {
    return TableSchemaView.from(requireTable(_repository, name).schema);
  }
}

unittest {
  import uim.databases.relational.ports.repositories.fakes : FakeTableRepository;
  import std.exception : assertThrown;

  auto catalog = new TableCatalogInteractor(new FakeTableRepository);
  auto users = catalog.createTable(CreateTableCommand("users", [
        ColumnSpec("id", "INTEGER", false, true), ColumnSpec("name", "varchar")
      ]));
  assert(users.primaryKey == "id" && users.columns[1].type == "STRING");

  catalog.createTable(CreateTableCommand("orders", [
      ColumnSpec("id", "INTEGER", false, true), ColumnSpec("user_id", "INTEGER")
    ], [ForeignKeySpec("user_id", "users", "id")]));
  // Self reference is fine.
  catalog.createTable(CreateTableCommand("staff", [
      ColumnSpec("id", "INTEGER", false, true), ColumnSpec("boss", "INTEGER")
    ], [ForeignKeySpec("boss", "staff", "id")]));
  assert(catalog.listTables() == ["orders", "staff", "users"]);
  assert(catalog.describeTable("orders").foreignKeys == [ForeignKeyView("user_id", "users", "id")]);

  assertThrown!TableAlreadyExistsException(catalog.createTable(CreateTableCommand("users", [ColumnSpec("id", "INTEGER")])));
  assertThrown!SchemaException(catalog.createTable(CreateTableCommand("x", [ColumnSpec("a", "INTEGER")],
      [ForeignKeySpec("a", "missing", "id")])));
  assertThrown!SchemaException(catalog.createTable(CreateTableCommand("x", [ColumnSpec("a", "INTEGER")],
      [ForeignKeySpec("a", "users", "missing")])));
  assertThrown!SchemaException(catalog.createTable(CreateTableCommand("x", [ColumnSpec("a", "blob")])));

  assertThrown!ConstraintViolationException(catalog.dropTable("users"));
  catalog.dropTable("orders");
  catalog.dropTable("users");
  catalog.dropTable("staff"); // only references itself
  assertThrown!TableNotFoundException(catalog.dropTable("users"));
  assertThrown!TableNotFoundException(catalog.describeTable("users"));
}
