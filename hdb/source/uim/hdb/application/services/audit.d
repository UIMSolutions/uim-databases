/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Audit als Dekoratoren um die eingehenden Ports: die Dienste selbst wissen nichts vom Protokoll. app.d gibt den
/// eingehenden Adaptern (REST, Admin-Oberfläche, Unix-Socket) die dekorierten Ports, damit jede Aktion auf jedem
/// Weg gleich aufgezeichnet wird. Lesende Aufrufe gehen unverändert durch.
///
/// Was nie hineinkommt: Passwörter, Tokens, Werte aus Zeilen, das Passwort einer Replikationsquelle.
module uim.hdb.application.services.audit;

import uim.hdb;
import std.algorithm : map;
import std.array : join;
import std.format : format;
import std.regex : ctRegex, matchFirst;
import std.string : strip, toLower;

@safe:

/// Führt eine Aktion aus und zeichnet Erfolg oder Misserfolg auf; Ausnahmen gehen unverändert weiter.
private T recorded(T)(IAuditTrail trail, AuditRecord r, scope T delegate() @safe action) {
    try {
        static if (is(T == void)) {
            action();
            trail.audit(r);
        } else {
            auto result = action();
            trail.audit(r);
            return result;
        }
    } catch (Exception e) {
        r.success = false;
        r.message = e.msg;
        trail.audit(r);
        throw e;
    }
}

/// Anmeldung und Benutzerverwaltung (Kategorien auth, users, roles).
final class AuditedAccess : IAccessUseCase {
    private IAccessUseCase inner;
    private IAuditTrail trail;
    private Principal delegate() @safe current;
    private string delegate() @safe address;

    this(IAccessUseCase inner, IAuditTrail trail, Principal delegate() @safe current, string delegate() @safe address) {
        this.inner = inner;
        this.trail = trail;
        this.current = current;
        this.address = address;
    }

    LoginResult login(string tenant, string name, string password, string address) {
        auto requested = tenant.strip.toLower;
        auto r = AuditRecord(requested.length ? requested : defaultTenant, name.strip.toLower, address, "auth", "login");
        try {
            auto result = inner.login(tenant, name, password, address);
            r.scope_ = result.principal.tenant; // im Einzelmandanten-Betrieb zählt der angegebene Mandant nicht
            r.actor = result.principal.name;
            trail.audit(r);
            return result;
        } catch (Exception e) {
            r.success = false;
            r.message = e.msg;
            trail.audit(r);
            throw e;
        }
    }

    void logout(string token) {
        auto actor = current();
        if (!actor.authenticated)
            return inner.logout(token); // ein ungültiges Token: nichts, was sich zuordnen ließe
        recorded!void(trail, record(actor, "auth", "logout", actor.name), { inner.logout(token); });
    }

    Principal authenticate(string token, string address) {
        return inner.authenticate(token, address);
    }

    void changeOwnPassword(Principal actor, string current, string replacement) {
        recorded!void(trail, record(actor, "auth", "changePassword", actor.name), {
            inner.changeOwnPassword(actor, current, replacement);
        });
    }

    UserInfo[] listUsers(Principal actor) {
        return inner.listUsers(actor);
    }

    UserInfo createUser(Principal actor, string name, string password, string role) {
        auto r = record(actor, "users", "createUser", name, "role=" ~ role);
        return recorded!UserInfo(trail, r, () => inner.createUser(actor, name, password, role));
    }

    UserInfo updateUser(Principal actor, string name, string role, bool active) {
        auto r = record(actor, "users", "updateUser", name, format("role=%s active=%s", role, active));
        return recorded!UserInfo(trail, r, () => inner.updateUser(actor, name, role, active));
    }

    UserInfo setGrants(Principal actor, string name, TableGrant[] grants) {
        auto r = record(actor, "users", "setGrants", name, grants.map!(g => describe(g)).join(", "));
        return recorded!UserInfo(trail, r, () => inner.setGrants(actor, name, grants));
    }

