module uim.hdb.adapters.outbound.file_tenant_storage;

import uim.hdb;
import std.exception : enforce;
import std.file : mkdirRecurse, rename, rmdirRecurse;
static import std.file;
import std.path : buildPath;

/// Ausgehender Adapter: ein Verzeichnis je Mandant unter `root`:
///   <root>/<mandant>/tables/file   Tabellen mit Speicher FILE
///   <root>/<mandant>/tables/json   Tabellen mit Speicher JSON
///   <root>/<mandant>/hdb.log       Anweisungsprotokoll
///   <root>/<mandant>/backups       Sicherungen und Zeitplan
/// Der Name wird vor jedem Pfad geprüft: er kann nie aus `root` herausführen.
final class FileTenantStorage : ITenantStorage {
    private string root;

    this(string root) {
        this.root = root;
        if (!std.file.exists(root))
            mkdirRecurse(root);
    }

    TenantStorage open(string tenant) {
        auto dir = directoryOf(tenant);
        auto tables = buildPath(dir, "tables");
        return TenantStorage(
            new RoutingTableRepository(new MemoryTableRepository,
                new FileTableRepository(buildPath(tables, "file")), new JsonTableRepository(buildPath(tables, "json"))),
            new FileStatementLog(buildPath(dir, "hdb.log")),
            new FileBackupStore(buildPath(dir, "backups")));
    }

    bool exists(string tenant) {
        return std.file.exists(directoryOf(tenant));
    }

    void purge(string tenant) {
        auto dir = directoryOf(tenant);
        if (std.file.exists(dir))
            rmdirRecurse(dir);
    }

    private string directoryOf(string tenant) {
        enforce(validTenantName(tenant) == tenant && tenant != systemTenant, "Invalid tenant: " ~ tenant);
        return buildPath(root, tenant);
    }
}

/// Umstellung auf Mandanten: Daten aus der Zeit vor den Mandanten (Tabellen, Protokoll, Sicherungen an den
/// bisherigen Orten) ziehen in den Mandanten default. Läuft nur, wenn es dessen Verzeichnis noch nicht gibt;
/// verschoben wird, nicht kopiert, damit nichts doppelt existiert. Gibt true zurück, wenn etwas verschoben wurde.
bool migrateLegacyData(string root, string tablesDir, string logFile, string backupDir) {
    auto target = buildPath(root, defaultTenant);
    if (std.file.exists(target))
        return false;
    bool moved;
    void move(string from, string to) {
        if (!std.file.exists(from))
            return;
        if (!std.file.exists(target))
            mkdirRecurse(target);
        rename(from, to);
        moved = true;
    }

    move(tablesDir, buildPath(target, "tables"));
    move(logFile, buildPath(target, "hdb.log"));
    move(backupDir, buildPath(target, "backups"));
    return moved;
}

unittest {
    import std.exception : assertThrown;
    import std.file : readText, tempDir, write;
    import std.uuid : randomUUID;

    auto base = buildPath(tempDir, "hdb-tenant-storage-" ~ randomUUID().toString);
    scope (exit)
        if (std.file.exists(base))
            rmdirRecurse(base);

    // Altbestand an den bisherigen Orten
    mkdirRecurse(buildPath(base, "tables", "file"));
    mkdirRecurse(buildPath(base, "backups"));
    write(buildPath(base, "hdb.log"), "CREATE TABLE t (k INTEGER)\nINSERT INTO t VALUES (7)\n");
    write(buildPath(base, "backups", "schedule.json"), "{}");

    auto root = buildPath(base, "tenants");
    assert(migrateLegacyData(root, buildPath(base, "tables"), buildPath(base, "hdb.log"), buildPath(base, "backups")));
    assert(!std.file.exists(buildPath(base, "hdb.log")) && !std.file.exists(buildPath(base, "tables")));
    assert(readText(buildPath(root, "default", "hdb.log")).length);
    assert(std.file.exists(buildPath(root, "default", "backups", "schedule.json")));
    // Ein zweiter Lauf ändert nichts
    assert(!migrateLegacyData(root, buildPath(base, "tables"), buildPath(base, "hdb.log"), buildPath(base, "backups")));

    // Die verschobenen Daten gehören jetzt zum Mandanten default
    auto storage = new FileTenantStorage(root);
    assert(storage.exists("default") && !storage.exists("acme"));
    auto parts = storage.open("default");
    auto core = new SqlService(parts.tables, parts.log);
    core.recover();
    assert(core.execute("SELECT k FROM t").rows[0][0].get!long == 7);

    // Ein neuer Mandant beginnt leer und hat sein eigenes Verzeichnis
    auto acme = storage.open("acme");
    auto acmeCore = new SqlService(acme.tables, acme.log);
    acmeCore.recover();
    assert(acmeCore.listTables().length == 0);
    acmeCore.execute("CREATE TABLE a (k INTEGER)");
    assert(storage.exists("acme"));
    storage.purge("acme");
    assert(!storage.exists("acme") && storage.exists("default"));

    assertThrown(storage.open("../default"));
    assertThrown(storage.open("system"));
    assertThrown(storage.purge("Default"));

    // Ohne Altbestand legt die Umstellung nichts an
    auto fresh = buildPath(base, "fresh");
    assert(!migrateLegacyData(fresh, buildPath(base, "none"), buildPath(base, "none.log"), buildPath(base, "nob")));
    assert(!std.file.exists(buildPath(fresh, "default")));
}
