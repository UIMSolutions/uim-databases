/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.infrastructure.repositories.binary;

import uim.hdb;
import uim.hdb.domain.value : SqlNull = Null;
import std.sumtype : match;
import std.array : appender, Appender;
import std.bitmanip : littleEndianToNative, nativeToLittleEndian;
import std.digest.sha : sha256Of;
import std.exception : enforce;
import std.utf : validate;
import vibe.data.json : Json;

@safe:

/// Tabellen als kompakte Binärdateien (<name>.bin), alle Zahlen little-endian:
///
///   "HDBTBIN" 0x00               Kennung, 8 Byte
///   u16 Version (1)
///   str Tabellenname
///   u32 Spaltenzahl, je Spalte: str Name, str Typ (wie in CREATE TABLE)
///   u64 Zeilenzahl, je Zeile ein Wert je Spalte:
///       u8 0 NULL | 1 i64 | 2 f64 (IEEE 754) | 3 str | 4 u8 bool | 5 str exakte Dezimalzahl
///   32 Byte SHA-256 über alles davor
///
/// str ist u32 Länge plus UTF-8. Zahlen bleiben bitgenau, Text wird nicht maskiert. Beim Lesen wird jeder Wert gegen
/// seinen Spaltentyp geprüft wie bei JSON-Tabellen: die Datei gilt nicht als vertrauenswürdiger als eine Sicherung.
final class BinaryTableRepository : SnapshotTableRepository {
    private static immutable ubyte[8] magic = ['H', 'D', 'B', 'T', 'B', 'I', 'N', 0];
    private enum ushort formatVersion = 1;
    private enum checksumLength = 32;

    this(string directory) {
        super(directory, "bin");
        loadAll();
    }

    protected override immutable(ubyte)[] encodeBytes(ColumnTable t) {
        auto w = LittleEndianWriter(appender!(ubyte[]));
        w.bytes(magic[]);
        w.put!ushort(formatVersion);
        w.text(t.name);
        w.put!uint(cast(uint) t.defs.length);
        foreach (d; t.defs) {
            w.text(d.name);
            w.text(typeName(d.type));
        }
        auto rows = t.liveRows();
        w.put!ulong(rows.length);
        foreach (row; rows)
            foreach (c; 0 .. t.defs.length)
                writeValue(w, t.value(c, row));
        auto body_ = w.data;
        w.bytes(sha256Of(body_)[]);
        return w.data.idup;
    }

    protected override ColumnTable decodeBytes(immutable(ubyte)[] content) {
        enforce(content.length >= magic.length + checksumLength, "Binary table file is truncated");
        auto body_ = content[0 .. $ - checksumLength];
        enforce(sha256Of(body_)[] == content[$ - checksumLength .. $], "Binary table file is damaged (checksum)");

        auto r = LittleEndianReader(body_);
        enforce(r.take(magic.length) == magic[], "Not an hdb binary table");
        enforce(r.get!ushort == formatVersion, "Unsupported binary table version");
        auto name = r.text();
        auto columnCount = r.get!uint;
        enforce(columnCount > 0 && columnCount <= r.remaining / 8, "Invalid column count in binary table " ~ name);
        ColumnDef[] defs;
        foreach (i; 0 .. columnCount) {
            auto columnName = r.text();
            defs ~= ColumnDef(columnName, parseTypeName(r.text()));
        }
        auto table = new ColumnTable(name, defs, TableStorage.binary);
        auto rowCount = r.get!ulong;
        enforce(rowCount <= r.remaining / defs.length, "Invalid row count in binary table " ~ name); // je Wert >= 1 Byte
        auto row = new Value[defs.length];
        foreach (n; 0 .. rowCount) {
            foreach (c, d; defs)
                assign(row[c], tableValueFromJson(d.type, readValue(r)));
            table.insert(row.dup);
        }
        enforce(r.remaining == 0, "Unexpected data at the end of binary table " ~ name);
        return table;
    }

