module uim.hdb.infrastructure.repositories.backups;

import uim.hdb;
import std.algorithm : all, canFind, filter, map, sort;
import std.array : appender, array, join, split;
import std.ascii : isAlphaNum;
import std.conv : octal, to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.digest : LetterCase, toHexString;
import std.digest.sha : sha256Of;
import std.exception : enforce;
import std.file : dirEntries, exists, getSize, mkdirRecurse, readText, remove, rename, setAttributes, SpanMode;
import std.format : format;
import std.math : isFinite;
import std.path : baseName, buildPath, stripExtension;
import std.regex : ctRegex, matchFirst;
import std.stdio : File;
import std.string : indexOf, lastIndexOf, strip;
import std.utf : validate;
import vibe.data.json : Json, parseJsonString;

/// Sicherungen als eine Textdatei (*.hdbbak), Zeile für Zeile JSON:
///   Kopf     {"format":"hdb-backup","version":1,"created":...,"label":...,"tables":n,"rows":m}
///   je Tabelle  {"table":...,"storage":...,"columns":[...],"rows":k}, danach k Zeilen mit je einem Datensatz
///   Abschluss   {"sha256":...} über alle vorherigen Bytes
/// Die Prüfsumme erkennt beschädigte oder abgeschnittene Dateien, beweist aber keine Herkunft: wer eine Datei hochlädt,
/// kann sie neu berechnen. Deshalb werden Inhalt und Typen immer vollständig geprüft.
final class FileBackupStore : IBackupStore {
    private enum extension = ".hdbbak";
    private enum scheduleFile = "schedule.json";
    private string directory;
    private string lastBase;
    private int sequence;

    this(string directory) {
        this.directory = directory;
        if (!exists(directory))
            mkdirRecurse(directory);
    }

    BackupInfo[] list() {
        BackupInfo[] result;
        foreach (entry; dirEntries(directory, "*" ~ extension, SpanMode.shallow)) {
            auto info = BackupInfo(baseName(entry.name));
            info.size = getSize(entry.name);
            info.kind = kindOf(info.name);
            try {
                auto file = File(entry.name, "r");
                auto header = parseHeader(file.readln().strip);
                info.label = header.label;
                info.created = header.created;
                info.tables = header.tables;
                info.rows = header.rows;
            } catch (Exception)
                info.readable = false;
            result ~= info;
        }
        // Neueste zuerst: die Aufbewahrung verlässt sich darauf. Der Name beginnt mit dem Zeitstempel; ohne Endung
        // verglichen, weil sonst "-x.hdbbak" hinter dem neueren "-x-0002.hdbbak" stünde.
        result.sort!((a, b) => stripExtension(a.name) > stripExtension(b.name));
        return result;
    }

    BackupInfo save(string label, TableSnapshot[] tables) {
        auto created = wholeSeconds();
        return write(encode(cleanLabel(label), created.toISOExtString, tables), created.toISOString, cleanLabel(label));
    }

    TableSnapshot[] load(string name) {
        return decode(read(name)).tables;
    }

    string read(string name) {
        auto path = pathOf(name);
        if (!exists(path))
            throw new BackupNotFound("Backup not found: " ~ name);
        return readText(path);
    }

    BackupInfo store(string content) {
        auto decoded = decode(content);
        auto stamp = wholeSeconds().toISOString;
        // Das Präfix hält fremde Dateien aus der Aufbewahrung heraus, auch wenn ihr Label "scheduled" lautet
        auto label = cleanLabel(decoded.header.label);
        return write(content, stamp, label.length ? "uploaded-" ~ label : "uploaded");
    }

    BackupSchedule loadSchedule() {
        BackupSchedule s;
        auto path = buildPath(directory, scheduleFile);
        if (!exists(path))
            return s;
        try {
            auto j = parseJsonString(readText(path));
            BackupSchedule loaded;
            loaded.enabled = j["enabled"].get!bool;
            loaded.intervalHours = j["intervalHours"].get!int;
            loaded.keepScheduled = j["keepScheduled"].get!int;
            loaded.keepSafety = j["keepSafety"].get!int;
            loaded.lastRun = j["lastRun"].get!string;
            SysTime.fromISOExtString(loaded.lastRun.length ? loaded.lastRun : "2000-01-01T00:00:00Z");
            loaded.lastError = j["lastError"].get!string;
            enforce(loaded.intervalHours >= 1 && loaded.keepScheduled >= 1 && loaded.keepSafety >= 1, "invalid values");
            return loaded;
        } catch (Exception) {
            // Sichern soll weiterlaufen: Standardwerte, und die Meldung zeigt, dass Einstellungen verloren sind.
            // Der nächste erfolgreiche Lauf oder ein Speichern im Formular schreibt die Datei neu.
            s.lastError = "The schedule settings were unreadable, the defaults are in use";
            return s;
        }
    }

