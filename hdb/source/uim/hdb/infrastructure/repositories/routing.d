module uim.hdb.infrastructure.repositories.routing;

import uim.hdb.application.ports;
import uim.hdb.domain.table;
import uim.hdb.domain.types.tablestorage : TableStorage;
import std.algorithm : sort;
import std.array : array;
import std.exception : enforce;

/// Verteilt Tabellen nach ColumnTable.storage auf die Repositories. Der Kern sieht nur dieses eine Repository,
/// Tabellennamen sind über alle Speicher hinweg eindeutig.
final class RoutingTableRepository : ITableRepository, IDurableTableRepository {
    private ITableRepository[TableStorage] backends;

    this(ITableRepository memory, ITableRepository file, ITableRepository json) {
        backends = [TableStorage.memory: memory, TableStorage.file: file, TableStorage.json: json];
        bool[string] seen;
        foreach (b; backends)
            foreach (name; b.list()) {
                enforce((name in seen) is null, "Tabelle liegt in mehreren Speichern: " ~ name);
                seen[name] = true;
            }
    }

    bool exists(string name) {
        foreach (b; backends)
            if (b.exists(name))
                return true;
        return false;
    }

    ColumnTable get(string name) {
        foreach (b; backends)
            if (b.exists(name))
                return b.get(name);
        throw new Exception("Tabelle nicht gefunden: " ~ name);
    }

    void save(ColumnTable table) {
        backends[table.storage].save(table);
    }

    void remove(string name) {
        foreach (b; backends)
            b.remove(name);
    }

    string[] list() {
        string[] names;
        foreach (b; backends)
            names ~= b.list();
        return names.sort.array;
    }

    /// Fragt alle dauerhaften Speicher: ist die Tabelle umgezogen, verschwindet so ihre alte Datei.
    void flush(string name) {
        foreach (b; backends)
            if (auto durable = cast(IDurableTableRepository) b)
                durable.flush(name);
    }
}

