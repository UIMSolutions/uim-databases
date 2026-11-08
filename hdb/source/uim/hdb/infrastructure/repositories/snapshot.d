/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.infrastructure.repositories.snapshot;

import uim.hdb.application.ports;
import uim.hdb.domain.table;
import std.algorithm : sort;
import std.array : array;
import std.exception : enforce;
import std.file : dirEntries, exists, mkdirRecurse, read, remove, rename, SpanMode;
import std.path : baseName, buildPath, stripExtension;
import std.stdio : File;
import std.string : toLower;

@safe:

/// Gemeinsame Grundlage für Repositories mit einer Datei je Tabelle. Tabellen liegen zum Abfragen im Speicher,
/// flush schreibt die ganze Tabelle neu: Aufwand O(Tabelle) je Schreibvorgang. Die Datei wird über eine temporäre
/// Datei und rename ersetzt, nach einem Absturz liegt also der alte oder der neue Stand vor, nie ein halber.
/// Eine beschädigte Datei bricht den Start ab, statt die Tabelle stillschweigend zu verlieren.
abstract class SnapshotTableRepository : ITableRepository, IDurableTableRepository {
    private string directory, extension;
    private ColumnTable[string] store;

    protected this(string directory, string extension) {
        this.directory = directory;
        this.extension = extension;
        if (!exists(directory))
            mkdirRecurse(directory);
    }

    /// Inhalt der Datei einer Tabelle. Textformate leiten von TextTableRepository ab.
    protected abstract immutable(ubyte)[] encodeBytes(ColumnTable table);
    /// Liest den Inhalt einer Datei vollständig und prüft ihn; wirft bei jedem Fehler.
    protected abstract ColumnTable decodeBytes(immutable(ubyte)[] content);

    /// Liest alle Tabellen; die abgeleitete Klasse ruft das am Ende ihres Konstruktors auf.
    protected final void loadAll() {
        foreach (entry; filesIn(directory, "*." ~ extension)) {
            auto table = decodeBytes(readBytes(entry));
            enforce(table.name.toLower == baseName(entry).stripExtension,
                "Tabellenname passt nicht zur Datei: " ~ entry);
            store[table.name.toLower] = table;
        }
    }

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

    void flush(string name) {
        auto key = name.toLower;
        auto path = buildPath(directory, key ~ "." ~ extension);
        auto table = key in store;
        if (table is null) {
            if (.exists(path))
                .remove(path);
            return;
        }
        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        f.rawWrite(encodeBytes(*table));
        f.flush();
        f.sync(); // sonst könnte rename nach einem Absturz auf eine leere Datei zeigen
        f.close();
        rename(tmp, path);
    }
}

/// Für Textformate: die Datei ist UTF-8, ungültiger Text bricht den Start ab.
abstract class TextTableRepository : SnapshotTableRepository {
    protected this(string directory, string extension) {
        super(directory, extension);
    }

    protected abstract string encode(ColumnTable table);
    protected abstract ColumnTable decode(string content);

    protected override immutable(ubyte)[] encodeBytes(ColumnTable table) {
        return cast(immutable(ubyte)[]) encode(table);
    }

    protected override ColumnTable decodeBytes(immutable(ubyte)[] content) {
        import std.utf : validate;

        auto text = cast(string) content;
        validate(text);
        return decode(text);
    }
}

/// Dateien eines Verzeichnisses (nicht rekursiv), deren Name zum Muster passt, sortiert.
/// @trusted: dirEntries ist @system, weil der Iterator interne Zeiger hält; zurück kommt nur eine fertige Liste.
string[] filesIn(string directory, string pattern) @trusted {
    import std.algorithm : map, sort;
    import std.array : array;
    import std.file : dirEntries, SpanMode;

    return dirEntries(directory, pattern, SpanMode.shallow).map!(e => e.name).array.sort.release;
}

/// Inhalt einer Datei als Bytes. @trusted: read liefert void[]; der Puffer ist frisch angelegt und gehört nur uns,
/// die Umwandlung in unveränderliche Bytes ist deshalb sicher.
immutable(ubyte)[] readBytes(string path) @trusted {
    import std.exception : assumeUnique;
    import std.file : read;

    return assumeUnique(cast(ubyte[]) read(path));
}
