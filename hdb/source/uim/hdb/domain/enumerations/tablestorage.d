/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.hdb.domain.enumerations.tablestorage;

import uim.hdb;
import std.string : strip, toUpper;

@safe:

/// Where a table is permanently stored. Queries are always performed in main memory.
enum TableStorage {
    memory, // Hauptspeicher, Wiederherstellung über das Anweisungsprotokoll
    file, // eigene Textdatei je Tabelle
    json, // eigene JSON-Datei je Tabelle
    binary, // eigene kompakte Binärdatei je Tabelle, mit Prüfsumme
    bson // eigenes BSON-Dokument je Tabelle, lesbar mit bsondump und MongoDB-Treibern
}

string storageName(TableStorage storage) {
    final switch (storage) {
    case TableStorage.memory:
        return "MEMORY";
    case TableStorage.file:
        return "FILE";
    case TableStorage.json:
        return "JSON";
    case TableStorage.binary:
        return "BINARY";
    case TableStorage.bson:
        return "BSON";
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
    case "BINARY":
        return TableStorage.binary;
    case "BSON":
        return TableStorage.bson;
    default:
        throw new Exception("Unbekannter Speicher: " ~ name ~ " (MEMORY, FILE, JSON, BINARY oder BSON)");
    }
}

unittest {
    import std.exception : assertThrown;

    foreach (s; [TableStorage.memory, TableStorage.file, TableStorage.json, TableStorage.binary, TableStorage.bson])
        assert(parseStorage(storageName(s)) == s);
    assert(parseStorage(" json ") == TableStorage.json);
    assertThrown(parseStorage("disk"));
}