    void saveSchedule(BackupSchedule s) {
        auto j = Json.emptyObject;
        j["enabled"] = s.enabled;
        j["intervalHours"] = s.intervalHours;
        j["keepScheduled"] = s.keepScheduled;
        j["keepSafety"] = s.keepSafety;
        j["lastRun"] = s.lastRun;
        j["lastError"] = s.lastError;
        auto path = buildPath(directory, scheduleFile);
        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        f.write(j.toPrettyString());
        f.flush();
        f.sync();
        f.close();
        rename(tmp, path);
    }

    void remove(string name) {
        auto path = pathOf(name);
        if (!exists(path))
            throw new BackupNotFound("Backup not found: " ~ name);
        .remove(path);
    }

    /// Der Name kommt aus URLs: er darf nie aus dem Verzeichnis herausführen.
    private string pathOf(string name) {
        if (!isBackupName(name))
            throw new BackupNotFound("Backup not found: " ~ name);
        return buildPath(directory, name);
    }

    private BackupInfo write(string content, string stamp, string label) {
        auto base = stamp.filterStamp ~ (label.length ? "-" ~ label : "");
        // Der Zähler läuft nur vorwärts: ein von der Aufbewahrung frei gewordener Name würde sonst neu vergeben,
        // sortierte als ältester und die neue Sicherung flöge sofort wieder heraus.
        if (base != lastBase) {
            lastBase = base;
            sequence = 0;
        }
        string name;
        do {
            ++sequence;
            name = sequence == 1 ? base ~ extension : format("%s-%04d%s", base, sequence, extension);
        }
        while (exists(buildPath(directory, name)));

        auto path = buildPath(directory, name);
        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        setAttributes(tmp, octal!600); // vor dem Schreiben: die Datei enthält alle Daten der Datenbank
        f.write(content);
        f.flush();
        f.sync();
        f.close();
        rename(tmp, path);

        auto header = parseHeader(content[0 .. content.lastIndexOfFirstLine]);
        return BackupInfo(name, header.label, header.created, content.length, header.tables, header.rows, true, kindOf(name));
    }
}

/// Die Art steht im Dateinamen, den nur der Server vergibt; der Kopf einer Datei könnte von außen kommen.
string kindOf(string name) {
    auto m = matchFirst(name, ctRegex!(`^\d{8}-\d{6}Z-(scheduled|before-restore|uploaded)(-.*)?\.hdbbak$`));
    if (m.empty)
        return "manual";
    if (m[1] == "uploaded")
        return "uploaded";
    // Nur der Server hängt an diese Namen etwas an, und dann eine Zahl
    if (m[2].length && matchFirst(m[2], ctRegex!(`^-\d+$`)).empty)
        return "manual";
    return m[1] == "scheduled" ? "scheduled" : "safety";
}

bool isBackupName(string name) {
    enum extension = ".hdbbak";
    return name.length > extension.length && name.length <= 128 && name[$ - extension.length .. $] == extension
        && !name.canFind("..") && name.all!(c => isAlphaNum(c) || c == '-' || c == '_' || c == '.');
}

private SysTime wholeSeconds() {
    auto time = Clock.currTime(UTC());
    time.fracSecs = typeof(time.fracSecs).zero;
    return time;
}

private size_t lastIndexOfFirstLine(string content) {
    foreach (i, c; content)
        if (c == '\n')
            return i;
    return content.length;
}

private string filterStamp(string stamp) {
    string result;
    foreach (c; stamp)
        if (isAlphaNum(c))
            result ~= c == 'T' ? '-' : c;
    return result;
}

private string cleanLabel(string label) {
    string result;
    foreach (c; label.strip) {
        if (result.length == 40)
            break;
        if (isAlphaNum(c) || c == '-' || c == '_')
            result ~= c;
        else if (c == ' ')
            result ~= '-';
    }
    return result;
}