    void resetPassword(Principal actor, string name, string replacement) {
        recorded!void(trail, record(actor, "users", "resetPassword", name), {
            inner.resetPassword(actor, name, replacement);
        });
    }

    void deleteUser(Principal actor, string name) {
        recorded!void(trail, record(actor, "users", "deleteUser", name), { inner.deleteUser(actor, name); });
    }

    RoleInfo[] listRoles(Principal actor) {
        return inner.listRoles(actor);
    }

    RoleInfo saveRole(Principal actor, string name, string description, string[] permissions) {
        auto r = record(actor, "roles", "saveRole", name, "permissions=" ~ permissions.join(","));
        return recorded!RoleInfo(trail, r, () => inner.saveRole(actor, name, description, permissions));
    }

    void deleteRole(Principal actor, string name) {
        recorded!void(trail, record(actor, "roles", "deleteRole", name), { inner.deleteRole(actor, name); });
    }

    private AuditRecord record(Principal actor, string category, string action, string target, string message = "") {
        return AuditRecord(actor.tenant, actor.name, address(), category, action, target, true, message);
    }
}

/// Mandanten (Kategorie tenants) und erlaubte Netze des eigenen Mandanten (network).
final class AuditedTenants : ITenantUseCase {
    private ITenantUseCase inner;
    private IAuditTrail trail;
    private string delegate() @safe address;

    this(ITenantUseCase inner, IAuditTrail trail, string delegate() @safe address) {
        this.inner = inner;
        this.trail = trail;
        this.address = address;
    }

    TenantInfo[] listTenants(Principal actor) {
        return inner.listTenants(actor);
    }

    TenantInfo createTenant(Principal actor, string name, string label, string adminName, string adminPassword) {
        auto r = record(actor, "tenants", "createTenant", name, "admin=" ~ adminName);
        return recorded!TenantInfo(trail, r, () => inner.createTenant(actor, name, label, adminName, adminPassword));
    }

    TenantInfo updateTenant(Principal actor, string name, string label, bool active) {
        auto r = record(actor, "tenants", "updateTenant", name, format("active=%s", active));
        return recorded!TenantInfo(trail, r, () => inner.updateTenant(actor, name, label, active));
    }

    void deleteTenant(Principal actor, string name) {
        recorded!void(trail, record(actor, "tenants", "deleteTenant", name), { inner.deleteTenant(actor, name); });
    }

    TenantInfo setTenantNetworks(Principal actor, string name, string[] networks) {
        auto r = record(actor, "tenants", "setTenantNetworks", name, networkText(networks));
        return recorded!TenantInfo(trail, r, () => inner.setTenantNetworks(actor, name, networks));
    }

    string[] ownNetworks(Principal actor) {
        return inner.ownNetworks(actor);
    }

    string[] setOwnNetworks(Principal actor, string[] networks, string clientAddress) {
        auto r = record(actor, "network", "setNetworks", actor.tenant, networkText(networks));
        return recorded!(string[])(trail, r, () => inner.setOwnNetworks(actor, networks, clientAddress));
    }

    private AuditRecord record(Principal actor, string category, string action, string target, string message = "") {
        return AuditRecord(actor.tenant, actor.name, address(), category, action, target, true, message);
    }
}

/// Daten eines Mandanten: Schema (schema), Zeilen (data), Wartung (maintenance), Sicherungen (backups) und
/// Replikation (replication). SELECT, BEGIN, COMMIT und ROLLBACK werden nicht aufgezeichnet.
final class AuditedDatabases : ISqlUseCase, IBackupUseCase, IReplicationUseCase {
    private ISqlUseCase sql;
    private IBackupUseCase backups;
    private IReplicationUseCase replication;
    private IAuditTrail trail;
    private Principal delegate() @safe current;
    private string delegate() @safe address;

    this(ISqlUseCase sql, IBackupUseCase backups, IReplicationUseCase replication, IAuditTrail trail,
        Principal delegate() @safe current, string delegate() @safe address) {
        this.sql = sql;
        this.backups = backups;
        this.replication = replication;
        this.trail = trail;
        this.current = current;
        this.address = address;
    }

