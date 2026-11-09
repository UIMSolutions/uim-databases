/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Helpers shared by the interactors.
module uim.databases.object.application.usecases.support;

import uim.databases.object.application.dtos.commands : ConditionInput;
import uim.databases.object.domain;
import uim.databases.object.ports.repositories;
import std.algorithm : map;
import std.array : array;

package(uim.databases.object.application) @safe:

/// Throws: CollectionNotFoundException.
DocumentCollection requireCollection(ICollectionRepository repository, string name) {
  auto collection = repository.find(name);
  if (collection is null) {
    throw new CollectionNotFoundException(name);
  }
  return collection;
}

/// Throws: ValidationException.
Condition[] toConditions(ConditionInput[] inputs) {
  return inputs.map!(i => Condition(FieldPath(i.field),
      i.op.length == 0 ? QueryOperator.EQUALS : parseQueryOperator(i.op), i.value)).array;
}
