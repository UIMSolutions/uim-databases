module uim.hdb.application.services.tenants;

import uim.hdb;
import std.algorithm : map, sort;
import std.array : array, join;
import std.exception : enforce;

@safe:

/// Die bekannten Mandanten. Der Systembereich steht nicht darin und gilt immer als aktiv.
final class TenantRegistry {
    private ITenantStore store;
    private Tenant[string] tenants;
    private IpNetwork[][string] parsed; // erlaubte Netze, einmal gelesen statt bei jeder Anfrage

    this(ITenantStore store) {
        this.store = store;
        foreach (t; store.load())
            tenants[t.name] = t;
        parsed = parseAll(tenants);
    }

    /// Für AccessService: erlaubte Netze eines Mandanten; leer heißt ohne Einschränkung.
    /// Der Bereich system wird nicht eingeschränkt.
    IpNetwork[] networks(string name) {
        auto n = name in parsed;
        return n !is null ? *n : null;
    }

    private static IpNetwork[][string] parseAll(Tenant[string] all) {
        IpNetwork[][string] result;
        foreach (name, t; all)
            if (t.networks.length)
                result[name] = parseNetworks(t.networks);
        return result;
    }

    /// Für AccessService: gibt es den Mandanten, und ist er aktiv?
    bool isActive(string name) {
        if (name == systemTenant)
            return true;
        auto t = name in tenants;
        return t !is null && t.active;
    }

    bool has(string name) {
        return (name in tenants) !is null;
    }

    Tenant get(string name) {
        auto t = name in tenants;
        enforce(t !is null, "Tenant not found: " ~ name);
        return *t;
    }

    Tenant[] all() {
        auto result = tenants.values;
        result.sort!((a, b) => a.name < b.name);
        return result;
    }

    /// Erst speichern, dann übernehmen: schlägt das Schreiben fehl, bleibt alles wie es war.
    void put(Tenant tenant) {
        auto next = tenants.dup;
        next[tenant.name] = tenant;
        auto nextParsed = parseAll(next); // ungültige Netze scheitern vor dem Speichern
        store.save(next.values);
        tenants = next;
        parsed = nextParsed;
    }

    void remove(string name) {
        auto next = tenants.dup;
        next.remove(name);
        store.save(next.values);
        tenants = next;
        parsed.remove(name);
    }
}

/// Eine Datenbank je Mandant: jede Anfrage geht an die Datenbank des angemeldeten Mandanten.
/// Getrennt sind Tabellen, Protokoll, Sicherungen, Zeitplan und die offene Transaktion. Systemadministratoren
/// haben keine Datenbank und werden abgelehnt, ebenso Anfragen ohne Anmeldung.
/// Jeder Mandant kann Quelle und Ziel einer Replikation sein; ein Ziel nimmt keine Schreibzugriffe an.
final class TenantDatabases : ISqlUseCase, IBackupUseCase, IBackupScheduler, IReplicationUseCase {
    private struct Engine {
        SecuredSqlUseCase sql;
        BackupService backups;
        TenantReplication replication;
    }

    private ITenantStorage storage;
    private Principal delegate() @safe current;
    private IReplicationClient client;
    private size_t retain;
    private Engine[string] engines;

    /// `client` null: dieser Server kann Quelle sein, aber kein Ziel. `retain`: so viele Änderungen bleiben je
    /// Mandant abrufbar, ein Ziel mit größerem Rückstand holt einen vollständigen Stand.
    this(ITenantStorage storage, Principal delegate() @safe current, IReplicationClient client = null, size_t retain = 10_000) {
        this.storage = storage;
        this.current = current;
        this.client = client;
        this.retain = retain;
    }

    /// Lädt die Datenbank eines Mandanten aus ihrem Protokoll. Mehrfaches Öffnen ändert nichts.
    void open(string tenant) {
        if (tenant in engines)
            return;
        auto parts = storage.open(tenant);
        auto core = new SqlService(parts.tables, parts.log);
        core.recover();
        core.mergeDelta();
        auto feed = new ChangeFeed(retain);
        core.changeSink(feed); // erst nach dem Einspielen: der Strom beginnt mit dem geladenen Stand
        auto configs = parts.replication !is null ? parts.replication : new MemoryReplicationConfigStore;
        engines[tenant] = Engine(new SecuredSqlUseCase(core, current), new BackupService(core, parts.backups, current),
            new TenantReplication(core, feed, configs, client));
    }

    bool isOpen(string tenant) {
        return (tenant in engines) !is null;
    }

