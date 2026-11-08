/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.infrastructure.repositories.bson;

import uim.hdb;
import uim.hdb.domain.value : SqlNull = Null;
import std.sumtype : match;
import uim.hdb.infrastructure.repositories.binary : LittleEndianReader;
import std.algorithm : canFind;
import std.bitmanip : nativeToLittleEndian;
import std.conv : to;
import std.exception : enforce;
import std.utf : validate;
import vibe.data.json : Json;

@safe:

/// Tabellen als BSON-Dokumente (<name>.bson), lesbar mit bsondump, mongosh und jedem MongoDB-Treiber:
///
///   { format: "hdb-table", version: 1, name: "t",
///     columns: [ { name: "id", type: "INTEGER" }, ... ],
///     rows: [ [ 1, "a", null ], ... ] }
///
/// INTEGER und die kleineren Ganzzahltypen sind int64, DOUBLE und REAL double, BOOLEAN bool, NULL null, alles
/// andere string (auch exakte Dezimalzahlen: als Text bleiben alle Stellen erhalten).
///
/// Gelesen wird mit einem eigenen, strengen Parser statt vibe.data.bson: der prüft Längenangaben nicht, und eine
/// beschädigte Datei könnte den Server zum Absturz bringen, statt den Start mit einer Meldung abzubrechen.
/// BSON begrenzt ein Dokument auf 2 GB; MongoDB selbst nimmt nur Dokumente bis 16 MB an.
final class BsonTableRepository : SnapshotTableRepository {
    private enum format = "hdb-table";
    private enum formatVersion = 1;

    this(string directory) {
        super(directory, "bson");
        loadAll();
    }

    protected override immutable(ubyte)[] encodeBytes(ColumnTable t) {
        BsonWriter w;
        auto root = w.begin();
        w.text("format", format);
        w.int32("version", formatVersion);
        w.text("name", t.name);
        auto columns = w.begin("columns", true);
        foreach (i, d; t.defs) {
            auto column = w.begin(i.to!string, false);
            w.text("name", d.name);
            w.text("type", typeName(d.type));
            w.end(column);
        }
        w.end(columns);
        auto rows = w.begin("rows", true);
        size_t index;
        foreach (row; t.liveRows()) {
            auto r = w.begin((index++).to!string, true);
            foreach (c; 0 .. t.defs.length) {
                auto key = c.to!string;
                t.value(c, row).match!(
                    (bool x) => w.boolean(key, x), // vor long: bool passt sonst auch dort
                    (long x) => w.int64(key, x),
                    (double x) => w.float64(key, x),
                    (string x) => w.text(key, x),
                    (SqlNull _) => w.null_(key),
                    (Exact x) => w.text(key, x.text)
                );
            }
            w.end(r);
        }
        w.end(rows);
        w.end(root);
        return w.buffer.idup;
    }

    protected override ColumnTable decodeBytes(immutable(ubyte)[] content) {
        auto r = LittleEndianReader(content);
        auto document = readDocument(r, false, 0);
        enforce(r.remaining == 0, "Unexpected data after the BSON document");

        enforce(document["format"].type == Json.Type.string && document["format"].get!string == format,
            "Not an hdb BSON table");
        enforce(document["version"].type == Json.Type.int_ && document["version"].get!long == formatVersion,
            "Unsupported BSON table version");
        auto name = document["name"].get!string;
        ColumnDef[] defs;
        foreach (c; document["columns"].byValue)
            defs ~= ColumnDef(c["name"].get!string, parseTypeName(c["type"].get!string));
        enforce(defs.length, "BSON table without columns: " ~ name);
        auto table = new ColumnTable(name, defs, TableStorage.bson);
        auto row = new Value[defs.length];
        foreach (values; document["rows"].byValue) {
            enforce(values.type == Json.Type.array && values.length == defs.length, "Invalid row in BSON table " ~ name);
            foreach (i, d; defs)
                assign(row[i], tableValueFromJson(d.type, values[i]));
            table.insert(row.dup);
        }
        return table;
    }
}

/// Schreibt BSON; Dokumentlängen werden am Ende jedes Dokuments nachgetragen.
struct BsonWriter {
    ubyte[] buffer;

    /// Beginnt das Wurzeldokument.
    size_t begin() {
        auto at = buffer.length;
        buffer ~= [0, 0, 0, 0];
        return at;
    }

    /// Beginnt ein eingebettetes Dokument oder Array (Schlüssel "0", "1", ...).
    size_t begin(string key, bool array) {
        element(array ? 0x04 : 0x03, key);
        return begin();
    }

