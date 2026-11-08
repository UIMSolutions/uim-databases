/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: table definitions (DDL).
module uim.databases.relational.ports.usecases.tables;

import uim.databases.relational.application.dtos;

interface ITableCatalogUseCase {
@safe:
  /// Foreign keys must reference an existing table and column (or the new table itself).
  /// Throws: SchemaException, TableAlreadyExistsException, TableNotFoundException.
  TableSchemaView createTable(CreateTableCommand command);

  /// Refused while another table references it. Throws: TableNotFoundException, ConstraintViolationException.
  void dropTable(string name);

  /// Names in ascending order.
  string[] listTables();

  /// Throws: TableNotFoundException.
  TableSchemaView describeTable(string name);
}
