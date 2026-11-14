module uim.hdb.presentation.rest.services;

import uim.hdb.adapters.inbound.admin_web : createTableSql, isIdentifier, selectSql;
import uim.hdb.adapters.inbound.security : bearerToken, currentClientAddress;
import uim.hdb.application.ports : BackupNotFound, IAccessUseCase, IBackupUseCase, ILogUseCase, IReplicationUseCase,
    ISqlUseCase, ITenantUseCase, LogQuery, ReplicationConfig;
import uim.hdb.adapters.outbound.replication_http : changeBatchJson;
import uim.hdb.infrastructure.repositories.backups : encodeSnapshot;
import uim.hdb.domain.entities.user;
import uim.hdb;
import uim.hdb.domain.value;
import uim.hdb.presentation.rest.interfaces;
import uim.hdb.presentation.rest.models;
import std.algorithm : any, map;
import std.array : array, join;
import std.conv : to;
import std.exception : enforce;
import std.string : icmp, toUpper;
import vibe.data.json : Json, serializeToJson;
import vibe.http.common : HTTPStatusException;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.stream.operations : readAllUTF8;
import vibe.web.rest : registerRestInterface, RestErrorInformation, RestInterfaceSettings;

@safe:

private enum long maxRowLimit = 1000;

final class SystemRestApi : ISystemRestApi {
@safe:
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    RestStatus health() {
        return RestStatus("UP");
    }

    RestTableInfo[] stats() {
        return sql.stats().map!(t => toRest(t)).array;
    }

    RestStatus checkpoint() {
        sql.checkpoint();
        return RestStatus("CHECKPOINTED");
    }

    RestMergeStatus mergeStatus() {
        return toRest(sql.mergeStatus());
    }

    RestStatus startMerge(out int httpStatus) {
        immutable started = sql.mergeDeltaAsync();
        httpStatus = HTTPStatus.accepted;
        return RestStatus(started ? "STARTED" : "RUNNING");
    }
}

final class SqlExecutionRestApi : ISqlRestApi {
@safe:
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    RestSqlResult execute(string statement, string transaction, string headerTransaction) {
        return toRest(sql.executeIn(transaction.length ? transaction : headerTransaction, statement));
    }
}

final class TableRestApi : ITableRestApi {
@safe:
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    string[] list() {
        return sql.listTables();
    }

    RestTableInfo create(string name, RestColumnDef[] columns, string storage) {
        sql.execute(createTableSql(name, columns.map!(c => c.name).array, columns.map!(c => c.type.toUpper).array, storage));
        return toRest(find(name));
    }

    RestTableInfo info(string _name) {
        return toRest(find(_name));
    }

    RestStatus drop(string _name) {
        sql.execute("DROP TABLE " ~ find(_name).table);
        return RestStatus("DROPPED");
    }

    RestRowPage rows(string _name, string where, string sort, bool desc, long limit, long offset) {
        auto t = find(_name);
        enforce(limit >= 1 && limit <= maxRowLimit, "limit must be between 1 and " ~ maxRowLimit.to!string);
        enforce(offset >= 0, "offset must not be negative");
        enforce(sort.length == 0 || t.columns.any!(c => icmp(c.name, sort) == 0), "Unknown column: " ~ sort);

        auto count = "SELECT COUNT(*) FROM " ~ t.table ~ (where.length ? " WHERE " ~ where : "");
        auto total = sql.execute(count).rows[0][0].get!long;
        auto r = sql.execute(selectSql(t.table, where, sort, desc, limit, offset));
        return RestRowPage(r.columns, toRestRows(r.rows), total, limit, offset);
    }

    RestSqlResult insert(string _name, Json[] values) {
        auto t = find(_name);
        enforce(values.length == t.columns.length, "Expected one value per column");
        string[] literals;
        foreach (i, c; t.columns)
            literals ~= jsonLiteral(c, values[i]);
        return toRest(sql.execute("INSERT INTO " ~ t.table ~ " VALUES (" ~ literals.join(", ") ~ ")"));
    }

    private TableStats find(string name) {
        if (isIdentifier(name))
            foreach (t; sql.stats())
                if (icmp(t.table, name) == 0)
                    return t;
        throw new HTTPStatusException(HTTPStatus.notFound, "Table not found: " ~ name);
    }
}

final class AuthRestApi : IAuthRestApi {
    private IAccessUseCase access;
    private Principal delegate() @safe current;

    this(IAccessUseCase access, Principal delegate() @safe current) {
        this.access = access;
        this.current = current;
    }

@safe:
    RestLogin login(string user, string password, string tenant) {
        auto r = access.login(tenant, user, password, currentClientAddress());
        return RestLogin(r.token, r.expiresInSeconds, RestUser(r.principal.name, r.principal.role, true, r.principal.tenant));
    }

    RestStatus logout(string authorization) {
        access.logout(bearerToken(authorization));
        return RestStatus("LOGGED_OUT");
    }

    RestMe me() {
        auto p = current();
        requireAuthenticated(p);
        return toRestMe(p);
    }

