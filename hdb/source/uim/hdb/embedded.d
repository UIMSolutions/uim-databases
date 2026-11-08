/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Betriebsart „eingebettet“: die Datenbank läuft im Prozess der Anwendung, ohne Netz, Anmeldung und Rollen.
/// Wer die API aufruft, hat alle Rechte. Es läuft kein Server und keine Ereignisschleife; der Delta-Merge nutzt
/// wie im Server einen eigenen Thread.
///
/// ---
/// auto db = HdbDatabase.open("data/mydb");
/// scope (exit) db.close();
/// db.execute("CREATE TABLE t (k INTEGER, name VARCHAR) USING FILE");
/// auto tx = db.begin();
/// tx.execute("INSERT INTO t VALUES (1, 'a')");
/// tx.commit();
/// foreach (row; db.execute("SELECT k, name FROM t").rows) ...
/// ---
///
/// Das Verzeichnis hat denselben Aufbau wie ein Mandant im Server (tables/, hdb.log, backups/). Es lässt sich
/// deshalb als Mandant in einen Server übernehmen (nach TENANTS_DIR/<mandant> kopieren und den Mandanten anlegen)
/// und umgekehrt. Ein Verzeichnis darf immer nur ein Prozess gleichzeitig öffnen.
module uim.hdb.embedded;

import uim.hdb;
import std.exception : enforce;

@safe:

/// Eine eingebettete Datenbank.
final class HdbDatabase {
    private SqlService core;
    private BackupService backupService; // null: ohne Ablage für Sicherungen
    private bool closed;

    private this(ITableRepository tables, IStatementLog log, IBackupStore backups) {
        core = new SqlService(tables, log);
        core.recover();
        core.mergeDelta();
        if (backups !is null) // Der Aufrufer ist der Besitzer: er hat alle Rechte
            backupService = new BackupService(core, backups, () => Principal("embedded", HdbRole.admin, true, defaultTenant));
    }

    /// Öffnet die Datenbank im Verzeichnis oder legt sie dort an; der Stand wird aus dem Protokoll wiederhergestellt.
    static HdbDatabase open(string directory) {
        enforce(directory.length, "A directory is required; use HdbDatabase.inMemory() for a volatile database");
        auto parts = storageIn(directory);
        return new HdbDatabase(parts.tables, parts.log, parts.backups);
    }

    /// Flüchtige Datenbank: alles liegt im Speicher und ist mit dem Prozess weg. Tabellen mit USING FILE, JSON,
    /// BINARY oder BSON gibt es hier nicht. Sicherungen nur, wenn `backupDirectory` angegeben ist.
    static HdbDatabase inMemory(string backupDirectory = "") {
        return new HdbDatabase(new MemoryTableRepository, null,
            backupDirectory.length ? new FileBackupStore(backupDirectory) : null);
    }

    /// Führt eine Anweisung außerhalb einer Transaktion aus. Fehler werfen eine Exception.
    QueryResult execute(string sql) {
        return open_().execute(sql);
    }

    /// Führt eine Anweisung in der Transaktion `transaction` aus (siehe `begin`).
    QueryResult executeIn(string transaction, string sql) {
        return open_().executeIn(transaction, sql);
    }

    /// Beginnt eine Transaktion. Solange sie offen ist, sperrt sie die Datenbank für andere Schreibzugriffe.
    Transaction begin() {
        auto r = open_().execute("BEGIN");
        return Transaction(this, r.transaction);
    }

    string[] tables() {
        return open_().listTables();
    }

    TableStats[] stats() {
        return open_().stats();
    }

    /// Schreibt alle Tabellen in ihre Ablage und kürzt das Protokoll.
    void checkpoint() {
        open_().checkpoint();
    }

    /// Führt den Delta-Merge sofort aus (der Server stößt ihn sonst selbst an).
    void mergeDelta() {
        open_().mergeDelta();
    }

    MergeStatus mergeStatus() {
        return open_().mergeStatus();
    }

    BackupInfo backup(string label = "") {
        return backups_().create(label);
    }

    BackupInfo[] backups() {
        return backups_().list();
    }

    /// Ersetzt alle Tabellen durch die Sicherung. Vorher entsteht eine Sicherheitskopie "before-restore".
    BackupInfo restore(string name) {
        return backups_().restore(name);
    }

    void removeBackup(string name) {
        backups_().remove(name);
    }

    /// Schreibt den Stand weg. Danach ist das Objekt nicht mehr benutzbar; mehrfaches Schließen ändert nichts.
    void close() {
        if (closed)
            return;
        core.checkpoint();
        closed = true;
    }

    private SqlService open_() {
        enforce(!closed, "The database is closed");
        return core;
    }

    private BackupService backups_() {
        open_();
        enforce(backupService !is null, "This database has no backup directory");
        return backupService;
    }
}

/// Eine offene Transaktion. Ohne commit wird sie beim Verlassen des Gültigkeitsbereichs nicht automatisch
/// zurückgerollt: dafür `scope (failure) tx.rollback();` verwenden.
struct Transaction {
    private HdbDatabase db;
    private string id;
    private bool done;

    string transactionId() const {
        return id;
    }

    QueryResult execute(string sql) {
        enforce(!done, "The transaction has ended");
        return db.executeIn(id, sql);
    }

    void commit() {
        finish("COMMIT");
    }

    void rollback() {
        if (!done)
            finish("ROLLBACK");
    }

    private void finish(string statement) {
        enforce(!done, "The transaction has ended");
        db.executeIn(id, statement);
        done = true;
    }
}

unittest {
    import uim.hdb.domain.value : get;
    import std.exception : assertThrown;
    import std.file : exists, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, "hdb-embedded-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dir))
            rmdirRecurse(dir);

    auto db = HdbDatabase.open(dir);
    db.execute("CREATE TABLE t (k INTEGER, name VARCHAR) USING FILE");
    db.execute("INSERT INTO t VALUES (1, 'a')");

    auto tx = db.begin();
    tx.execute("INSERT INTO t VALUES (2, 'b')");
    tx.commit();
    assertThrown(tx.execute("INSERT INTO t VALUES (3, 'c')"));

    auto tx2 = db.begin();
    tx2.execute("INSERT INTO t VALUES (9, 'x')");
    tx2.rollback();
    assert(db.execute("SELECT COUNT(*) FROM t").rows[0][0].get!long == 2);

    auto b = db.backup("first");
    db.execute("DELETE FROM t WHERE k = 1");
    db.restore(b.name);
    assert(db.execute("SELECT COUNT(*) FROM t").rows[0][0].get!long == 2);
    db.close();
    db.close();
    assertThrown(db.execute("SELECT * FROM t"));

    // Wieder öffnen: der Stand kommt aus Ablage und Protokoll
    auto again = HdbDatabase.open(dir);
    assert(again.tables() == ["t"]);
    assert(again.execute("SELECT name FROM t ORDER BY k DESC").rows[0][0].get!string == "b");
    again.close();

    auto mem = HdbDatabase.inMemory();
    mem.execute("CREATE TABLE m (k INTEGER)");
    mem.execute("INSERT INTO m VALUES (5)");
    assert(mem.execute("SELECT k FROM m").rows[0][0].get!long == 5);
    assertThrown(mem.backup("x")); // ohne Verzeichnis für Sicherungen
    assertThrown(HdbDatabase.open(""));
}