    /// Entfernt die Datenbank aus dem Speicher und löscht ihre Daten und Sicherungen endgültig.
    void purge(string tenant) {
        engines.remove(tenant);
        storage.purge(tenant);
    }

    private Engine engine() {
        auto p = current();
        if (!p.authenticated)
            throw new AuthenticationRequired;
        if (p.tenant == systemTenant)
            throw new AccessDenied("System administrators have no access to tenant data");
        auto e = p.tenant in engines;
        if (e is null)
            throw new AccessDenied("No database for tenant " ~ p.tenant);
        return *e;
    }

    /// Ein Ziel liest nur: lokale Änderungen würden beim nächsten vollständigen Stand verloren gehen und
    /// bis dahin das Einspielen der Quelle stören.
    private void requireWritable(Engine e) {
        if (e.replication.isReplica)
            throw new AccessDenied("This tenant is a read-only replica of " ~ e.replication.sourceUrl
                    ~ ". Stop the replication to change data.");
    }

    // ISqlUseCase
    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto e = engine();
        if (!isReadOnlyStatement(sql))
            requireWritable(e);
        return e.sql.executeIn(txId, sql);
    }

    string[] listTables() {
        return engine().sql.listTables();
    }

    void checkpoint() {
        engine().sql.checkpoint();
    }

    void mergeDelta() {
        engine().sql.mergeDelta();
    }

    bool mergeDeltaAsync() {
        return engine().sql.mergeDeltaAsync();
    }

    MergeStatus mergeStatus() {
        return engine().sql.mergeStatus();
    }

    TableStats[] stats() {
        return engine().sql.stats();
    }

    // IBackupUseCase
    BackupInfo[] list() {
        return engine().backups.list();
    }

    BackupInfo create(string label) {
        return engine().backups.create(label);
    }

    BackupInfo restore(string name) {
        auto e = engine();
        requireWritable(e);
        return e.backups.restore(name);
    }

    void remove(string name) {
        engine().backups.remove(name);
    }

    string download(string name) {
        return engine().backups.download(name);
    }

    BackupInfo upload(string content) {
        return engine().backups.upload(content);
    }

    BackupSchedule schedule() {
        return engine().backups.schedule();
    }

    BackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety) {
        return engine().backups.updateSchedule(enabled, intervalHours, keepScheduled, keepSafety);
    }

    // IReplicationUseCase: lesen darf jeder Benutzer des Mandanten, er sieht über SELECT ohnehin alle Daten
    ReplicationSnapshot replicationSnapshot() {
        auto e = engine();
        requirePermission(current(), Permission.replicate);
        return e.replication.snapshot();
    }

    ChangeBatch replicationChanges(string epoch, ulong since, size_t limit) {
        auto e = engine();
        requirePermission(current(), Permission.replicate);
        return e.replication.changes(epoch, since, limit);
    }

    ReplicationStatus replicationStatus() {
        auto e = engine();
        requirePermission(current(), Permission.manageReplication);
        return e.replication.status();
    }

    ReplicationStatus configureReplica(ReplicationConfig config) {
        auto e = engine();
        requirePermission(current(), Permission.manageReplication);
        return e.replication.configure(config);
    }

    ReplicationStatus stopReplica() {
        auto e = engine();
        requirePermission(current(), Permission.manageReplication);
        return e.replication.stop();
    }

    ReplicationStatus resyncReplica() {
        auto e = engine();
        requirePermission(current(), Permission.manageReplication);
        return e.replication.resync();
    }

    /// Fällige Abrufe aller Ziele. Läuft ohne Anfrage und damit ohne Identität: nur für den Zeitgeber der Anwendung.
    /// Gibt neue Fehler zurück, je Mandant einer.
    string[] replicationTick() {
        string[] errors;
        foreach (name; engines.keys) {
            auto e = name in engines;
            if (e is null)
                continue;
            if (auto error = e.replication.tick())
                errors ~= name ~ ": " ~ error;
        }
        return errors;
    }

    /// Fällige Sicherungen aller Mandanten; ein Fehler bei einem hält die anderen nicht auf.
    string tick() {
        string[] errors;
        foreach (name; engines.keys) {
            auto e = name in engines; // purge kann während einer Sicherung laufen
            if (e is null)
                continue;
            try {
                if (auto error = e.backups.tick())
                    errors ~= name ~ ": " ~ error;
            } catch (Exception ex)
                errors ~= name ~ ": " ~ ex.msg;
        }
        return errors.length ? errors.join("; ") : null;
    }
}

