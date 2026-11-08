module uim.hdb.domain.enumerations.tablestorage;

import uim.hdb;
import std.string : strip, toUpper;

/// Where a table is permanently stored. Queries are always performed in main memory.
enum TableStorage {
    memory, // Hauptspeicher, Wiederherstellung über das Anweisungsprotokoll
    file, // eigene Textdatei je Tabelle
    json // eigene JSON-Datei je Tabelle
}

string storageName(TableStorage storage) {
    final switch (storage) {
    case TableStorage.memory:
        return "MEMORY";
    case TableStorage.file:
        return "FILE";
    case TableStorage.json:
        return "JSON";
    }
}

TableStorage parseStorage(string name) {
    switch (name.strip.toUpper) {
    case "MEMORY":
        return TableStorage.memory;
    case "FILE":
        return TableStorage.file;
    case "JSON":
        return TableStorage.json;
    default:
        throw new Exception("Unbekannter Speicher: " ~ name ~ " (MEMORY, FILE oder JSON)");
    }
}

unittest {
    import std.exception : assertThrown;

    foreach (s; [TableStorage.memory, TableStorage.file, TableStorage.json])
        assert(parseStorage(storageName(s)) == s);
    assert(parseStorage(" json ") == TableStorage.json);
    assertThrown(parseStorage("disk"));
}