private struct Header {
    string label, created;
    long tables, rows;
}

private struct Decoded {
    Header header;
    TableSnapshot[] tables;
}

private Header parseHeader(string line) {
    auto j = parseJsonString(line);
    enforce(j["format"].get!string == "hdb-backup", "Not an hdb backup");
    enforce(j["version"].get!long == 1, "Unsupported backup version");
    return Header(j["label"].get!string, j["created"].get!string, j["tables"].get!long, j["rows"].get!long);
}

private string encode(string label, string created, TableSnapshot[] tables) {
    long rows;
    foreach (t; tables)
        rows += t.rows.length;
    auto header = Json.emptyObject;
    header["format"] = "hdb-backup";
    header["version"] = 1;
    header["created"] = created;
    header["label"] = label;
    header["tables"] = cast(long) tables.length;
    header["rows"] = rows;

    auto out_ = appender!string;
    out_ ~= header.toString ~ "\n";
    foreach (t; tables) {
        auto columns = Json.emptyArray;
        foreach (c; t.columns) {
            auto column = Json.emptyObject;
            column["name"] = c.name;
            column["type"] = typeName(c.type);
            columns ~= column;
        }
        auto meta = Json.emptyObject;
        meta["table"] = t.name;
        meta["storage"] = storageName(t.storage);
        meta["columns"] = columns;
        meta["rows"] = cast(long) t.rows.length;
        out_ ~= meta.toString ~ "\n";
        foreach (row; t.rows)
            out_ ~= "[" ~ row.map!(tableValueJson).join(",") ~ "]\n";
    }
    auto body_ = out_[];
    return body_ ~ `{"sha256":"` ~ checksum(body_) ~ `"}` ~ "\n";
}

/// Wie \w im Kern. Der Tabellenname wird bei File- und Json-Tabellen zum Dateinamen.
private bool isSqlName(string name) {
    return !matchFirst(name, ctRegex!(`^\w+$`)).empty;
}

private string checksum(string content) {
    return sha256Of(content).toHexString!(LetterCase.lower).idup;
}

/// Liest eine Sicherung vollständig; alles, was nicht passt, ist ein Fehler.
private Decoded decode(string content) {
    try {
        validate(content);
        enforce(content.length > 1 && content[$ - 1] == '\n', "file is truncated");
        immutable lastLine = content[0 .. $ - 1].lastIndexOf('\n');
        enforce(lastLine > 0, "file is truncated");
        auto body_ = content[0 .. lastLine + 1];
        enforce(parseJsonString(content[lastLine + 1 .. $])["sha256"].get!string == checksum(body_), "checksum does not match");

        auto lines = body_.split("\n");
        auto header = parseHeader(lines[0]);
        TableSnapshot[] tables;
        long rows;
        size_t i = 1;
        while (i < lines.length - 1) {
            auto meta = parseJsonString(lines[i++]);
            TableSnapshot t;
            t.name = meta["table"].get!string;
            enforce(isSqlName(t.name), "invalid table name");
            t.storage = parseStorage(meta["storage"].get!string);
            foreach (c; meta["columns"]) {
                t.columns ~= ColumnDef(c["name"].get!string, parseTypeName(c["type"].get!string));
                enforce(isSqlName(t.columns[$ - 1].name), "invalid column name");
            }
            immutable count = meta["rows"].get!long;
            enforce(count >= 0 && i + count <= lines.length - 1, "row count does not match");
            foreach (n; 0 .. count) {
                auto line = parseJsonString(lines[i++]);
                enforce(line.length == t.columns.length, "row has the wrong number of values");
                Value[] row;
                foreach (c, d; t.columns) {
                    auto value = tableValueFromJson(d.type, line[c]);
                    if (auto number = value.peek!double)
                        enforce(isFinite(*number), "value is not a finite number");
                    row ~= value;
                }
                t.rows ~= row;
            }
            rows += count;
            tables ~= t;
        }
        enforce(tables.length == header.tables && rows == header.rows, "header does not match the content");
        return Decoded(header, tables);
    } catch (Exception e)
        throw new Exception("Invalid backup: " ~ e.msg);
}