    private static void writeValue(ref LittleEndianWriter w, Value v) {
        v.match!(
            (bool x) { w.put!ubyte(4); w.put!ubyte(x ? 1 : 0); }, // vor long: bool passt sonst auch dort
            (long x) { w.put!ubyte(1); w.put!long(x); },
            (double x) { w.put!ubyte(2); w.put!double(x); },
            (string x) { w.put!ubyte(3); w.text(x); },
            (SqlNull _) { w.put!ubyte(0); },
            (Exact x) { w.put!ubyte(5); w.text(x.text); }
        );
    }

    /// Als Json, damit tableValueFromJson Typ und Inhalt prüft wie bei JSON-Tabellen.
    private static Json readValue(ref LittleEndianReader r) {
        switch (r.get!ubyte) {
        case 0:
            return Json(null);
        case 1:
            return Json(r.get!long);
        case 2:
            return Json(r.get!double);
        case 3:
        case 5:
            return Json(r.text());
        case 4:
            auto b = r.get!ubyte;
            enforce(b <= 1, "Invalid boolean in binary table");
            return Json(b == 1);
        default:
            throw new Exception("Unknown value tag in binary table");
        }
    }
}

/// Schreibt Zahlen little-endian; auch für BSON.
struct LittleEndianWriter {
    Appender!(ubyte[]) buffer;

    void put(T)(T value) {
        buffer ~= nativeToLittleEndian(value)[];
    }

    void bytes(const(ubyte)[] data) {
        buffer ~= data;
    }

    /// u32 Länge plus UTF-8.
    void text(string s) {
        enforce(s.length <= uint.max, "Text too long");
        put!uint(cast(uint) s.length);
        buffer ~= cast(const(ubyte)[]) s;
    }

    ubyte[] data() {
        return buffer[];
    }
}

/// Liest little-endian mit Prüfung jeder Länge: eine kaputte Datei ergibt eine Exception, nie einen Absturz.
struct LittleEndianReader {
    immutable(ubyte)[] data;
    size_t position;

    size_t remaining() const {
        return data.length - position;
    }

    immutable(ubyte)[] take(size_t n) {
        enforce(n <= remaining, "File is truncated");
        auto result = data[position .. position + n];
        position += n;
        return result;
    }

    T get(T)() {
        ubyte[T.sizeof] raw = take(T.sizeof);
        return littleEndianToNative!T(raw);
    }

    /// u32 Länge plus UTF-8, als gültiger Text geprüft.
    string text() {
        auto s = cast(string) take(get!uint);
        validate(s);
        return s;
    }
}