/// Mandanten anlegen, ändern und löschen (Recht manageTenants) und auflisten (viewTenants), beides nur im Bereich system.
final class TenantService : ITenantUseCase {
    private TenantRegistry registry;
    private ITenantAccounts accounts;
    private TenantDatabases databases;
    private ITenantStorage storage;

    this(TenantRegistry registry, ITenantAccounts accounts, TenantDatabases databases, ITenantStorage storage) {
        this.registry = registry;
        this.accounts = accounts;
        this.databases = databases;
        this.storage = storage;
    }

    TenantInfo[] listTenants(Principal actor) {
        requirePermission(actor, Permission.viewTenants);
        return registry.all().map!(t => info(t)).array;
    }

    /// Reihenfolge: prüfen, eintragen, Datenbank anlegen, Administrator anlegen. Scheitert ein Schritt,
    /// werden die vorigen zurückgenommen.
    TenantInfo createTenant(Principal actor, string name, string label, string adminName, string adminPassword) {
        requirePermission(actor, Permission.manageTenants);
        auto normalized = validTenantName(name);
        enforce(normalized != systemTenant, "This tenant name is reserved: " ~ normalized);
        enforce(!registry.has(normalized), "Tenant already exists: " ~ normalized);
        // Daten ohne Eintrag stammen von einem früheren Mandanten: nie stillschweigend übernehmen
        enforce(!storage.exists(normalized), "Data for tenant " ~ normalized
                ~ " is still on disk. Remove it before creating the tenant again.");
        auto tenant = Tenant(normalized, cleanLabel(label, normalized), true);
        registry.put(tenant);
        try {
            databases.open(normalized);
            accounts.provisionAdmin(normalized, adminName, adminPassword);
        } catch (Exception e) {
            try
                databases.purge(normalized);
            catch (Exception) {
            }
            try
                registry.remove(normalized);
            catch (Exception) {
            }
            throw e;
        }
        return info(tenant);
    }

    TenantInfo updateTenant(Principal actor, string name, string label, bool active) {
        requirePermission(actor, Permission.manageTenants);
        auto tenant = registry.get(validTenantName(name));
        tenant.label = cleanLabel(label, tenant.name);
        tenant.active = active;
        registry.put(tenant);
        if (!active)
            accounts.revokeTenant(tenant.name);
        return info(tenant);
    }

    /// Erst austragen und die Benutzer löschen, dann die Daten: bricht das Löschen der Dateien ab, ist der Mandant
    /// trotzdem nicht mehr erreichbar, und die Meldung nennt, was übrig ist.
    void deleteTenant(Principal actor, string name) {
        requirePermission(actor, Permission.manageTenants);
        auto tenant = registry.get(validTenantName(name));
        enforce(!tenant.active, "Deactivate tenant " ~ tenant.name ~ " before deleting it");
        registry.remove(tenant.name);
        accounts.removeTenant(tenant.name);
        try
            databases.purge(tenant.name);
        catch (Exception e)
            throw new Exception("Tenant " ~ tenant.name ~ " was removed, but its data could not be deleted: " ~ e.msg);
    }

    TenantInfo setTenantNetworks(Principal actor, string name, string[] networks) {
        requirePermission(actor, Permission.manageTenants);
        auto tenant = registry.get(validTenantName(name));
        tenant.networks = canonicalNetworks(networks);
        registry.put(tenant);
        return info(tenant);
    }

    string[] ownNetworks(Principal actor) {
        requireTenantAccessManager(actor);
        return registry.get(actor.tenant).networks.dup;
    }

    string[] setOwnNetworks(Principal actor, string[] networks, string clientAddress) {
        requireTenantAccessManager(actor);
        auto tenant = registry.get(actor.tenant);
        auto next = canonicalNetworks(networks);
        enforce(isAllowed(parseNetworks(next), clientAddress), "Your current address "
                ~ (clientAddress.length ? clientAddress : "(unknown)")
                ~ " is not in the list. Add it, or you would lock yourself out.");
        tenant.networks = next;
        registry.put(tenant);
        return next;
    }

    /// Netze gibt es nur für Mandanten, nicht für den Bereich system.
    private void requireTenantAccessManager(Principal actor) {
        requirePermission(actor, Permission.manageAccess);
        enforce!AccessDenied(actor.tenant != systemTenant, "The system area has no network restriction");
    }

    private TenantInfo info(Tenant t) {
        return TenantInfo(t.name, t.label, t.active, accounts.userCount(t.name), t.networks.dup);
    }
}