unittest {
    import uim.hdb;
    import std.exception : assertThrown, collectException;
    import std.file : getAttributes, rmdirRecurse, tempDir, write;
    import std.string : replace;
    import std.uuid : randomUUID;

    static class MemLog : IStatementLog {
        string[] lines;
        void append(string st) {
            lines ~= st;
        }

        void appendAll(string[] a) {
            lines ~= a;
        }

        string[] readAll() {
            return lines.map!"a".array;
        }

        void replaceAll(string[] items) {
            lines = items.map!"a".array;
        }
    }

    auto root = buildPath(tempDir, "hdb-backup-" ~ randomUUID().toString);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);
    auto log = new MemLog;
    SqlService start() {
        auto s = new SqlService(new RoutingTableRepository(new MemoryTableRepository,
                new FileTableRepository(buildPath(root, "file")), new JsonTableRepository(buildPath(root, "json"))), log);
        s.recover();
        return s;
    }

    Principal who = Principal("a", HdbRole.admin, true);
    auto sql = start();
    auto store = new FileBackupStore(buildPath(root, "backups"));
    auto backups = new BackupService(sql, store, () => who);

    enum nasty = "tab\there\nline 'q' \"d\" \\ ümläut €";
    foreach (storage; ["MEMORY", "FILE", "JSON"]) {
        auto t = "t_" ~ storage;
        sql.execute("CREATE TABLE " ~ t ~ " (id INTEGER, n VARCHAR, w DECIMAL) USING " ~ storage);
        sql.execute("INSERT INTO " ~ t ~ " VALUES (1, " ~ toSqlLiteral(Value(nasty)) ~ ", 123456789012345678.0)");
        sql.execute("INSERT INTO " ~ t ~ " VALUES (2, NULL, NULL)");
        sql.execute("INSERT INTO " ~ t ~ " VALUES (3, 'weg', 1)");
        sql.execute("DELETE FROM " ~ t ~ " WHERE id = 3");
    }

    auto info = backups.create("Nightly run #1 / ../x");
    assert(info.tables == 3 && info.rows == 6 && info.label == "Nightly-run-1--x", info.label);
    assert(isBackupName(info.name));
    assert((getAttributes(buildPath(root, "backups", info.name)) & octal!777) == octal!600);
    assert(backups.list().length == 1 && backups.list()[0].rows == 6);
    assert(backups.download(info.name).indexOf("passwordHash") < 0);

    void verifyOriginal(SqlService s) {
        assert(s.listTables().length == 3);
        foreach (storage; ["MEMORY", "FILE", "JSON"]) {
            auto r = s.execute("SELECT id, n, w FROM t_" ~ storage ~ " ORDER BY id").rows;
            assert(r.length == 2 && r[0][1] == Value(nasty) && r[0][2] == Value(123456789012345678.0), storage);
            assert(isNull(r[1][1]) && isNull(r[1][2]), storage);
        }
        assert(s.stats().map!(t => t.storage).array.sort.array
            == [TableStorage.memory, TableStorage.file, TableStorage.json]);
    }

    // Änderungen nach der Sicherung verschwinden, auch neue Tabellen und ihre Dateien
    sql.execute("DROP TABLE t_FILE");
    sql.execute("DELETE FROM t_JSON");
    sql.execute("UPDATE t_MEMORY SET n = 'x'");
    sql.execute("CREATE TABLE neu (a INTEGER) USING FILE");
    sql.execute("CREATE TABLE neu2 (a INTEGER)");
    auto safety = backups.restore(info.name);
    assert(safety.label == "before-restore" && safety.tables == 4);
    verifyOriginal(sql);
    assert(!exists(buildPath(root, "file", "neu.tbl")));

    // Der Stand überlebt den Neustart samt Merge, und die Sicherheitskopie macht es rückgängig
    sql = start();
    sql.mergeDelta();
    verifyOriginal(sql);
    backups = new BackupService(sql, store, () => who);
    backups.restore(safety.name);
    assert(sql.listTables().length == 4 && sql.execute("SELECT a FROM neu").rows.length == 0);
    backups.restore(info.name);

    // Herunterladen und wieder hochladen ergibt dieselbe Sicherung
    auto content = backups.download(info.name);
    auto uploaded = backups.upload(content);
    assert(uploaded.name != info.name && backups.download(uploaded.name) == content);

    // Beschädigte Dateien werden erkannt, bevor irgendetwas geändert wird
    string[] invalid = [
        "", "kein Backup", "{}\n", content[0 .. $ / 2], content ~ "x", content.replace("weg", "WEG") ~ "\n",
        content.replace("t_FILE", "t_FILx"), cast(string)[0xff, 0xfe, 0x0a]
    ];
    foreach (bad; invalid)
        assertThrown(backups.upload(bad));

    // Eine neu berechnete Prüfsumme hilft nicht: Inhalte werden trotzdem geprüft
    string forged(string table, string columns, string rows, long count, string storage = "FILE") {
        auto body_ = `{"format":"hdb-backup","version":1,"created":"x","label":"","tables":1,"rows":` ~ count.to!string ~ "}\n"
            ~ `{"table":"` ~ table ~ `","storage":"` ~ storage ~ `","columns":` ~ columns ~ `,"rows":` ~ count.to!string ~ "}\n" ~ rows;
        return body_ ~ `{"sha256":"` ~ checksum(body_) ~ `"}` ~ "\n";
    }

    enum one = `[{"name":"a","type":"INTEGER"}]`;
    assertThrown(backups.upload(forged("../../evil", one, "[1]\n", 1)));
    assertThrown(backups.upload(forged("a/b", one, "", 0)));
    // zweite Linie: auch der Kern nimmt so einen Namen nicht an
    assertThrown(sql.restore([TableSnapshot("../../evil", TableStorage.file, [ColumnDef("a", ColumnType.integer)])]));
    assertThrown(sql.restore([TableSnapshot("t", TableStorage.memory, [ColumnDef("a b", ColumnType.integer)])]));
    assertThrown(sql.restore([TableSnapshot("t", TableStorage.memory), TableSnapshot("T", TableStorage.memory)]));
    assert(!exists(buildPath(root, "evil.tbl")) && !exists(buildPath(root, "evil")));
    verifyOriginal(sql);
    assertThrown(backups.upload(forged("t", one, `["x"]` ~ "\n", 1)));
    assertThrown(backups.upload(forged("t", one, "[1,2]\n", 1)));
    assertThrown(backups.upload(forged("t", `[{"name":"a","type":"RAW"}]`, "", 0)));
    assertThrown(backups.upload(forged("t", `[{"name":"a","type":"LINK"}]`, `["javascript:alert(1)"]` ~ "\n", 1)));
    assertThrown(backups.upload(forged("t", `[{"name":"a","type":"BLOB"}]`, `["xyz"]` ~ "\n", 1)));
    assertThrown(backups.upload(forged("t", `[{"name":"a","type":"DECIMAL"}]`, "[1e999]\n", 1)));
    assertThrown(backups.upload(forged("t", one, "", 0, "DISK")));
    assertThrown(backups.upload(forged("t", `[{"name":"a b","type":"INTEGER"}]`, "", 0)));
    verifyOriginal(sql);

    // Namen aus URLs führen nicht aus dem Verzeichnis heraus
    foreach (bad; ["../x.hdbbak", "..hdbbak", "a/b.hdbbak", "x", "", "a..b.hdbbak", "/etc/passwd"]) {
        assert(!isBackupName(bad), bad);
        assertThrown!BackupNotFound(backups.remove(bad));
        assertThrown!BackupNotFound(backups.download(bad));
    }
    assertThrown!BackupNotFound(backups.restore("missing.hdbbak"));

    // Nicht bei offener Transaktion
    auto tx = sql.execute("BEGIN").transaction;
    assertThrown(backups.create("x"));
    assertThrown(backups.restore(info.name));
    sql.executeIn(tx, "ROLLBACK");

    // Nur für Administratoren
    who = Principal("e", HdbRole.editor, true);
    assertThrown!AccessDenied(backups.list());
    assertThrown!AccessDenied(backups.create("x"));
    assertThrown!AccessDenied(backups.restore(info.name));
    assertThrown!AccessDenied(backups.download(info.name));
    assertThrown!AccessDenied(backups.upload(content));
    assertThrown!AccessDenied(backups.remove(info.name));
    who = Principal.init;
    assertThrown!AuthenticationRequired(backups.list());
    who = Principal("a", HdbRole.admin, true);

    backups.remove(info.name);
    assertThrown!BackupNotFound(backups.remove(info.name));
}

