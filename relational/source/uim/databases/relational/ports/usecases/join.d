/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: joins across tables.
module uim.databases.relational.ports.usecases.join;

import uim.databases.relational.application.dtos;
import uim.databases.relational.domain.types : QueryResult;

interface IJoinUseCase {
@safe:
  /// INNER JOIN; result columns are qualified as `table.column`.
  /// Throws: TableNotFoundException, ValidationException.
  QueryResult innerJoin(JoinRequest request);
}
