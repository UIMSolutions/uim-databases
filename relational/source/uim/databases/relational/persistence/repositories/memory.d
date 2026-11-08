/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.persistence.repositories.memory;

import uim.databases.relational.domain.entities : Table;
import uim.databases.relational.ports.repositories : ITableRepository;
import std.algorithm : map, sort;
import std.array : array;

@safe:

/// Driven adapter: keeps tables in process memory. Data is lost on restart.
///
/// Tables are held by reference, so `save` has nothing to copy; it exists so that durable adapters
/// (files, a SQL store via persistence/storages + mappers + records) can be swapped in without
/// touching the interactors. No method yields to the vibe.d event loop, so every call is atomic for
/// fibers on one thread; share an instance across threads only behind a lock.
final class InMemoryTableRepository : ITableRepository {
  private Table[string] _tables;

  void save(Table table) {
    assert(table !is null);
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

unittest {
  import uim.databases.relational.domain;

  auto repository = new InMemoryTableRepository;
  auto b = new Table(TableSchema("b", [ColumnDefinition("x", ColumnType.INTEGER)]));
  auto a = new Table(TableSchema("a", [ColumnDefinition("x", ColumnType.INTEGER)]));
  repository.save(b);
  repository.save(a);
  assert(repository.names == ["a", "b"] && repository.all[0] is a);
  assert(repository.find("b") is b && repository.find("c") is null);
  assert(repository.remove("a") && !repository.remove("a") && !repository.exists("a"));
}