/// Scheitert das Ersetzen mittendrin, kommt der alte Stand zurück.
unittest {
    import uim.hdb;
    import std.exception : collectException;

    static class Database : IDatabaseSnapshots {
        TableSnapshot[] state;
        int failures;
        TableSnapshot[] snapshot() {
            return state;
        }

        void restore(TableSnapshot[] tables) {
            if (failures-- > 0)
                throw new Exception("disk full");
            state = tables;
        }
    }

    static class Store : IBackupStore {
        BackupInfo[] list() {
            return null;
        }

        BackupInfo save(string label, TableSnapshot[] tables) {
            return BackupInfo("safety.hdbbak", label);
        }

        TableSnapshot[] load(string name) {
            return [TableSnapshot("neu")];
        }

        string read(string name) {
            return "";
        }

        BackupInfo store(string content) {
            return BackupInfo.init;
        }

        void remove(string name) {
        }

        BackupSchedule loadSchedule() {
            return BackupSchedule.init;
        }

        void saveSchedule(BackupSchedule schedule) {
        }
    }

    auto database = new Database;
    database.state = [TableSnapshot("alt")];
    auto backups = new BackupService(database, new Store, () => Principal("a", HdbRole.admin, true));

    database.failures = 1;
    auto e = collectException(backups.restore("x.hdbbak"));
    assert(e !is null && e.msg == "Restore failed, the previous state was put back: disk full");
    assert(database.state[0].name == "alt");

    database.failures = 2;
    e = collectException(backups.restore("x.hdbbak"));
    assert(e !is null && e.msg.indexOf("safety.hdbbak") > 0);

    database.failures = 0;
    assert(backups.restore("x.hdbbak").name == "safety.hdbbak" && database.state[0].name == "neu");
}