    void end(size_t at) {
        buffer ~= 0;
        auto length = buffer.length - at;
        enforce(length <= int.max, "Table too large for BSON (2 GB per document)");
        buffer[at .. at + 4] = nativeToLittleEndian(cast(int) length)[];
    }

    void text(string key, string value) {
        enforce(value.length < int.max, "Text too long for BSON");
        element(0x02, key);
        buffer ~= nativeToLittleEndian(cast(int)(value.length + 1))[];
        buffer ~= cast(const(ubyte)[]) value;
        buffer ~= 0;
    }

    void float64(string key, double value) {
        element(0x01, key);
        buffer ~= nativeToLittleEndian(value)[];
    }

    void boolean(string key, bool value) {
        element(0x08, key);
        buffer ~= value ? 1 : 0;
    }

    void null_(string key) {
        element(0x0A, key);
    }

    void int32(string key, int value) {
        element(0x10, key);
        buffer ~= nativeToLittleEndian(value)[];
    }

    void int64(string key, long value) {
        element(0x12, key);
        buffer ~= nativeToLittleEndian(value)[];
    }

    private void element(ubyte type, string key) {
        enforce(!key.canFind('\0'), "BSON keys can't contain NUL");
        buffer ~= type;
        buffer ~= cast(const(ubyte)[]) key;
        buffer ~= 0;
    }
}

private enum maxDepth = 8; // das Tabellenformat braucht 3 Ebenen

/// Liest ein BSON-Dokument als Json. Erlaubt sind nur die Typen, die das Tabellenformat schreibt; jede Länge wird
/// geprüft, doppelte Schlüssel und lückenhafte Arrays sind Fehler.
Json readDocument(ref LittleEndianReader r, bool array, int depth) {
    enforce(depth < maxDepth, "BSON document is nested too deeply");
    immutable start = r.position;
    immutable size = r.get!int;
    enforce(size >= 5 && cast(size_t) size - 4 <= r.remaining, "Invalid BSON document size");
    immutable end = start + size;
    auto result = array ? Json.emptyArray : Json.emptyObject;
    size_t index;
    while (true) {
        enforce(r.position < end, "BSON document is truncated");
        immutable type = r.get!ubyte;
        if (type == 0) {
            enforce(r.position == end, "BSON document size does not match its content");
            return result;
        }
        auto key = readKey(r, end);
        Json value;
        switch (type) {
        case 0x01:
            value = Json(r.get!double);
            break;
        case 0x02:
            immutable length = r.get!int;
            enforce(length >= 1, "Invalid BSON string length");
            auto bytes = r.take(length);
            enforce(bytes[$ - 1] == 0, "BSON string is not terminated");
            auto s = cast(string) bytes[0 .. $ - 1];
            validate(s);
            value = Json(s);
            break;
        case 0x03:
        case 0x04:
            value = readDocument(r, type == 0x04, depth + 1);
            break;
        case 0x08:
            immutable b = r.get!ubyte;
            enforce(b <= 1, "Invalid BSON boolean");
            value = Json(b == 1);
            break;
        case 0x0A:
            value = Json(null);
            break;
        case 0x10:
            value = Json(cast(long) r.get!int);
            break;
        case 0x12:
            value = Json(r.get!long);
            break;
        default:
            throw new Exception("Unsupported BSON type 0x" ~ type.to!string(16) ~ " for key " ~ key);
        }
        enforce(r.position <= end, "BSON element runs past its document");
        if (array) {
            enforce(key == index.to!string, "BSON array keys must be 0, 1, 2, ...");
            ++index;
            result.appendArrayElement(value); // ~= würde ein Array-Element auspacken
        } else {
            enforce(result[key].type == Json.Type.undefined, "Duplicate BSON key: " ~ key);
            result[key] = value;
        }
    }
}

private string readKey(ref LittleEndianReader r, size_t end) {
    immutable start = r.position;
    while (true) {
        enforce(r.position < end, "BSON key is not terminated");
        if (r.get!ubyte == 0)
            break;
    }
    auto key = cast(string) r.data[start .. r.position - 1];
    validate(key);
    return key;
}