unittest {
    import std.exception : assertThrown;
    import std.file : exists, read, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, "hdb-binary-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dir))
            rmdirRecurse(dir);

    // Jeder Spaltentyp übersteht Schreiben und Lesen bitgenau
    auto defs = [ColumnDef("id", ColumnType.integer), ColumnDef("d", ColumnType.decimal), ColumnDef("s", ColumnType.text),
        ColumnDef("b", ColumnType.boolean), ColumnDef("x", ColumnType.exact), ColumnDef("blob", ColumnType.blob),
        ColumnDef("day", ColumnType.date), ColumnDef("small", ColumnType.int16), ColumnDef("f", ColumnType.single),
        ColumnDef("g", ColumnType.guid)];
    auto t = new ColumnTable("All", defs, TableStorage.binary);
    t.insert([Value(long.min), Value(0.1 + 0.2), Value("tab\tnew\nline ü \\N"), Value(true),
        valueFromInput(ColumnType.exact, "12345678901234567890.123456789"), valueFromInput(ColumnType.blob, "00ff"),
        valueFromInput(ColumnType.date, "2026-11-08"), Value(-32768L), valueFromInput(ColumnType.single, "1.5"),
        valueFromInput(ColumnType.guid, "01234567-89ab-cdef-0123-456789abcdef")]);
    t.insert([Value(long.max), nullValue, Value(""), Value(false), nullValue, nullValue, nullValue, nullValue,
        nullValue, nullValue]);

    auto repo = new BinaryTableRepository(dir);
    repo.save(t);
    repo.flush("All");
    auto path = buildPath(dir, "all.bin");
    assert(exists(path));

    auto loaded = new BinaryTableRepository(dir).get("all");
    assert(loaded.name == "All" && loaded.storage == TableStorage.binary && loaded.defs == defs);
    auto rows = loaded.liveRows();
    assert(rows.length == 2);
    foreach (c; 0 .. defs.length) {
        assert(loaded.value(c, rows[0]) == t.value(c, t.liveRows()[0]), defs[c].name);
        assert(loaded.value(c, rows[1]) == t.value(c, t.liveRows()[1]), defs[c].name);
    }
    assert(loaded.value(1, rows[0]).get!double == 0.1 + 0.2); // keine Rundung über Text

    // Leere Tabelle
    repo.save(new ColumnTable("empty", [ColumnDef("a", ColumnType.integer)], TableStorage.binary));
    repo.flush("empty");
    assert(new BinaryTableRepository(dir).get("empty").liveRows().length == 0);
    repo.remove("empty");
    repo.flush("empty");
    assert(!exists(buildPath(dir, "empty.bin")));

    // Jede Beschädigung bricht das Laden ab, ohne Absturz
    auto good = readBytes(path);
    auto bad = good.dup;
    bad[20] ^= 1;
    write(path, bad);
    assertThrown(new BinaryTableRepository(dir));
    write(path, good[0 .. $ - 1]);
    assertThrown(new BinaryTableRepository(dir));
    write(path, good[0 .. 10]);
    assertThrown(new BinaryTableRepository(dir));
    write(path, "");
    assertThrown(new BinaryTableRepository(dir));

    // Gültige Prüfsumme, aber unsinniger Inhalt: wird trotzdem abgelehnt
    ubyte[] forge(void delegate(ref LittleEndianWriter) @safe fill) {
        auto w = LittleEndianWriter(appender!(ubyte[]));
        fill(w);
        auto body_ = w.data;
        w.bytes(sha256Of(body_)[]);
        return w.data;
    }

    void header(ref LittleEndianWriter w, string type) {
        w.bytes(cast(const(ubyte)[]) "HDBTBIN\0");
        w.put!ushort(1);
        w.text("all");
        w.put!uint(1);
        w.text("a");
        w.text(type);
    }

    write(path, forge((ref w) { header(w, "INTEGER"); w.put!ulong(1); w.put!ubyte(3); w.text("kein int"); }));
    assertThrown(new BinaryTableRepository(dir)); // Text in einer INTEGER-Spalte
    write(path, forge((ref w) { header(w, "TINYINT"); w.put!ulong(1); w.put!ubyte(1); w.put!long(300); }));
    assertThrown(new BinaryTableRepository(dir)); // außerhalb des Wertebereichs
    write(path, forge((ref w) { header(w, "INTEGER"); w.put!ulong(ulong.max); }));
    assertThrown(new BinaryTableRepository(dir)); // Zeilenzahl größer als die Datei
    write(path, forge((ref w) { header(w, "VARCHAR"); w.put!ulong(1); w.put!ubyte(3); w.put!uint(2); w.bytes([0xff, 0xfe]); }));
    assertThrown(new BinaryTableRepository(dir)); // kein UTF-8
    write(path, forge((ref w) { header(w, "INTEGER"); w.put!ulong(0); w.put!ubyte(0); }));
    assertThrown(new BinaryTableRepository(dir)); // Rest am Ende
    write(path, forge((ref w) { header(w, "INTEGER"); w.put!ulong(0); }));
    assert(new BinaryTableRepository(dir).get("all").liveRows().length == 0); // gültig, nur leer
    write(buildPath(dir, "other.bin"), readBytes(path));
    assertThrown(new BinaryTableRepository(dir)); // Tabelle "all" in other.bin
}