    RestStatus changePassword(string oldPassword, string replacement) {
        access.changeOwnPassword(current(), oldPassword, replacement);
        return RestStatus("PASSWORD_CHANGED");
    }
}

final class UserRestApi : IUserRestApi {
    private IAccessUseCase access;
    private Principal delegate() @safe current;

    this(IAccessUseCase access, Principal delegate() @safe current) {
        this.access = access;
        this.current = current;
    }

@safe:
    RestUser[] list() {
        return access.listUsers(current()).map!(u => toRest(u)).array;
    }

    RestUser create(string name, string password, string role) {
        return toRest(access.createUser(current(), name, password, role));
    }

    RestUser update(string _name, string role, bool active) {
        return toRest(access.updateUser(current(), _name, role, active));
    }

    RestStatus resetPassword(string _name, string password) {
        access.resetPassword(current(), _name, password);
        return RestStatus("PASSWORD_RESET");
    }

    RestStatus remove(string _name) {
        access.deleteUser(current(), _name);
        return RestStatus("DELETED");
    }

    RestUser setGrants(string _name, RestGrant[] grants) {
        return toRest(access.setGrants(current(), _name, grants.map!(g => TableGrant(g.table, g.role, g.from, g.until)).array));
    }

    RestRole[] roles() {
        return access.listRoles(current()).map!(r => toRest(r)).array;
    }

    RestRole saveRole(string _name, string[] permissions, string description) {
        return toRest(access.saveRole(current(), _name, description, permissions));
    }

    RestStatus removeRole(string _name) {
        access.deleteRole(current(), _name);
        return RestStatus("DELETED");
    }
}

final class TenantRestApi : ITenantRestApi {
    private ITenantUseCase tenants;
    private Principal delegate() @safe current;

    this(ITenantUseCase tenants, Principal delegate() @safe current) {
        this.tenants = tenants;
        this.current = current;
    }

@safe:
    RestTenant[] list() {
        return tenants.listTenants(current()).map!(t => toRest(t)).array;
    }

    RestTenant create(string name, string adminName, string adminPassword, string label) {
        return toRest(tenants.createTenant(current(), name, label, adminName, adminPassword));
    }

    RestTenant update(string _name, bool active, string label) {
        return toRest(tenants.updateTenant(current(), _name, label, active));
    }

    RestStatus remove(string _name) {
        tenants.deleteTenant(current(), _name);
        return RestStatus("DELETED");
    }

    RestTenant setNetworks(string _name, string[] networks) {
        return toRest(tenants.setTenantNetworks(current(), _name, networks));
    }
}

final class NetworkRestApi : INetworkRestApi {
    private ITenantUseCase tenants;
    private Principal delegate() @safe current;

    this(ITenantUseCase tenants, Principal delegate() @safe current) {
        this.tenants = tenants;
        this.current = current;
    }

@safe:
    RestNetworks get() {
        return RestNetworks(tenants.ownNetworks(current()), currentClientAddress());
    }

    RestNetworks set(string[] networks) {
        return RestNetworks(tenants.setOwnNetworks(current(), networks, currentClientAddress()), currentClientAddress());
    }
}

final class BackupRestApi : IBackupRestApi {
    private IBackupUseCase backups;

    this(IBackupUseCase backups) {
        this.backups = backups;
    }

@safe:
    RestBackup[] list() {
        return backups.list().map!(b => toRest(b)).array;
    }

    RestBackup create(string label) {
        return toRest(backups.create(label));
    }

    RestBackupSchedule schedule() {
        return toRest(backups.schedule());
    }

    RestBackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety) {
        return toRest(backups.updateSchedule(enabled, intervalHours, keepScheduled, keepSafety));
    }

    RestRestore restore(string _name) {
        return RestRestore("RESTORED", toRest(backups.restore(_name)));
    }

    RestStatus remove(string _name) {
        backups.remove(_name);
        return RestStatus("DELETED");
    }
}

final class LogRestApi : ILogRestApi {
    private ILogUseCase logs;
    private Principal delegate() @safe current;

    this(ILogUseCase logs, Principal delegate() @safe current) {
        this.logs = logs;
        this.current = current;
    }

@safe:
    RestLogInfo[] list() {
        return logs.logs(current()).map!(i => toRest(i)).array;
    }

    RestLogPage entries(string _kind, string severity, string category, string actor, string text, string tenant,
        string from, string until, long limit, long before) {
        enforce(limit >= 1 && limit <= 1000, "limit must be between 1 and 1000");
        enforce(before >= 0, "before must not be negative");
        LogQuery q;
        q.kind = kindOf(_kind);
        if (severity.length)
            q.minSeverity = parseSeverity(severity);
        q.category = category;
        q.actor = actor;
        q.text = text;
        q.scope_ = tenant;
        q.from = from;
        q.until = until;
        q.limit = cast(size_t) limit;
        q.before = cast(ulong) before;
        auto page = logs.read(current(), q);
        return RestLogPage(page.entries.map!(e => toRest(e)).array, cast(long) page.total);
    }