/// Prüft eine Liste und gibt sie in kanonischer Schreibweise zurück.
string[] canonicalNetworks(string[] entries) {
    string[] result;
    foreach (n; parseNetworks(entries))
        result ~= n.toString;
    return result;
}

private string cleanLabel(string label, string fallback) {
    import std.string : strip;

    auto trimmed = label.strip;
    enforce(trimmed.length <= 100, "Tenant labels have at most 100 characters");
    return trimmed.length ? trimmed : fallback;
}

unittest {
    import std.algorithm : canFind;
    import std.exception : assertThrown;

    static class MemTenantStore : ITenantStore {
        Tenant[] saved;
        Tenant[] load() {
            return saved;
        }

        void save(Tenant[] tenants) {
            saved = tenants.dup;
        }
    }

    static class MemBackups : IBackupStore {
        BackupInfo[] items;
        BackupSchedule plan;
        BackupInfo[] list() {
            return items;
        }

        BackupInfo save(string label, TableSnapshot[] tables) {
            auto b = BackupInfo(label ~ ".hdbbak", label);
            items ~= b;
            return b;
        }

        TableSnapshot[] load(string name) {
            return null;
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
            return plan;
        }

        void saveSchedule(BackupSchedule s) {
            plan = s;
        }
    }

    static class MemStorage : ITenantStorage {
        TenantStorage[string] opened;
        string[] purged;
        TenantStorage open(string tenant) {
            if (auto s = tenant in opened)
                return *s;
            return opened[tenant] = TenantStorage(new MemoryTableRepository, null, new MemBackups);
        }

        bool exists(string tenant) {
            return (tenant in opened) !is null;
        }

        void purge(string tenant) {
            opened.remove(tenant);
            purged ~= tenant;
        }
    }

    static class Accounts : ITenantAccounts {
        size_t[string] counts;
        string[] revoked;
        void provisionAdmin(string tenant, string name, string password) {
            enforce(password.length >= 12, "short");
            counts[tenant] = 1;
        }

        void revokeTenant(string tenant) {
            revoked ~= tenant;
        }

        void removeTenant(string tenant) {
            counts.remove(tenant);
        }

        size_t userCount(string tenant) {
            return counts.get(tenant, 0);
        }
    }

    Principal who;
    auto store = new MemTenantStore;
    auto registry = new TenantRegistry(store);
    auto storage = new MemStorage;
    auto accounts = new Accounts;
    auto databases = new TenantDatabases(storage, () => who);
    auto service = new TenantService(registry, accounts, databases, storage);
    auto sys = Principal("root", HdbRole.admin, true, systemTenant);

    // Nur Systemadministratoren
    assertThrown!AuthenticationRequired(service.listTenants(Principal.init));
    assertThrown!AccessDenied(service.listTenants(Principal("a", HdbRole.admin, true, defaultTenant)));
    assertThrown!AccessDenied(service.createTenant(Principal("s", HdbRole.editor, true, systemTenant), "x", "", "a", "long-password-1"));

    // Anlegen: Eintrag, Datenbank, Administrator
    auto acme = service.createTenant(sys, " ACME ", "Acme Corp", "admin", "long-password-1");
    assert(acme == TenantInfo("acme", "Acme Corp", true, 1));
    assert(registry.isActive("acme") && databases.isOpen("acme") && store.saved.length == 1);
    service.createTenant(sys, "globex", "", "admin", "long-password-2");
    assert(service.listTenants(sys).map!(t => t.name).array == ["acme", "globex"]);
    assert(service.listTenants(sys)[1].label == "globex");
    assertThrown(service.createTenant(sys, "acme", "", "admin", "long-password-1")); // doppelt
    assertThrown(service.createTenant(sys, "system", "", "admin", "long-password-1")); // reserviert
    assertThrown(service.createTenant(sys, "../etc", "", "admin", "long-password-1"));

    // Scheitert der Administrator, bleibt nichts zurück
    assertThrown(service.createTenant(sys, "broken", "", "admin", "short"));
    assert(!registry.has("broken") && !databases.isOpen("broken") && storage.purged.canFind("broken"));

    // Daten sind getrennt
    who = Principal("admin", HdbRole.admin, true, "acme");
    databases.execute("CREATE TABLE t (k INTEGER)");
    databases.execute("INSERT INTO t VALUES (1)");
    databases.create("mine");
    who = Principal("admin", HdbRole.admin, true, "globex");
    assert(databases.listTables().length == 0);
    assert(databases.list().length == 0);
    assertThrown(databases.execute("SELECT k FROM t"));
    databases.execute("CREATE TABLE t (k INTEGER)");
    assert(databases.execute("SELECT COUNT(*) FROM t").rows[0][0].get!long == 0);

    // Transaktionen sperren nur den eigenen Mandanten
    auto tx = databases.execute("BEGIN").transaction;
    who = Principal("admin", HdbRole.admin, true, "acme");
    databases.execute("INSERT INTO t VALUES (2)");
    who = Principal("admin", HdbRole.admin, true, "globex");
    databases.executeIn(tx, "ROLLBACK");

    // Systemadministratoren und Anonyme sehen keine Daten
    who = sys;
    assertThrown!AccessDenied(databases.listTables());
    assertThrown!AccessDenied(databases.list());
    who = Principal.init;
    assertThrown!AuthenticationRequired(databases.listTables());
    who = Principal("x", HdbRole.admin, true, "nowhere");
    assertThrown!AccessDenied(databases.listTables());

    // Geplante Sicherungen laufen für jeden Mandanten mit Tabellen
    assert(databases.tick() is null);

    // Deaktivieren beendet Sitzungen, Löschen nur danach
    assertThrown(service.deleteTenant(sys, "acme"));
    assert(!service.updateTenant(sys, "acme", "Acme", false).active);
    assert(!registry.isActive("acme") && accounts.revoked == ["acme"]);
    assertThrown(service.updateTenant(sys, "nobody", "", true));
    service.deleteTenant(sys, "acme");
    assert(!registry.has("acme") && !databases.isOpen("acme") && accounts.userCount("acme") == 0);
    assert(storage.purged.canFind("acme") && store.saved.length == 1);
    assert(registry.isActive(systemTenant) && !registry.isActive("acme"));
}