    // ISqlUseCase

    QueryResult execute(string statement) {
        return executeIn("", statement);
    }

    QueryResult executeIn(string txId, string statement) {
        auto kind = classifyStatement(statement);
        if (kind.category.length == 0)
            return sql.executeIn(txId, statement);
        auto r = record(kind.category, kind.action, kind.table, kind.category == "schema" ? excerpt(statement) : "");
        if (txId.length)
            r.message = (r.message.length ? r.message ~ " " : "") ~ "(in transaction)";
        try {
            auto result = sql.executeIn(txId, statement);
            if (kind.category == "data")
                r.message = format("%s rows%s", result.affected, txId.length ? " (in transaction)" : "");
            trail.audit(r);
            return result;
        } catch (Exception e) {
            r.success = false;
            r.message = e.msg;
            trail.audit(r);
            throw e;
        }
    }

    string[] listTables() {
        return sql.listTables();
    }

    void checkpoint() {
        recorded!void(trail, record("maintenance", "checkpoint"), { sql.checkpoint(); });
    }

    void mergeDelta() {
        recorded!void(trail, record("maintenance", "merge"), { sql.mergeDelta(); });
    }

    bool mergeDeltaAsync() {
        return recorded!bool(trail, record("maintenance", "merge"), () => sql.mergeDeltaAsync());
    }

    MergeStatus mergeStatus() {
        return sql.mergeStatus();
    }

    TableStats[] stats() {
        return sql.stats();
    }

    // IBackupUseCase

    BackupInfo[] list() {
        return backups.list();
    }

    BackupInfo create(string label) {
        auto r = record("backups", "createBackup", label);
        try {
            auto info = backups.create(label);
            r.target = info.name;
            trail.audit(r);
            return info;
        } catch (Exception e) {
            r.success = false;
            r.message = e.msg;
            trail.audit(r);
            throw e;
        }
    }

    BackupInfo restore(string name) {
        auto r = record("backups", "restoreBackup", name);
        return recorded!BackupInfo(trail, r, () => backups.restore(name));
    }

    void remove(string name) {
        recorded!void(trail, record("backups", "deleteBackup", name), { backups.remove(name); });
    }

    /// Eine Sicherung enthält alle Daten: auch Herunterladen wird aufgezeichnet.
    string download(string name) {
        return recorded!string(trail, record("backups", "downloadBackup", name), () => backups.download(name));
    }

    BackupInfo upload(string content) {
        auto r = record("backups", "uploadBackup");
        try {
            auto info = backups.upload(content);
            r.target = info.name;
            trail.audit(r);
            return info;
        } catch (Exception e) {
            r.success = false;
            r.message = e.msg;
            trail.audit(r);
            throw e;
        }
    }

    BackupSchedule schedule() {
        return backups.schedule();
    }

    BackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety) {
        auto r = record("backups", "updateSchedule", "", format("enabled=%s intervalHours=%s keepScheduled=%s keepSafety=%s",
                enabled, intervalHours, keepScheduled, keepSafety));
        return recorded!BackupSchedule(trail, r,
            () => backups.updateSchedule(enabled, intervalHours, keepScheduled, keepSafety));
    }

    // IReplicationUseCase

    /// Der vollständige Stand enthält alle Daten. Der Änderungsstrom wird nicht aufgezeichnet: Ziele fragen ihn
    /// alle paar Sekunden ab.
    ReplicationSnapshot replicationSnapshot() {
        return recorded!ReplicationSnapshot(trail, record("replication", "readSnapshot"),
            () => replication.replicationSnapshot());
    }

    ChangeBatch replicationChanges(string epoch, ulong since, size_t max) {
        return replication.replicationChanges(epoch, since, max);
    }

    ReplicationStatus replicationStatus() {
        return replication.replicationStatus();
    }

    ReplicationStatus configureReplica(ReplicationConfig config) {
        auto r = record("replication", "configureReplica", config.url, format("enabled=%s tenant=%s user=%s intervalSeconds=%s",
                config.enabled, config.tenant, config.user, config.intervalSeconds));
        return recorded!ReplicationStatus(trail, r, () => replication.configureReplica(config));
    }

    ReplicationStatus stopReplica() {
        return recorded!ReplicationStatus(trail, record("replication", "stopReplica"), () => replication.stopReplica());
    }

    ReplicationStatus resyncReplica() {
        return recorded!ReplicationStatus(trail, record("replication", "resyncReplica"), () => replication.resyncReplica());
    }

    private AuditRecord record(string category, string action, string target = "", string message = "") {
        auto actor = current();
        return AuditRecord(actor.tenant, actor.name, address(), category, action, target, true, message);
    }
}

