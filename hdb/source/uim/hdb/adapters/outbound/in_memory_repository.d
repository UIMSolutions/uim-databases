module uim.hdb.adapters.outbound.in_memory_repository;

import uim.hdb.application.ports;
import uim.hdb.domain.table;
import std.algorithm : sort;
import std.array : array;
import std.exception : enforce;
import std.string : toLower;

/// Ausgehender Adapter: hält alle Tabellen im Hauptspeicher.
final class InMemoryTableRepository : ITableRepository {
    private ColumnTable[string] store;

    bool exists(string name) {
        return (name.toLower in store) !is null;
    }

    ColumnTable get(string name) {
        auto p = name.toLower in store;
        enforce(p, "Tabelle nicht gefunden: " ~ name);
        return *p;
    }

    void save(ColumnTable table) {
        store[table.name.toLower] = table;
    }

    void remove(string name) {
        store.remove(name.toLower);
    }

    string[] list() {
        return store.keys.sort.array;
    }
}
