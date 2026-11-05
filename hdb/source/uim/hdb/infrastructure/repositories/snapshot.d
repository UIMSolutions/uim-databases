module uim.hdb.infrastructure.repositories.snapshot;

import uim.hdb.application.ports;
import uim.hdb.domain.table;
import std.algorithm : sort;
import std.array : array;
import std.exception : enforce;
import std.file : dirEntries, exists, mkdirRecurse, readText, remove, rename, SpanMode;
import std.path : baseName, buildPath, stripExtension;
import std.stdio : File;
import std.string : toLower;

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

    protected abstract string encode(ColumnTable table);
    protected abstract ColumnTable decode(string content);

    /// Liest alle Tabellen; die abgeleitete Klasse ruft das am Ende ihres Konstruktors auf.
    protected final void loadAll() {
        foreach (entry; dirEntries(directory, "*." ~ extension, SpanMode.shallow)) {
            auto table = decode(readText(entry.name));
            enforce(table.name.toLower == baseName(entry.name).stripExtension,
                "Tabellenname passt nicht zur Datei: " ~ entry.name);
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
        f.write(encode(*table));
        f.flush();
        f.sync(); // sonst könnte rename nach einem Absturz auf eine leere Datei zeigen
        f.close();
        rename(tmp, path);
    }
}