    RestLogSettings settings(string _kind) {
        return toRest(logs.settings(current(), kindOf(_kind)));
    }

    RestLogSettings configure(string _kind, bool enabled, string minSeverity, int retentionDays, long maxEntries,
        string[] categories) {
        enforce(maxEntries >= 0, "Maximum entries must not be negative");
        auto next = LogSettings(enabled, parseSeverity(minSeverity), retentionDays, cast(size_t) maxEntries, categories);
        return toRest(logs.configure(current(), kindOf(_kind), next, currentClientAddress()));
    }

    private static LogKind kindOf(string name) {
        try
            return parseLogKind(name);
        catch (Exception e)
            throw new HTTPStatusException(HTTPStatus.notFound, e.msg);
    }
}

unittest {
    import std.exception : assertThrown;

    ColumnStats column;
    column.name = "c";
    column.type = ColumnType.blob;
    assert(jsonLiteral(column, Json("00ff")) == "'00FF'");
    assert(jsonLiteral(column, Json(null)) == "NULL");
    assertThrown(jsonLiteral(column, Json("xyz")));
    assertThrown(jsonLiteral(column, Json(12)));
    assertThrown(jsonLiteral(column, Json(1.5)));
    column.type = ColumnType.geo;
    assert(jsonLiteral(column, Json("point(1 2)")) == "'POINT(1 2)'");
    assertThrown(jsonLiteral(column, Json("nowhere")));
    assertThrown(jsonLiteral(column, Json(1)));
    column.type = ColumnType.link;
    assert(jsonLiteral(column, Json("https://a.org/it's")) == "'https://a.org/it''s'");
    assertThrown(jsonLiteral(column, Json("javascript:alert(1)")));
    assertThrown(jsonLiteral(column, Json(true)));

    column.type = ColumnType.boolean;
    assert(jsonLiteral(column, Json(true)) == "true" && jsonLiteral(column, Json(false)) == "false");
    assertThrown(jsonLiteral(column, Json(1)));
    column.type = ColumnType.byte_;
    assert(jsonLiteral(column, Json(255)) == "255");
    assertThrown(jsonLiteral(column, Json(256)));
    assertThrown(jsonLiteral(column, Json(1.5)));
    assertThrown(jsonLiteral(column, Json("1")));
    column.type = ColumnType.exact;
    assert(jsonLiteral(column, Json("12345678901234567890.10")) == "12345678901234567890.1");
    assert(jsonLiteral(column, Json(1.5)) == "1.5" && jsonLiteral(column, Json(2)) == "2");
    column.type = ColumnType.duration;
    assert(jsonLiteral(column, Json("PT36H")) == "'P1DT12H'");
    column.type = ColumnType.dateTime;
    assert(jsonLiteral(column, Json("2026-11-06T12:00:00+01:00")) == "'2026-11-06T11:00:00.0000000Z'");
}

/// SQL-Literal eines JSON-Werts, geprüft gegen den Spaltentyp; Eingaben gelangen nie ungequotet in die Anweisung.
string jsonLiteral(ColumnStats column, Json value) {
    final switch (value.type) with (Json.Type) {
    case null_:
        return "NULL";
    case string:
        enforce(!isNumeric(column.type) || column.type == ColumnType.exact, "Column " ~ column.name ~ " expects a number");
        return toSqlLiteral(valueFromInput(column.type, value.get!(.string)));
    case int_:
    case bigInt:
        enforce(isNumeric(column.type) || column.type == ColumnType.text, "Column " ~ column.name ~ " does not take a number");
        return toSqlLiteral(valueFromInput(column.type, value.to!(.string)));
    case float_:
        enforce(!isIntegerType(column.type), "Column " ~ column.name ~ " expects an integer");
        enforce(isNumeric(column.type) || column.type == ColumnType.text, "Column " ~ column.name ~ " does not take a number");
        return toSqlLiteral(valueFromInput(column.type, exactText(value.get!double)));
    case bool_:
        enforce(column.type == ColumnType.boolean, "Column " ~ column.name ~ " does not take a boolean");
        return value.get!bool ? "true" : "false";
    case undefined:
    case array:
    case object:
        throw new Exception("Unsupported value for column " ~ column.name);
    }
}

private void writeRestError(HTTPServerResponse res, Exception e) @safe {
    if (cast(AuthenticationRequired) e)
        res.statusCode = HTTPStatus.unauthorized;
    else if (cast(AccessDenied) e)
        res.statusCode = HTTPStatus.forbidden;
    else if (cast(BackupNotFound) e)
        res.statusCode = HTTPStatus.notFound;
    else if (auto status = cast(HTTPStatusException) e)
        res.statusCode = status.status;
    else
        res.statusCode = HTTPStatus.badRequest;
    res.writeJsonBody(["statusMessage": e.msg]);
}

