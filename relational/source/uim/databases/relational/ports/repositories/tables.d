/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driven port: storage of tables. Implemented in persistence/repositories.
module uim.databases.relational.ports.repositories.tables;

import uim.databases.relational.domain.entities : Table;

interface ITableRepository {
@safe:
  /// Inserts the table or stores its new state. Interactors call it after every change.
  void save(Table table);

  /// null when there is no such table.
  Table find(string name);

  /// False if there was nothing to remove.
  bool remove(string name);

  bool exists(string name);

  /// Table names in ascending order.
  string[] names();

  /// All tables, ordered by name.
  Table[] all();
}
