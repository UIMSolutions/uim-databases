module uim.hdb.application.services.tenants;

import uim.hdb;
import std.algorithm : map, sort;
import std.array : array, join;
import std.exception : enforce;

/// Die bekannten Mandanten. Der Systembereich steht nicht darin und gilt immer als aktiv.
final class TenantRegistry {
    private ITenantStore store;
    private Tenant[string] tenants;

    this(ITenantStore store) {
        this.store = store;
        foreach (t; store.load())
            tenants[t.name] = t;
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
        store.save(next.values);
        tenants = next;
    }

    void remove(string name) {
        auto next = tenants.dup;
        next.remove(name);
        store.save(next.values);
        tenants = next;
    }
}

/// Eine Datenbank je Mandant: jede Anfrage geht an die Datenbank des angemeldeten Mandanten.
/// Getrennt sind Tabellen, Protokoll, Sicherungen, Zeitplan und die offene Transaktion. Systemadministratoren
/// haben keine Datenbank und werden abgelehnt, ebenso Anfragen ohne Anmeldung.
final class TenantDatabases : ISqlUseCase, IBackupUseCase, IBackupScheduler {
    private struct Engine {
        SecuredSqlUseCase sql;
        BackupService backups;
    }

    private ITenantStorage storage;
    private Principal delegate() current;
    private Engine[string] engines;

    this(ITenantStorage storage, Principal delegate() current) {
        this.storage = storage;
        this.current = current;
    }

    /// Lädt die Datenbank eines Mandanten aus ihrem Protokoll. Mehrfaches Öffnen ändert nichts.
    void open(string tenant) {
        if (tenant in engines)
            return;
        auto parts = storage.open(tenant);
        auto core = new SqlService(parts.tables, parts.log);
        core.recover();
        core.mergeDelta();
        engines[tenant] = Engine(new SecuredSqlUseCase(core, current), new BackupService(core, parts.backups, current));
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

    // ISqlUseCase
    QueryResult execute(string sql) {
        return engine().sql.execute(sql);
    }

    QueryResult executeIn(string txId, string sql) {
        return engine().sql.executeIn(txId, sql);
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
        return engine().backups.restore(name);
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

/// Mandanten anlegen, ändern und löschen. Nur Systemadministratoren dürfen das.
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
        requireSystemAdmin(actor);
        return registry.all().map!(t => info(t)).array;
    }

    /// Reihenfolge: prüfen, eintragen, Datenbank anlegen, Administrator anlegen. Scheitert ein Schritt,
    /// werden die vorigen zurückgenommen.
    TenantInfo createTenant(Principal actor, string name, string label, string adminName, string adminPassword) {
        requireSystemAdmin(actor);
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
        requireSystemAdmin(actor);
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
        requireSystemAdmin(actor);
        auto tenant = registry.get(validTenantName(name));
        enforce(!tenant.active, "Deactivate tenant " ~ tenant.name ~ " before deleting it");
        registry.remove(tenant.name);
        accounts.removeTenant(tenant.name);
        try
            databases.purge(tenant.name);
        catch (Exception e)
            throw new Exception("Tenant " ~ tenant.name ~ " was removed, but its data could not be deleted: " ~ e.msg);
    }

    private TenantInfo info(Tenant t) {
        return TenantInfo(t.name, t.label, t.active, accounts.userCount(t.name));
    }
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