/// Registers all REST interfaces. Input errors (invalid SQL, locked database) result in a 400
/// as with POST /sql; the HTTPStatusException retains its status. Stack traces are not included in the response.
/// `logs` null: ohne die Protokoll-Endpunkte.
void registerHdbRestApi(URLRouter router, ISqlUseCase sql, IAccessUseCase access, IBackupUseCase backups,
    ITenantUseCase tenants, IReplicationUseCase replication, Principal delegate() @safe current,
    ILogUseCase logs = null) {
    auto settings = new RestInterfaceSettings;
    settings.errorHandler = (HTTPServerRequest req, HTTPServerResponse res, RestErrorInformation error) @safe {
        writeRestError(res, error.exception);
    };
    router.registerRestInterface!ISystemRestApi(new SystemRestApi(sql), settings);
    router.registerRestInterface!ISqlRestApi(new SqlExecutionRestApi(sql), settings);
    router.registerRestInterface!ITableRestApi(new TableRestApi(sql), settings);
    router.registerRestInterface!IAuthRestApi(new AuthRestApi(access, current), settings);
    router.registerRestInterface!IUserRestApi(new UserRestApi(access, current), settings);
    router.registerRestInterface!ITenantRestApi(new TenantRestApi(tenants, current), settings);
    router.registerRestInterface!INetworkRestApi(new NetworkRestApi(tenants, current), settings);
    if (logs !is null)
        router.registerRestInterface!ILogRestApi(new LogRestApi(logs, current), settings);
    // Das Label ist optional, die REST-Schnittstelle verlangt aber immer einen JSON-Rumpf
    router.post("/api/v1/backups", (HTTPServerRequest req, HTTPServerResponse res) {
        if (req.headers.get("Content-Length", "0") != "0" || "Transfer-Encoding" in req.headers)
            return;
        try
            res.writeJsonBody(serializeToJson(toRest(backups.create(""))));
        catch (Exception e)
            writeRestError(res, e);
    });
    router.registerRestInterface!IBackupRestApi(new BackupRestApi(backups), settings);

    router.get("/api/v1/backups/:name/content", (HTTPServerRequest req, HTTPServerResponse res) {
        try {
            auto content = backups.download(req.params["name"]);
            res.headers["Content-Disposition"] = `attachment; filename="` ~ req.params["name"] ~ `"`;
            res.writeBody(content, "application/octet-stream");
        } catch (Exception e)
            writeRestError(res, e);
    });
    registerReplicationRoutes(router, replication);
    router.post("/api/v1/backups/import", (HTTPServerRequest req, HTTPServerResponse res) {
        try {
            requirePermission(current(), Permission.manageBackups); // vor dem Lesen des Rumpfs
            res.statusCode = HTTPStatus.created;
            res.writeJsonBody(serializeToJson(toRest(backups.upload(req.bodyReader.readAllUTF8()))));
        } catch (Exception e)
            writeRestError(res, e);
    });
}
/// Replikation. Quelle: Stand im Sicherungsformat (Position in X-Hdb-Epoch und X-Hdb-Sequence) und Änderungen ab
/// einer Position, beides für jeden Benutzer des Mandanten. Ziel: Einstellungen und Zustand, nur für admin.
/// Das Passwort der Quelle wird angenommen, aber nie ausgegeben.
private void registerReplicationRoutes(URLRouter router, IReplicationUseCase replication) {
    static void handle(HTTPServerResponse res, scope void delegate() @safe work) @safe {
        try
            work();
        catch (Exception e)
            writeRestError(res, e);
    }

    router.get("/api/v1/replication/snapshot", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, {
            auto snap = replication.replicationSnapshot();
            res.headers["X-Hdb-Epoch"] = snap.epoch;
            res.headers["X-Hdb-Sequence"] = snap.sequence.to!string;
            res.writeBody(encodeSnapshot("replication", snap.tables), "application/octet-stream");
        });
    });
    router.get("/api/v1/replication/changes", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, {
            ulong since;
            size_t limit;
            try {
                since = req.query.get("since", "0").to!ulong;
                limit = req.query.get("max", "500").to!size_t;
            } catch (Exception)
                throw new HTTPStatusException(HTTPStatus.badRequest, "since and max must be whole numbers");
            res.writeJsonBody(changeBatchJson(replication.replicationChanges(req.query.get("epoch", ""), since, limit)));
        });
    });
    router.get("/api/v1/replication", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, { res.writeJsonBody(serializeToJson(replication.replicationStatus())); });
    });
    router.put("/api/v1/replication/source", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, {
            auto j = req.json;
            enforce(j.isObject, "JSON object expected");
            string text(string key) {
                auto v = j[key];
                if (v.type == Json.Type.undefined || v.isNull)
                    return "";
                enforce(v.isString, key ~ " must be text");
                return v.get!string;
            }

            ReplicationConfig config;
            config.url = text("url");
            config.tenant = text("tenant");
            config.user = text("user");
            config.password = text("password");
            auto interval = j["intervalSeconds"];
            if (interval.isInteger)
                config.intervalSeconds = interval.get!int;
            else
                enforce(interval.type == Json.Type.undefined, "intervalSeconds must be a whole number");
            res.writeJsonBody(serializeToJson(replication.configureReplica(config)));
        });
    });
    router.delete_("/api/v1/replication/source", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, { res.writeJsonBody(serializeToJson(replication.stopReplica())); });
    });
    router.post("/api/v1/replication/resync", (HTTPServerRequest req, HTTPServerResponse res) @safe {
        handle(res, { res.writeJsonBody(serializeToJson(replication.resyncReplica())); });
    });
}

