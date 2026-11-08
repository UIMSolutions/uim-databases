/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: row data (DML) of one table. Every method throws TableNotFoundException for unknown tables.
module uim.databases.relational.ports.usecases.rows;

import uim.databases.relational.application.dtos;
import uim.databases.relational.domain.types : QueryResult, RowData;

interface IRowUseCase {
@safe:
  /// Inserts all rows or none and returns their row ids.
  /// Throws: ValidationException, ConstraintViolationException.
  ulong[] insert(string table, RowData[] rows);

  /// Throws: ValidationException.
  QueryResult select(string table, SelectRequest request);

  /// Returns the number of updated rows. Throws: ValidationException, ConstraintViolationException.
  size_t update(string table, UpdateCommand command);

  /// Returns the number of deleted rows. Throws: ValidationException (also for an empty WHERE).
  size_t remove(string table, DeleteCommand command);

  size_t count(string table);

  /// `key` is the primary key as text (e.g. taken from a URL) and is parsed by the key column's type.
  /// Throws: ValidationException, RowNotFoundException.
  RowData findByPrimaryKey(string table, string key);
}