unittest {
    import uim.hdb.application.sql_service : SqlService;
    import uim.hdb.domain.value;
    import uim.hdb.infrastructure.repositories.files : FileTableRepository;
    import uim.hdb.infrastructure.repositories.json : JsonTableRepository;
    import uim.hdb.infrastructure.repositories.memory : MemoryTableRepository;
    import std.conv : to;
    import std.exception : assertThrown;
    import std.file : exists, deleteFile = remove, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.string : indexOf;
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
            return lines.dup;
        }

        void replaceAll(string[] a) {
            lines = a.dup;
        }
    }

    auto root = buildPath(tempDir, "hdb-repos-" ~ randomUUID().toString);
    scope (exit)
        if (exists(root))
            rmdirRecurse(root);
    auto fileDir = buildPath(root, "file"), jsonDir = buildPath(root, "json");
    auto log = new MemLog;

    // Ein "Neustart": alles neu aufbauen, nur Dateien und Log bleiben
    SqlService start() {
        auto s = new SqlService(new RoutingTableRepository(new MemoryTableRepository,
                new FileTableRepository(fileDir), new JsonTableRepository(jsonDir)), log);
        s.recover();
        return s;
    }

    auto s = start();
    enum nasty = "tab\there\nline\rcr \\N back\\slash 'q' \"d\" ümläut €";
    enum big = "123456789012345678"; // verliert mit 16 Stellen Genauigkeit

    foreach (storage; ["MEMORY", "FILE", "JSON"]) {
        auto t = "t_" ~ storage;
        s.execute("CREATE TABLE " ~ t ~ " (id INTEGER, n VARCHAR, w DECIMAL) USING " ~ storage);
        s.execute("INSERT INTO " ~ t ~ " VALUES (1, " ~ toSqlLiteral(Value(nasty)) ~ ", 1234567.891)");
        s.execute("INSERT INTO " ~ t ~ " VALUES (2, NULL, NULL)");
        s.execute("INSERT INTO " ~ t ~ " VALUES (3, '', " ~ big ~ ".0)");
        s.execute("INSERT INTO " ~ t ~ " VALUES (9223372036854775807, '\\N', 2)");
        s.execute("INSERT INTO " ~ t ~ " VALUES (5, 'weg', 1)");
        s.execute("DELETE FROM " ~ t ~ " WHERE id = 5");
        s.execute("INSERT INTO " ~ t ~ " VALUES (6, 'x', 7)");
    }
    assert(exists(buildPath(fileDir, "t_file.tbl")) && exists(buildPath(jsonDir, "t_json.json")));
    assert(!exists(buildPath(fileDir, "t_memory.tbl")));

    // Nur Speicher-Tabellen stehen im Log: sonst würde jede Zeile doppelt geladen
    foreach (line; log.lines) {
        assert(line.indexOf("t_FILE") < 0 && line.indexOf("t_JSON") < 0);
    }

    foreach (round; 0 .. 2) {
        s = start();
        s.mergeDelta(); // wie beim echten Start: der Merge darf keinen Wert verändern
        foreach (storage; ["MEMORY", "FILE", "JSON"]) {
            auto t = "t_" ~ storage;
            auto r = s.execute("SELECT id, n, w FROM " ~ t ~ " ORDER BY id").rows;
            assert(r.length == 5, storage ~ " " ~ r.length.to!string);
            assert(r[0][1] == Value(nasty) && r[0][2] == Value(1234567.891), storage);
            assert(isNull(r[1][1]) && isNull(r[1][2]), storage);
            assert(r[2][1] == Value("") && r[2][2] == Value(big.to!double), storage);
            assert(r[4][0] == Value(long.max) && r[4][1] == Value("\\N"), storage);
            assert(r[3][2] == Value(7.0), storage);
        }
        s.checkpoint(); // ändert an den Dateitabellen nichts und schreibt sie nicht ins Log
        foreach (line; log.lines)
            assert(line.indexOf("t_FILE") < 0 && line.indexOf("t_JSON") < 0);
    }
    assert(s.stats().length == 3);

    // ROLLBACK erreicht die Datei nie, COMMIT schreibt sie
    auto path = buildPath(fileDir, "t_file.tbl");
    auto before = readText(path);
    auto tx = s.execute("BEGIN").transaction;
    s.executeIn(tx, "DELETE FROM t_FILE");
    s.executeIn(tx, "CREATE TABLE neu (a INTEGER) USING JSON");
    assert(readText(path) == before && !exists(buildPath(jsonDir, "neu.json")));
    s.executeIn(tx, "ROLLBACK");
    assert(readText(path) == before && s.execute("SELECT id FROM t_FILE").rows.length == 5);
    assertThrown(s.execute("SELECT a FROM neu")); // in der Transaktion angelegt, also wieder weg

    tx = s.execute("BEGIN").transaction;
    s.executeIn(tx, "DELETE FROM t_FILE WHERE id = 1");
    s.executeIn(tx, "INSERT INTO t_MEMORY VALUES (7, 'tx', 1)");
    assert(readText(path) == before);
    assert(s.executeIn(tx, "COMMIT").message.indexOf("(2 ") > 0);
    assert(readText(path) != before);
    s = start();
    assert(s.execute("SELECT id FROM t_FILE").rows.length == 4);
    assert(s.execute("SELECT id FROM t_MEMORY").rows.length == 6);

    // Speicher-Tabelle löschen, gleichnamig als Datei neu anlegen: die Log-Historie darf nicht stören
    s.execute("CREATE TABLE wechsel (a INTEGER)");
    s.execute("INSERT INTO wechsel VALUES (1)");
    s.execute("DROP TABLE wechsel");
    s.execute("CREATE TABLE wechsel (a INTEGER) USING FILE");
    s.execute("INSERT INTO wechsel VALUES (2)");
    s = start();
    assert(s.execute("SELECT a FROM wechsel").rows == [[Value(2L)]]);

    // und umgekehrt: DROP entfernt die Datei
    s.execute("DROP TABLE wechsel");
    assert(!exists(buildPath(fileDir, "wechsel.tbl")));
    s.execute("CREATE TABLE wechsel (a INTEGER) USING JSON");
    s.execute("DROP TABLE wechsel");
    s.execute("CREATE TABLE wechsel (a INTEGER)");
    s.execute("INSERT INTO wechsel VALUES (3)");
    s = start();
    assert(s.execute("SELECT a FROM wechsel").rows == [[Value(3L)]]);

    // Namen sind speicherübergreifend eindeutig, unbekannte Speicher werden abgelehnt
    assertThrown(s.execute("CREATE TABLE t_FILE (a INTEGER) USING JSON"));
    assertThrown(s.execute("CREATE TABLE x (a INTEGER) USING DISK"));
    new SqlService(new MemoryTableRepository).execute("CREATE TABLE a (b INTEGER) USING MEMORY");
    assertThrown(new SqlService(new MemoryTableRepository).execute("CREATE TABLE a (b INTEGER) USING FILE"));

    // Einzelne Textspalte mit Leerstring überlebt das Zeilenformat
    s.execute("CREATE TABLE eins (t VARCHAR) USING FILE");
    s.execute("INSERT INTO eins VALUES ('')");
    s.execute("INSERT INTO eins VALUES ('a')");
    s = start();
    assert(s.execute("SELECT t FROM eins").rows.length == 2);

    // Beschädigte oder doppelte Dateien brechen den Start ab
    write(buildPath(fileDir, "kaputt.tbl"), "kein Format");
    assertThrown(start());
    deleteFile(buildPath(fileDir, "kaputt.tbl"));
    write(buildPath(jsonDir, "kaputt.json"), "{");
    assertThrown(start());
    deleteFile(buildPath(jsonDir, "kaputt.json"));
    write(buildPath(jsonDir, "t_file.json"), `{"name": "t_FILE", "columns": [{"name": "a", "type": "INTEGER"}], "rows": []}`);
    assertThrown(start());
    deleteFile(buildPath(jsonDir, "t_file.json"));
    start();
}