///
/// Actual run over HTTP using the clients generated from the interfaces, including the gateway and roles.
unittest {
    import uim.hdb;
    import std.exception : collectException;
    import std.file : exists, rmdirRecurse, tempDir;
    import std.functional : toDelegate;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import vibe.http.client : HTTPClientRequest;
    import vibe.http.server : HTTPServerSettings, listenHTTP;
    import vibe.web.rest : RestException, RestInterfaceClient;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.map!"a".array;
        }
    }

    static class MemTenants : ITenantStore {
        Tenant[] saved;
        Tenant[] load() {
            return saved;
        }

        void save(Tenant[] tenants) {
            saved = tenants.map!"a".array;
        }
    }

    // Derselbe Aufbau wie in app.d: eine Datenbank je Mandant, Systemadministratoren getrennt
    auto dataDir = buildPath(tempDir, "hdb-rest-tenants-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dataDir))
            rmdirRecurse(dataDir);
    auto principal = toDelegate(&currentPrincipal);
    auto registry = new TenantRegistry(new MemTenants);
    registry.put(Tenant(defaultTenant, "Default", true));
    auto access = new AccessService(new MemStore, new OpensslCredentialCrypto, null, &registry.isActive);
    access.bootstrap("root", "correct-horse-root");
    access.bootstrap(systemTenant, "sys", "correct-horse-sys1");
    auto storage = new FileTenantStorage(dataDir);
    auto databases = new TenantDatabases(storage, principal);
    databases.open(defaultTenant);
    auto tenantService = new TenantService(registry, access, databases, storage);
    auto router = new URLRouter;
    new SecurityGate(access).register(router);
    registerHdbRestApi(router, databases, access, databases, tenantService, databases, principal);
    auto http = new HTTPServerSettings;
    http.port = 0;
    http.bindAddresses = ["127.0.0.1"];
    auto listener = listenHTTP(http, router);
    auto base = "http://127.0.0.1:" ~ listener.bindAddresses[0].port.to!string ~ "/";

    import uim.hdb.testing : runInEventLoop;

    auto failure = runInEventLoop({
        auto client(I)(string token) {
            auto c = new RestInterfaceClient!I(base);
            c.requestFilter = (HTTPClientRequest r) @safe {
                if (token.length)
                    r.headers["Authorization"] = "Bearer " ~ token;
            };
            return c;
        }

        int statusOf(void delegate() @safe call) {
            auto e = collectException!RestException(call());
            assert(e !is null);
            return e.status;
        }

        // Ohne Token ist nur health erreichbar
        assert(client!ISystemRestApi("").health().status == "UP");
        assert(statusOf({ client!ISystemRestApi("").stats(); }) == 401);
        assert(statusOf({ client!ISqlRestApi("").execute("SELECT 1", "", ""); }) == 401);
        assert(statusOf({ client!ITableRestApi("forged").list(); }) == 401);
        assert(statusOf({ client!IAuthRestApi("").login("root", "wrong-password"); }) == 401);

        auto token = client!IAuthRestApi("").login("root", "correct-horse-root").token;
        auto system = client!ISystemRestApi(token);
        auto tables = client!ITableRestApi(token);
        auto sql = client!ISqlRestApi(token);
        auto users = client!IUserRestApi(token);
        assert(client!IAuthRestApi(token).me().role == "admin");

        auto info = tables.create("t", [RestColumnDef("id", "integer"), RestColumnDef("n", "VARCHAR"), RestColumnDef("w", "DECIMAL")]);
        assert(info.columns.length == 3 && info.columns[0].type == "INTEGER");
        assert(tables.list() == ["t"]);

        assert(tables.insert("t", [Json(1), Json("it's; DROP TABLE t"), Json(1234567.891)]).affected == 1);
        assert(tables.insert("t", [Json(2), Json(null), Json(2)]).affected == 1);
        auto page = tables.rows("t", "id >= 1", "id", true, 1, 0);
        assert(page.total == 2 && page.rows.length == 1 && page.rows[0][0].get!long == 2 && page.rows[0][1].type.isNull);
        assert(tables.rows("t", "", "", false, 100, 0).rows[0][1].get!string == "it's; DROP TABLE t");

        auto tx = sql.execute("BEGIN", "", "").transaction;
        assert(tx.length);
        sql.execute("DELETE FROM t", tx, "");
        sql.execute("ROLLBACK", "", tx); // Id über den Header
        assert(sql.execute("SELECT COUNT(*) FROM t", "", "").rows[0][0].get!long == 2);

        int status;
        auto merge = system.startMerge(status).status;
        assert(status == 202 && (merge == "STARTED" || merge == "RUNNING"));
        assert(system.checkpoint().status == "CHECKPOINTED");

        assert(statusOf({ tables.info("missing"); }) == 404);
        assert(statusOf({ sql.execute("SELECT nope FROM t", "", ""); }) == 400);
        assert(statusOf({ tables.insert("t", [Json("x"), Json("y"), Json(1)]); }) == 400);
        assert(statusOf({ tables.insert("t", [Json(1)]); }) == 400);
        assert(statusOf({ tables.rows("t", "", "evil; DROP", false, 10, 0); }) == 400);
        assert(statusOf({ tables.rows("t", "", "", false, 100_000, 0); }) == 400);
        assert(statusOf({ tables.create("a;b", [RestColumnDef("x", "INTEGER")]); }) == 400);
        assert(statusOf({ tables.create("b", [RestColumnDef("x", "INTEGER")], "DISK"); }) == 400);
        // Der Mandant hat eine echte Dateiablage: FILE-Tabellen gehen
        assert(tables.create("b", [RestColumnDef("x", "INTEGER")], "FILE").storage == "FILE");
        assert(exists(buildPath(dataDir, "default", "tables", "file")));
        tables.drop("b");

        // Rollen über dieselben Endpunkte
        assert(users.create("vera", "correct-horse-vera", "viewer").role == "viewer");
        auto viewerToken = client!IAuthRestApi("").login("vera", "correct-horse-vera").token;
        auto viewerTables = client!ITableRestApi(viewerToken);
        assert(viewerTables.rows("t", "", "", false, 10, 0).total == 2);
        assert(statusOf({ viewerTables.insert("t", [Json(3), Json("x"), Json(1)]); }) == 403);
        assert(statusOf({ viewerTables.drop("t"); }) == 403);
        assert(statusOf({ client!ISystemRestApi(viewerToken).checkpoint(); }) == 403);
        assert(statusOf({ client!IUserRestApi(viewerToken).list(); }) == 403);
        assert(statusOf({ client!ISqlRestApi(viewerToken).execute("DROP TABLE t", "", ""); }) == 403);

        users.update("vera", "editor", true);
        assert(viewerTables.insert("t", [Json(3), Json("x"), Json(1)]).affected == 1);
        users.remove("vera");
        assert(statusOf({ viewerTables.list(); }) == 401);
        assert(statusOf({ users.remove("root"); }) == 400); // letzter Administrator

        // Sicherung über dieselbe Schnittstelle, nur für Administratoren
        auto backups = client!IBackupRestApi(token);
        assert(statusOf({ client!IBackupRestApi(viewerToken).list(); }) == 401); // vera ist gelöscht
        auto saved = backups.create("rest");
        assert(saved.tables == 1 && backups.list().length == 1);
        tables.insert("t", [Json(99), Json("später"), Json(1)]);
        assert(backups.restore(saved.name).safetyBackup.label == "before-restore");
        assert(tables.rows("t", "id = 99", "", false, 10, 0).total == 0);
        assert(statusOf({ backups.restore("missing.hdbbak"); }) == 404);
        assert(statusOf({ backups.remove("../x.hdbbak"); }) == 404);
        assert(backups.remove(saved.name).status == "DELETED");

        // RBAC über die API: eigene Rolle, Benutzer ohne Rolle, Zugriff nur auf freigegebene Tabellen
        tables.create("hidden", [RestColumnDef("x", "INTEGER")]);
        auto clerk = users.saveRole("clerk", ["select", "insert"], "Enters rows");
        assert(clerk.permissions == ["select", "insert"] && !clerk.builtin);
        assert(users.roles().map!(r => r.name).array == ["viewer", "editor", "admin", "clerk"]);
        assert(statusOf({ users.saveRole("admin", ["select"]); }) == 400);
        assert(statusOf({ users.saveRole("bad", ["manageTenants"]); }) == 400);
        users.create("tina", "correct-horse-tina", "");
        auto granted = users.setGrants("tina", [RestGrant("T", "clerk")]);
        assert(granted.grants == [RestGrant("t", "clerk", "", "", "active")] && granted.role == "");
        auto tinaToken = client!IAuthRestApi("").login("tina", "correct-horse-tina").token;
        auto tinaMe = client!IAuthRestApi(tinaToken).me();
        assert(tinaMe.permissions.length == 0 && tinaMe.tables == [RestTableAccess("t", ["select", "insert"])]);
        auto tinaTables = client!ITableRestApi(tinaToken);
        assert(tinaTables.list() == ["t"]); // hidden bleibt verborgen
        assert(tinaTables.insert("t", [Json(50), Json("tina"), Json(1)]).affected == 1);
        // verborgen wie nicht vorhanden: 404, die Existenz wird nicht verraten
        assert(statusOf({ tinaTables.rows("hidden", "", "", false, 10, 0); }) == 404);
        assert(statusOf({ tinaTables.rows("nothere", "", "", false, 10, 0); }) == 404);
        assert(statusOf({ tinaTables.drop("t"); }) == 403);
        assert(statusOf({ client!ISqlRestApi(tinaToken).execute("SELECT * FROM t JOIN hidden h ON t.id = h.x", "", ""); }) == 403);
        assert(statusOf({ client!ISqlRestApi(tinaToken).execute("DELETE FROM t", "", ""); }) == 403);
        assert(statusOf({ client!IUserRestApi(tinaToken).roles(); }) == 403);
        assert(client!IAuthRestApi(token).me().permissions.length == 16); // admin: alle Mandantenrechte
        assert(statusOf({ users.removeRole("clerk"); }) == 400); // noch verwendet
        users.setGrants("tina", []);
        assert(tinaTables.list().length == 0); // ohne Freigaben sieht sie nichts
        users.remove("tina");
        assert(users.removeRole("clerk").status == "DELETED");
        tables.drop("hidden");
        tables.rows("t", "id = 50", "", false, 10, 0); // die Zeile von tina ist da
        sql.execute("DELETE FROM t WHERE id = 50", "", "");

        // Mandanten: nur der Systemadministrator verwaltet sie und sieht keine Daten
        assert(statusOf({ client!ITenantRestApi(token).list(); }) == 403);
        auto sysToken = client!IAuthRestApi("").login("sys", "correct-horse-sys1", "system").token;
        assert(client!IAuthRestApi(sysToken).me().tenant == "system");
        assert(statusOf({ client!ITableRestApi(sysToken).list(); }) == 403);
        assert(statusOf({ client!IBackupRestApi(sysToken).list(); }) == 403);
        assert(statusOf({ client!ISqlRestApi(sysToken).execute("SELECT 1", "", ""); }) == 403);
        auto tenantsApi = client!ITenantRestApi(sysToken);
        auto acme = tenantsApi.create("acme", "boss", "correct-horse-acme", "Acme Corp");
        assert(acme.name == "acme" && acme.label == "Acme Corp" && acme.active && acme.users == 1);
        assert(tenantsApi.list().map!(t => t.name).array == ["acme", "default"]);
        assert(statusOf({ tenantsApi.create("acme", "boss", "correct-horse-acme"); }) == 400);
        assert(statusOf({ tenantsApi.create("../x", "boss", "correct-horse-acme"); }) == 400);

        // Gleicher Tabellenname, getrennte Daten
        auto acmeToken = client!IAuthRestApi("").login("boss", "correct-horse-acme", "ACME").token;
        assert(client!IAuthRestApi(acmeToken).me().tenant == "acme");
        auto acmeTables = client!ITableRestApi(acmeToken);
        assert(acmeTables.list().length == 0);
        acmeTables.create("t", [RestColumnDef("id", "integer")]);
        acmeTables.insert("t", [Json(42)]);
        assert(acmeTables.rows("t", "", "", false, 10, 0).total == 1);
        assert(tables.rows("t", "", "", false, 10, 0).total == 3);
        assert(client!IUserRestApi(acmeToken).list().map!(u => u.name ~ "@" ~ u.tenant).array == ["boss@acme"]);
        assert(statusOf({ client!IUserRestApi(acmeToken).remove("root"); }) == 400); // nicht gefunden
        assert(statusOf({ client!IAuthRestApi("").login("root", "correct-horse-root", "acme"); }) == 401);
        assert(statusOf({ client!IAuthRestApi("").login("boss", "correct-horse-acme"); }) == 401); // default

        // Deaktivieren beendet die Sitzungen, Löschen entfernt alles
        assert(statusOf({ tenantsApi.remove("acme"); }) == 400);
        assert(!tenantsApi.update("acme", false, "Acme Corp").active);
        assert(statusOf({ acmeTables.list(); }) == 401);
        assert(statusOf({ client!IAuthRestApi("").login("boss", "correct-horse-acme", "acme"); }) == 401);
        assert(tenantsApi.remove("acme").status == "DELETED");
        assert(!exists(buildPath(dataDir, "acme")) && tenantsApi.list().length == 1);
        assert(statusOf({ tenantsApi.update("acme", true); }) == 400);

        assert(tables.drop("t").status == "DROPPED");
        client!IAuthRestApi(token).logout("Bearer " ~ token);
        assert(statusOf({ tables.list(); }) == 401);
    });
    listener.stopListening();
    if (failure !is null)
        throw failure;
}

