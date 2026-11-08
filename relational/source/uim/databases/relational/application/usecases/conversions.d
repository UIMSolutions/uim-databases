/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Turns request DTOs into validated domain types (shared by the interactors).
module uim.databases.relational.application.usecases.conversions;

import uim.databases.relational.application.dtos;
import uim.databases.relational.domain;
import uim.databases.relational.ports.repositories;
import std.algorithm : map;
import std.array : array;

package(uim.databases.relational.application) @safe:

Condition toCondition(const ConditionSpec spec) {
  return Condition(spec.column, parseComparisonOperator(spec.op), spec.value, spec.values.dup);
}

Condition[] toConditions(const ConditionSpec[] specs) {
  return specs.map!(s => toCondition(s)).array;
}

Query toQuery(const SelectRequest request) {
  Ordering[] orderBy;
  if (request.orderBy.length > 0) {
    orderBy = [Ordering(request.orderBy, request.ascending ? SortDirection.ascending : SortDirection.descending)];
  }
  return Query(request.columns.dup, toConditions(request.where), orderBy, request.limit, request.offset);
}

TableSchema toSchema(const CreateTableCommand command) {
  auto columns = command.columns
    .map!(c => ColumnDefinition(c.name, parseColumnType(c.type), c.nullable, c.primaryKey, c.unique, c.defaultValue))
    .array;
  auto foreignKeys = command.foreignKeys.map!(f => ForeignKey(f.column, f.refTable, f.refColumn)).array;
  return TableSchema(command.name, columns, foreignKeys);
}

/// Throws: TableNotFoundException.
Table requireTable(ITableRepository repository, string name) {
  auto table = repository.find(name);
  if (table is null) {
    throw new TableNotFoundException(name);
  }
  return table;
}