/// Was eine Anweisung für das Audit bedeutet; category leer: nicht aufzeichnen.
struct StatementKind {
    string category, action, table;
}

StatementKind classifyStatement(string statement) {
    auto s = statement.strip;
    if (auto m = matchFirst(s, ctRegex!(`^CREATE\s+TABLE\s+(\w+)`, "i")))
        return StatementKind("schema", "createTable", m[1]);
    if (auto m = matchFirst(s, ctRegex!(`^DROP\s+TABLE\s+(\w+)`, "i")))
        return StatementKind("schema", "dropTable", m[1]);
    if (auto m = matchFirst(s, ctRegex!(`^INSERT\s+INTO\s+(\w+)`, "i")))
        return StatementKind("data", "insert", m[1]);
    if (auto m = matchFirst(s, ctRegex!(`^UPDATE\s+(\w+)`, "i")))
        return StatementKind("data", "update", m[1]);
    if (auto m = matchFirst(s, ctRegex!(`^DELETE\s+FROM\s+(\w+)`, "i")))
        return StatementKind("data", "delete", m[1]);
    // Andere Schemaanweisungen, die der Kern ablehnt, sind trotzdem ein Versuch, das Schema zu ändern
    if (auto m = matchFirst(s, ctRegex!(`^(CREATE|DROP|ALTER|TRUNCATE|RENAME)\b`, "i")))
        return StatementKind("schema", m[1].toLower, "");
    return StatementKind.init;
}

/// Anfang einer Anweisung, höchstens 300 Zeichen.
private string excerpt(string statement) {
    import std.utf : toUTF32, toUTF8;

    auto s = statement.strip;
    auto chars = s.toUTF32;
    return chars.length <= 300 ? s : chars[0 .. 300].toUTF8 ~ " …";
}

private string describe(TableGrant g) {
    auto text = (g.table.length ? g.table : "*") ~ ":" ~ g.role;
    if (g.from.length || g.until.length)
        text ~= " [" ~ g.from ~ " – " ~ g.until ~ "]";
    return text;
}

private string networkText(string[] networks) {
    return networks.length ? "networks=" ~ networks.join(",") : "networks=any";
}