unittest {
    import std.exception : assertThrown;
    import std.file : exists, read, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, "hdb-bson-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dir))
            rmdirRecurse(dir);

    auto defs = [ColumnDef("id", ColumnType.integer), ColumnDef("d", ColumnType.decimal), ColumnDef("s", ColumnType.text),
        ColumnDef("b", ColumnType.boolean), ColumnDef("x", ColumnType.exact), ColumnDef("blob", ColumnType.blob),
        ColumnDef("at", ColumnType.dateTime), ColumnDef("tiny", ColumnType.byte_), ColumnDef("f", ColumnType.single)];
    auto t = new ColumnTable("Docs", defs, TableStorage.bson);
    t.insert([Value(long.min), Value(0.1 + 0.2), Value("NUL \0 inside, ü"), Value(true),
        valueFromInput(ColumnType.exact, "-0.000000000000000000001"), valueFromInput(ColumnType.blob, "CAFE"),
        valueFromInput(ColumnType.dateTime, "2026-11-08T10:00:00Z"), Value(255L), valueFromInput(ColumnType.single, "2.25")]);
    t.insert([Value(7L), nullValue, nullValue, Value(false), nullValue, nullValue, nullValue, nullValue, nullValue]);

    auto repo = new BsonTableRepository(dir);
    repo.save(t);
    repo.flush("docs");
    auto path = buildPath(dir, "docs.bson");

    auto loaded = new BsonTableRepository(dir).get("Docs");
    assert(loaded.name == "Docs" && loaded.storage == TableStorage.bson && loaded.defs == defs);
    auto rows = loaded.liveRows();
    assert(rows.length == 2);
    foreach (c; 0 .. defs.length) {
        assert(loaded.value(c, rows[0]) == t.value(c, t.liveRows()[0]), defs[c].name);
        assert(loaded.value(c, rows[1]) == t.value(c, t.liveRows()[1]), defs[c].name);
    }

    // Bekanntes Dokument nach der BSON-Spezifikation: {"a": 1} als int32
    BsonWriter w;
    auto root = w.begin();
    w.int32("a", 1);
    w.end(root);
    assert(w.buffer == [0x0C, 0, 0, 0, 0x10, 'a', 0, 1, 0, 0, 0, 0]);
    auto rd = LittleEndianReader(w.buffer.idup);
    assert(readDocument(rd, false, 0)["a"].get!long == 1);

    // Beschädigungen: Exception statt Absturz
    auto good = readBytes(path);
    foreach (cut; [0, 3, 4, 10, good.length / 2, good.length - 1]) {
        write(path, good[0 .. cut]);
        assertThrown(new BsonTableRepository(dir));
    }
    auto bad = good.dup;
    bad[0] = 0xff; // Gesamtlänge
    write(path, bad);
    assertThrown(new BsonTableRepository(dir));
    write(path, good ~ cast(ubyte) 0);
    assertThrown(new BsonTableRepository(dir));

    ubyte[] document(void delegate(ref BsonWriter) @safe fill) {
        BsonWriter x;
        auto at = x.begin();
        fill(x);
        x.end(at);
        return x.buffer;
    }

    void table(ref BsonWriter x, string type, void delegate(ref BsonWriter) @safe row) {
        x.text("format", "hdb-table");
        x.int32("version", 1);
        x.text("name", "docs");
        auto cs = x.begin("columns", true);
        auto c0 = x.begin("0", false);
        x.text("name", "a");
        x.text("type", type);
        x.end(c0);
        x.end(cs);
        auto rs = x.begin("rows", true);
        auto r0 = x.begin("0", true);
        row(x);
        x.end(r0);
        x.end(rs);
    }

    write(path, document((ref x) { table(x, "INTEGER", (ref y) { y.text("0", "1"); }); }));
    assertThrown(new BsonTableRepository(dir)); // Text in INTEGER
    write(path, document((ref x) { table(x, "INTEGER", (ref y) { y.int64("1", 1); }); }));
    assertThrown(new BsonTableRepository(dir)); // Arrayschlüssel mit Lücke
    write(path, document((ref x) { table(x, "INTEGER", (ref y) { y.int64("0", 1); y.int64("1", 2); }); }));
    assertThrown(new BsonTableRepository(dir)); // zu viele Werte
    write(path, document((ref x) { x.text("format", "other"); }));
    assertThrown(new BsonTableRepository(dir));
    write(path, document((ref x) { x.text("a", "1"); x.text("a", "2"); }));
    assertThrown(new BsonTableRepository(dir)); // doppelter Schlüssel
    write(path, document((ref x) {
        size_t[] open;
        foreach (i; 0 .. 20)
            open ~= x.begin("n", false);
        foreach_reverse (at; open)
            x.end(at);
    }));
    assertThrown(new BsonTableRepository(dir)); // zu tief verschachtelt
    write(path, document((ref x) { table(x, "INTEGER", (ref y) { y.int32("0", 42); }); }));
    assert(new BsonTableRepository(dir).get("docs").value(0, 0) == Value(42L)); // int32 anderer Werkzeuge geht
}