/// Zeitplan und Aufbewahrung.
unittest {
    import uim.hdb;
    import core.time : hours, minutes, seconds;
    import std.algorithm : reverse;
    import std.exception : assertThrown;
    import std.file : rmdirRecurse, tempDir;
    static import std.file;
    import std.uuid : randomUUID;

    static class Database : IDatabaseSnapshots {
        bool busy, empty;
        TableSnapshot[] snapshot() {
            enforce(!busy, "Datenbank gesperrt");
            return empty ? null : [TableSnapshot("t", TableStorage.memory, [ColumnDef("a", ColumnType.integer)])];
        }

        void restore(TableSnapshot[] tables) {
        }
    }

    auto root = buildPath(tempDir, "hdb-schedule-" ~ randomUUID().toString);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);
    auto store = new FileBackupStore(root);
    auto database = new Database;
    auto clock = SysTime.fromISOExtString("2030-01-01T00:00:00Z");
    Principal who = Principal("a", HdbRole.admin, true);
    auto backups = new BackupService(database, store, () => who, () => clock);
    size_t count(string kind) {
        return store.list().filter!(b => b.kind == kind).array.length;
    }

    // Erster Lauf sofort, danach erst nach Ablauf der Frist
    assert(backups.schedule().enabled && backups.schedule().intervalHours == 24 && backups.schedule().nextRun == "");
    database.empty = true;
    assert(backups.tick() is null && count("scheduled") == 0); // leere Datenbank: nichts anlegen
    database.empty = false;
    assert(backups.tick() is null && count("scheduled") == 1);
    assert(backups.schedule().lastRun == "2030-01-01T00:00:00Z" && backups.schedule().nextRun == "2030-01-02T00:00:00Z");
    clock += 23.hours;
    backups.tick();
    assert(count("scheduled") == 1);
    clock += 1.hours;
    backups.tick();
    assert(count("scheduled") == 2);

    // Der Zeitplan überlebt einen Neustart: die Frist beginnt nicht von vorn
    auto restarted = new BackupService(database, new FileBackupStore(root), () => who, () => clock);
    restarted.tick();
    assert(count("scheduled") == 2);

    // Aufbewahrung behält die neuesten, eigene und hochgeladene Sicherungen bleiben
    auto manual = backups.create("my label");
    auto content = store.read(store.list().filter!(b => b.kind == "scheduled").array[0].name);
    auto uploaded = backups.upload(content); // Kopf sagt "scheduled"
    assert(uploaded.kind == "uploaded" && manual.kind == "manual");
    backups.updateSchedule(true, 1, 3, 2);
    string[] names;
    foreach (i; 0 .. 5) {
        clock += 1.hours;
        clock += 1.seconds;
        backups.tick();
    }
    assert(count("scheduled") == 3);
    assert(exists(buildPath(root, manual.name)) && exists(buildPath(root, uploaded.name)));

    // Neueste zuerst, auch innerhalb derselben Sekunde: sonst löschte die Aufbewahrung gerade die neue Sicherung
    string[] made;
    foreach (i; 0 .. 12)
        made ~= store.save("order", database.snapshot()).name;
    string[] listed;
    foreach (b; store.list())
        if (b.label == "order")
            listed ~= b.name;
    made.reverse();
    assert(listed == made);
    foreach (name; made)
        store.remove(name);

    // Reservierte Labels, Schreibweise egal
    foreach (label; ["scheduled", "Scheduled ", "before-restore", "Before Restore"])
        assertThrown(backups.create(label));

    // Sicherheitskopien werden begrenzt, die neue bleibt
    foreach (i; 0 .. 4) {
        clock += 1.seconds;
        auto safety = backups.restore(manual.name);
        assert(exists(buildPath(root, safety.name)));
    }
    assert(count("safety") == 2 && exists(buildPath(root, manual.name)));

    // Weniger aufbewahren wirkt sofort
    backups.updateSchedule(true, 1, 1, 1);
    assert(count("scheduled") == 1 && count("safety") == 1);

    // Fehler: nichts wird gelöscht, die Meldung bleibt sichtbar, Wiederholung erst nach der Wartezeit
    clock += 2.hours;
    database.busy = true;
    assert(backups.tick() == "Datenbank gesperrt");
    assert(backups.schedule().lastError == "Datenbank gesperrt" && count("scheduled") == 1);
    database.busy = false;
    clock += 1.minutes;
    assert(backups.tick() is null && backups.schedule().lastError.length); // noch in der Wartezeit
    assert(count("scheduled") == 1);
    clock += 5.minutes;
    assert(backups.tick() is null && backups.schedule().lastError == "");
    assert(count("scheduled") == 1 && store.list().filter!(b => b.kind == "scheduled").array[0].created.length);

    // Ausgeschaltet läuft nichts
    backups.updateSchedule(false, 1, 1, 1);
    clock += 48.hours;
    auto before = store.list().length;
    backups.tick();
    assert(store.list().length == before && backups.schedule().nextRun == "");

    // Beschädigte Einstellungen stoppen die Sicherung nicht und lassen sich reparieren
    foreach (broken; ["{broken", `{"enabled":true}`, `{"enabled":true,"intervalHours":0,"keepScheduled":1,"keepSafety":1,"lastRun":"","lastError":""}`,
            `{"enabled":true,"intervalHours":1,"keepScheduled":1,"keepSafety":1,"lastRun":"gestern","lastError":""}`]) {
        std.file.write(buildPath(root, "schedule.json"), broken);
        auto loaded = backups.schedule();
        assert(loaded.enabled && loaded.intervalHours == 24 && loaded.lastError.length);
    }
    clock += 1.hours;
    auto scheduledBefore = count("scheduled");
    assert(backups.tick() is null && backups.schedule().lastError == "" && backups.schedule().lastRun.length);
    backups.updateSchedule(false, 1, 1, 1);

    // Grenzen und Rechte
    assertThrown(backups.updateSchedule(true, 0, 1, 1));
    assertThrown(backups.updateSchedule(true, 1, 0, 1));
    assertThrown(backups.updateSchedule(true, 1, 1, 0));
    who = Principal("e", HdbRole.editor, true);
    assertThrown!AccessDenied(backups.schedule());
    assertThrown!AccessDenied(backups.updateSchedule(true, 1, 1, 1));

    assert(kindOf("20300101-000000Z-scheduled.hdbbak") == "scheduled");
    assert(kindOf("20300101-000000Z-scheduled-0002.hdbbak") == "scheduled");
    assert(kindOf("20300101-000000Z-before-restore.hdbbak") == "safety");
    assert(kindOf("20300101-000000Z-uploaded-scheduled.hdbbak") == "uploaded");
    assert(kindOf("20300101-000000Z-scheduled-work.hdbbak") == "manual");
    assert(kindOf("20300101-000000Z-my-backup.hdbbak") == "manual");
    assert(kindOf("anything.hdbbak") == "manual");
}