unittest {
    import std.algorithm : canFind;
    import std.array : array;
    import std.exception : assertThrown;

    assert(classifyStatement(" create table Orders (id INTEGER)") == StatementKind("schema", "createTable", "Orders"));
    assert(classifyStatement("DELETE FROM t WHERE a = 1") == StatementKind("data", "delete", "t"));
    assert(classifyStatement("update  t set a = 2") == StatementKind("data", "update", "t"));
    assert(classifyStatement("ALTER TABLE t ADD x INT").category == "schema");
    assert(classifyStatement("SELECT * FROM t").category == "");
    assert(classifyStatement("COMMIT").category == "");

    auto store = new MemoryLogStore;
    auto settings = new MemoryLogSettingsStore;
    auto logs = new LogService(store, settings);
    // data aufzeichnen, damit auch Zeilenänderungen erscheinen
    auto sys = Principal("sys", HdbRole.admin, true, "system");
    auto acmeAdmin = Principal("ann", HdbRole.admin, true, "acme");
    auto all = logs.settings(acmeAdmin, LogKind.audit);
    all.categories = ["auth", "users", "roles", "data", "schema", "backups", "maintenance"];
    logs.configure(acmeAdmin, LogKind.audit, all, "");

    LogEntry[] audit() {
        return logs.read(sys, LogQuery(LogKind.audit, "", LogSeverity.debug_, "", "", "", "", "", 1000)).entries;
    }

    // Zugang
    static class FakeAccess : IAccessUseCase {
        LoginResult login(string tenant, string name, string password, string address) {
            if (password != "right")
                throw new AuthenticationRequired("Invalid tenant, user name or password");
            return LoginResult("token", Principal(name, HdbRole.admin, true, "acme"), 60);
        }

        void logout(string) {
        }

        Principal authenticate(string, string) {
            return Principal.init;
        }

        void changeOwnPassword(Principal, string, string) {
        }

        UserInfo[] listUsers(Principal) {
            return null;
        }

        UserInfo createUser(Principal actor, string name, string, string role) {
            if (role == "root")
                throw new Exception("Unknown role: root");
            return UserInfo.init;
        }

        UserInfo updateUser(Principal, string, string, bool) {
            return UserInfo.init;
        }

        UserInfo setGrants(Principal, string, TableGrant[]) {
            return UserInfo.init;
        }

        void resetPassword(Principal, string, string) {
        }

        void deleteUser(Principal actor, string) {
            throw new AccessDenied("Requires permission manageAccess");
        }

        RoleInfo[] listRoles(Principal) {
            return null;
        }

        RoleInfo saveRole(Principal, string, string, string[]) {
            return RoleInfo.init;
        }

        void deleteRole(Principal, string) {
        }
    }

    Principal requestPrincipal = acmeAdmin;
    auto access = new AuditedAccess(new FakeAccess, logs, () => requestPrincipal, () => "10.1.1.1");
    access.login(" ACME ", "Ann", "right", "10.1.1.1");
    assertThrown!AuthenticationRequired(access.login("acme", "ann", "wrong", "10.1.1.2"));
    access.createUser(acmeAdmin, "carl", "secret-password", "editor");
    assertThrown(access.createUser(acmeAdmin, "dave", "secret-password", "root"));
    assertThrown!AccessDenied(access.deleteUser(acmeAdmin, "carl"));
    access.setGrants(acmeAdmin, "carl", [TableGrant("orders", "viewer"), TableGrant("", "admin", "", "2026-12-01T00:00:00Z")]);
    access.logout("token");
    access.listUsers(acmeAdmin); // lesen: nichts

    auto entries = audit();
    assert(entries.length == 8); // 7 Aktionen und die Änderung der Einstellungen
    assert(entries[0].action == "logout" && entries[0].actor == "ann");
    assert(entries[1].message == "orders:viewer, *:admin [ – 2026-12-01T00:00:00Z]");
    assert(!entries[2].success && entries[2].message == "Requires permission manageAccess" && entries[2].target == "carl");
    assert(!entries[3].success && entries[3].message == "Unknown role: root");
    assert(entries[4].message == "role=editor" && entries[4].address == "10.1.1.1");
    assert(!entries[5].success && entries[5].address == "10.1.1.2" && entries[5].scope_ == "acme");
    assert(entries[6].success && entries[6].actor == "Ann" && entries[6].category == "auth");
    foreach (e; entries)
        assert(!e.message.canFind("secret") && !e.message.canFind("right") && !e.message.canFind("wrong"));

    // Daten
    static class FakeDb : ISqlUseCase, IBackupUseCase, IReplicationUseCase {
        QueryResult execute(string s) {
            return executeIn("", s);
        }

        QueryResult executeIn(string, string s) {
            if (s.canFind("missing"))
                throw new Exception("Tabelle nicht gefunden: missing");
            return QueryResult(null, null, 3, "ok");
        }

        string[] listTables() {
            return null;
        }

        void checkpoint() {
        }

        void mergeDelta() {
        }

        bool mergeDeltaAsync() {
            return true;
        }

        MergeStatus mergeStatus() {
            return MergeStatus.init;
        }

        TableStats[] stats() {
            return null;
        }

        BackupInfo[] list() {
            return null;
        }

        BackupInfo create(string label) {
            BackupInfo b;
            b.name = "backup-1";
            b.label = label;
            return b;
        }

        BackupInfo restore(string name) {
            return BackupInfo.init;
        }

        void remove(string) {
        }

        string download(string) {
            return "all the data";
        }

        BackupInfo upload(string) {
            throw new Exception("Not a backup");
        }

        BackupSchedule schedule() {
            return BackupSchedule.init;
        }

        BackupSchedule updateSchedule(bool, int, int, int) {
            return BackupSchedule.init;
        }

        ReplicationSnapshot replicationSnapshot() {
            return ReplicationSnapshot.init;
        }

        ChangeBatch replicationChanges(string, ulong, size_t) {
            return ChangeBatch.init;
        }

        ReplicationStatus replicationStatus() {
            return ReplicationStatus.init;
        }

        ReplicationStatus configureReplica(ReplicationConfig) {
            return ReplicationStatus.init;
        }

        ReplicationStatus stopReplica() {
            return ReplicationStatus.init;
        }

        ReplicationStatus resyncReplica() {
            return ReplicationStatus.init;
        }
    }

    auto fake = new FakeDb;
    auto db = new AuditedDatabases(fake, fake, fake, logs, () => requestPrincipal, () => "10.1.1.1");
    immutable before = audit().length;
    db.execute("SELECT * FROM orders");
    db.executeIn("", "BEGIN");
    db.execute("CREATE TABLE orders (id INTEGER, note TEXT)");
    db.executeIn("tx1", "INSERT INTO orders VALUES (1, 'my secret note')");
    assertThrown(db.execute("DROP TABLE missing"));
    db.checkpoint();
    assert(db.create("before upgrade").name == "backup-1");
    assert(db.download("backup-1") == "all the data");
    assertThrown(db.upload("garbage"));
    db.replicationChanges("e", 0, 10); // nicht aufgezeichnet, aber replication ist auch nicht gewählt

    entries = audit()[0 .. $ - before];
    assert(entries.length == 7);
    assert(entries[0].action == "uploadBackup" && !entries[0].success && entries[0].message == "Not a backup");
    assert(entries[1].action == "downloadBackup" && entries[1].target == "backup-1");
    assert(entries[2].action == "createBackup" && entries[2].target == "backup-1");
    assert(entries[3].category == "maintenance");
    assert(entries[4].action == "dropTable" && !entries[4].success && entries[4].target == "missing");
    assert(entries[5].action == "insert" && entries[5].target == "orders" && entries[5].message == "3 rows (in transaction)");
    assert(entries[6].action == "createTable" && entries[6].message == "CREATE TABLE orders (id INTEGER, note TEXT)");
    foreach (e; entries)
        assert(!e.message.canFind("secret note"));

    // Mandanten
    static class FakeTenants : ITenantUseCase {
        TenantInfo[] listTenants(Principal) {
            return null;
        }

        TenantInfo createTenant(Principal, string name, string, string, string) {
            return TenantInfo(name);
        }

        TenantInfo updateTenant(Principal, string name, string, bool) {
            return TenantInfo(name);
        }

        void deleteTenant(Principal, string) {
        }

        TenantInfo setTenantNetworks(Principal, string name, string[]) {
            return TenantInfo(name);
        }

        string[] ownNetworks(Principal) {
            return null;
        }

        string[] setOwnNetworks(Principal, string[] networks, string) {
            return networks;
        }
    }

    auto tenants = new AuditedTenants(new FakeTenants, logs, () => "10.9.9.9");
    tenants.createTenant(sys, "beta", "Beta", "bob", "bob-secret-pw");
    tenants.setOwnNetworks(acmeAdmin, ["10.0.0.0/8"], "10.1.1.1"); // network ist für acme nicht gewählt
    auto systemEntries = logs.read(sys, LogQuery(LogKind.audit, "system")).entries;
    assert(systemEntries[0].action == "createTenant" && systemEntries[0].message == "admin=bob");
    assert(!audit()[0].message.canFind("networks"));
}