/// Replikation über echtes HTTP: zwei vollständige Server, das Ziel holt Stand und Änderungen über die REST-API.
unittest {
    import uim.hdb;
    import std.exception : collectException;
    import std.file : exists, rmdirRecurse, tempDir;
    import std.functional : toDelegate;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import vibe.http.server : HTTPServerSettings, listenHTTP;

    static class MemUsers : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.map!"a".array;
        }
    }

    static class MemTenants : ITenantStore {
        Tenant[] saved;
        Tenant[] load() {
            return saved;
        }

        void save(Tenant[] tenants) {
            saved = tenants.map!"a".array;
        }
    }

    struct Server {
        AccessService access;
        TenantDatabases databases;
        string url;
        typeof(listenHTTP(HTTPServerSettings.init, URLRouter.init)) listener;
    }

    auto dataDir = buildPath(tempDir, "hdb-replication-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dataDir))
            rmdirRecurse(dataDir);
    auto principal = toDelegate(&currentPrincipal);

    Server start(string name) {
        Server s;
        auto registry = new TenantRegistry(new MemTenants);
        registry.put(Tenant(defaultTenant, "Default", true));
        s.access = new AccessService(new MemUsers, new OpensslCredentialCrypto, null, &registry.isActive);
        s.access.bootstrap("root", "correct-horse-root");
        auto storage = new FileTenantStorage(buildPath(dataDir, name));
        s.databases = new TenantDatabases(storage, principal, new HttpReplicationClient);
        s.databases.open(defaultTenant);
        auto router = new URLRouter;
        new SecurityGate(s.access).register(router);
        registerHdbRestApi(router, s.databases, s.access, s.databases,
            new TenantService(registry, s.access, s.databases, storage), s.databases, principal);
        auto http = new HTTPServerSettings;
        http.port = 0;
        http.bindAddresses = ["127.0.0.1"];
        s.listener = listenHTTP(http, router);
        s.url = "http://127.0.0.1:" ~ s.listener.bindAddresses[0].port.to!string;
        return s;
    }

    auto primary = start("primary");
    auto replica = start("replica");
    scope (exit) {
        primary.listener.stopListening();
        replica.listener.stopListening();
    }

    import uim.hdb.testing : runInEventLoop;

    auto failure = runInEventLoop({
        auto admin = Principal("root", HdbRole.admin, true, defaultTenant);
        // Auf der Quelle: Daten in allen Speicherarten und ein Benutzer nur zum Lesen für das Ziel
        bindPrincipal(admin);
        primary.databases.execute("CREATE TABLE m (id INTEGER, n VARCHAR)");
        primary.databases.execute("CREATE TABLE f (id INTEGER) USING FILE");
        primary.databases.execute("INSERT INTO m VALUES (1, 'it''s')");
        primary.databases.execute("INSERT INTO f VALUES (10)");
        primary.access.createUser(admin, "repl", "replication-pw1", HdbRole.viewer);

        // Ein Betrachter liest den Strom, darf aber nichts einstellen
        auto viewer = Principal("repl", HdbRole.viewer, true, defaultTenant);
        bindPrincipal(viewer);
        assert(primary.databases.replicationSnapshot().tables.length == 2);
        assert(collectException!AccessDenied(primary.databases.replicationStatus()) !is null);

        // Das Ziel einrichten und abrufen
        bindPrincipal(admin);
        replica.databases.execute("CREATE TABLE stale (x INTEGER)"); // wird vom Stand der Quelle ersetzt
        replica.databases.configureReplica(ReplicationConfig(true, primary.url, "", "repl", "replication-pw1", 1));
        assert(replica.databases.replicationTick().length == 0);
        auto status = replica.databases.replicationStatus();
        assert(status.state == "streaming" && status.replica, status.lastError);
        assert(replica.databases.listTables().sort.array == ["f", "m"]);
        assert(replica.databases.execute("SELECT n FROM m").rows[0][0].get!string == "it's");

        // Das Ziel ist schreibgeschützt, Lesen geht
        assert(collectException!AccessDenied(replica.databases.execute("INSERT INTO m VALUES (2, 'x')")) !is null);
        assert(collectException!AccessDenied(replica.databases.execute("BEGIN")) !is null);

        // Änderungen der Quelle kommen an, auch Transaktionen und Dateitabellen
        primary.databases.execute("INSERT INTO m VALUES (2, 'b')");
        auto tx = primary.databases.execute("BEGIN").transaction;
        primary.databases.executeIn(tx, "UPDATE f SET id = 11 WHERE id = 10");
        primary.databases.executeIn(tx, "DELETE FROM m WHERE id = 1");
        primary.databases.executeIn(tx, "COMMIT");
        primary.databases.execute("DROP TABLE f");
        import core.time : seconds;
        import vibe.core.core : sleep;

        sleep(1.seconds);
        assert(replica.databases.replicationTick().length == 0);
        assert(replica.databases.listTables() == ["m"]);
        assert(replica.databases.execute("SELECT id FROM m").rows.map!(r => r[0].get!long).array == [2]);
        assert(replica.databases.replicationStatus().appliedSequence == primary.databases.replicationChanges(
                primary.databases.replicationStatus().epoch, 0, 500).sequence);

        // Falsches Passwort wird gemeldet; nach dem Stoppen ist das Ziel wieder beschreibbar
        replica.databases.configureReplica(ReplicationConfig(true, primary.url, "", "repl", "wrong-password1", 1));
        auto errors = replica.databases.replicationTick();
        assert(errors.length == 1 && errors[0].canFind("rejected the login"), errors.join);
        replica.databases.stopReplica();
        replica.databases.execute("INSERT INTO m VALUES (3, 'local')");
        assert(replica.databases.execute("SELECT COUNT(*) FROM m").rows[0][0].get!long == 2);
        bindPrincipal(Principal.init);
    });
    if (failure !is null)
        throw failure;
}
