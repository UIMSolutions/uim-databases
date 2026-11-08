/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Test double for the repository port, so application and presentation tests never depend on persistence.
module uim.databases.relational.ports.repositories.fakes;

version (unittest):

import uim.databases.relational.domain.entities : Table;
import uim.databases.relational.ports.repositories.tables;
import std.algorithm : map, sort;
import std.array : array;

@safe:

final class FakeTableRepository : ITableRepository {
  private Table[string] _tables;
  size_t saves;

  void save(Table table) {
    saves++;
    _tables[table.name] = table;
  }

  Table find(string name) {
    auto found = name in _tables;
    return found is null ? null : *found;
  }

  bool remove(string name) {
    return _tables.remove(name);
  }

  bool exists(string name) {
    return (name in _tables) !is null;
  }

  string[] names() {
    return _tables.keys.sort.release;
  }

  Table[] all() {
    return names().map!(n => _tables[n]).array;
  }
}