/// Erlaubte Netze: eigener Mandant mit Schutz vor dem Aussperren, Korrektur durch Systemadministratoren.
unittest {
    import std.exception : assertThrown;

    static class MemTenantStore : ITenantStore {
        Tenant[] saved;
        Tenant[] load() {
            return saved;
        }

        void save(Tenant[] tenants) {
            saved = tenants.dup;
        }
    }

    static class NoAccounts : ITenantAccounts {
        void provisionAdmin(string, string, string) {
        }

        void revokeTenant(string) {
        }

        void removeTenant(string) {
        }

        size_t userCount(string) {
            return 1;
        }
    }

    auto store = new MemTenantStore;
    auto registry = new TenantRegistry(store);
    registry.put(Tenant("acme", "Acme", true));
    auto service = new TenantService(registry, new NoAccounts, null, null);
    auto admin = Principal("a", HdbRole.admin, true, "acme");
    auto viewer = Principal("v", HdbRole.viewer, true, "acme");
    auto sys = Principal("s", HdbRole.admin, true, systemTenant);

    assert(service.ownNetworks(admin).length == 0 && registry.networks("acme").length == 0);
    assertThrown!AccessDenied(service.ownNetworks(viewer));
    assertThrown!AccessDenied(service.ownNetworks(sys)); // der Bereich system hat keine Netzliste

    // Die eigene Adresse muss in der Liste bleiben
    assertThrown(service.setOwnNetworks(admin, ["10.0.0.0/8"], "192.168.1.5"));
    assertThrown(service.setOwnNetworks(admin, ["10.0.0.0/8"], ""));
    assert(service.setOwnNetworks(admin, ["10.0.0.0/8", "192.168.1.0/24", " ", "10.0.0.0/8"], "192.168.1.5")
        == ["10.0.0.0/8", "192.168.1.0/24"]);
    assert(registry.networks("acme").length == 2 && store.saved[0].networks == ["10.0.0.0/8", "192.168.1.0/24"]);
    assertThrown(service.setOwnNetworks(admin, ["300.1.1.1"], "192.168.1.5"));
    assert(service.setOwnNetworks(admin, [], "203.0.113.1").length == 0); // leeren geht immer

    // Systemadministratoren dürfen jede Liste setzen, auch ohne eigene Adresse darin
    service.setOwnNetworks(admin, ["192.168.1.0/24"], "192.168.1.5");
    assert(service.setTenantNetworks(sys, "acme", ["198.51.100.0/24"]).networks == ["198.51.100.0/24"]);
    assertThrown!AccessDenied(service.setTenantNetworks(admin, "acme", []));
    assert(service.listTenants(sys)[0].networks == ["198.51.100.0/24"]);

    // Ein Neustart liest die Listen wieder
    auto again = new TenantRegistry(store);
    assert(again.networks("acme").length == 1 && isAllowed(again.networks("acme"), "198.51.100.77"));
}
