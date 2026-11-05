module uim.hdb.presentation.rest.services;

import uim.hdb.adapters.inbound.admin_web : createTableSql, isIdentifier, selectSql;
import uim.hdb.adapters.inbound.security : bearerToken;
import uim.hdb.application.ports : IAccessUseCase, ISqlUseCase;
import uim.hdb.domain.entities.user;
import uim.hdb.domain.types.tablestats : ColumnStats, TableStats;
import uim.hdb.domain.value;
import uim.hdb.presentation.rest.interfaces;
import uim.hdb.presentation.rest.models;
import std.algorithm : any, map;
import std.array : array, join;
import std.conv : to;
import std.exception : enforce;
import std.string : icmp, toUpper;
import vibe.data.json : Json;
import vibe.http.common : HTTPStatusException;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.web.rest : registerRestInterface, RestErrorInformation, RestInterfaceSettings;

private enum long maxRowLimit = 1000;

final class SystemRestApi : ISystemRestApi {
    // vibe verlangt @safe, der Anwendungskern (ISqlUseCase) ist es nicht
@trusted:
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
    // vibe verlangt @safe, der Anwendungskern (ISqlUseCase) ist es nicht
@trusted:
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    RestSqlResult execute(string statement, string transaction, string headerTransaction) {
        return toRest(sql.executeIn(transaction.length ? transaction : headerTransaction, statement));
    }
}

final class TableRestApi : ITableRestApi {
    // vibe verlangt @safe, der Anwendungskern (ISqlUseCase) ist es nicht
@trusted:
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
    private Principal delegate() current;

    this(IAccessUseCase access, Principal delegate() current) {
        this.access = access;
        this.current = current;
    }

    // vibe verlangt @safe, der Anwendungskern (IAccessUseCase) ist es nicht
@trusted:
    RestLogin login(string user, string password) {
        auto r = access.login(user, password);
        return RestLogin(r.token, r.expiresInSeconds, RestUser(r.principal.name, roleName(r.principal.role), true));
    }

    RestStatus logout(string authorization) {
        access.logout(bearerToken(authorization));
        return RestStatus("LOGGED_OUT");
    }

    RestUser me() {
        auto p = current();
        requireRole(p, Role.viewer);
        return RestUser(p.name, roleName(p.role), true);
    }

    RestStatus changePassword(string oldPassword, string replacement) {
        access.changeOwnPassword(current(), oldPassword, replacement);
        return RestStatus("PASSWORD_CHANGED");
    }
}

final class UserRestApi : IUserRestApi {
    private IAccessUseCase access;
    private Principal delegate() current;

    this(IAccessUseCase access, Principal delegate() current) {
        this.access = access;
        this.current = current;
    }

@trusted:
    RestUser[] list() {
        return access.listUsers(current()).map!(u => toRest(u)).array;
    }

    RestUser create(string name, string password, string role) {
        return toRest(access.createUser(current(), name, password, parseRole(role)));
    }

    RestUser update(string _name, string role, bool active) {
        return toRest(access.updateUser(current(), _name, parseRole(role), active));
    }

    RestStatus resetPassword(string _name, string password) {
        access.resetPassword(current(), _name, password);
        return RestStatus("PASSWORD_RESET");
    }

    RestStatus remove(string _name) {
        access.deleteUser(current(), _name);
        return RestStatus("DELETED");
    }
}

/// SQL-Literal eines JSON-Werts, geprüft gegen den Spaltentyp; Eingaben gelangen nie ungequotet in die Anweisung.
string jsonLiteral(ColumnStats column, Json value) {
    final switch (value.type) with (Json.Type) {
    case null_:
        return "NULL";
    case string:
        enforce(column.type == ColumnType.text, "Column " ~ column.name ~ " expects a number");
        return toSqlLiteral(Value(value.get!(.string)));
    case int_:
    case bigInt:
        return toSqlLiteral(valueFromInput(column.type, value.to!(.string)));
    case float_:
        enforce(column.type != ColumnType.integer, "Column " ~ column.name ~ " expects an integer");
        return toSqlLiteral(valueFromInput(column.type, exactText(value.get!double)));
    case undefined:
    case bool_:
    case array:
    case object:
        throw new Exception("Unsupported value for column " ~ column.name);
    }
}

/// Registriert alle REST-Schnittstellen. Fehler der Eingabe (ungültiges SQL, gesperrte Datenbank) ergeben 400
/// wie bei POST /sql; HTTPStatusException behält ihren Status. Stacktraces gelangen nicht in die Antwort.
void registerHdbRestApi(URLRouter router, ISqlUseCase sql, IAccessUseCase access, Principal delegate() current) {
    auto settings = new RestInterfaceSettings;
    settings.errorHandler = (HTTPServerRequest req, HTTPServerResponse res, RestErrorInformation error) @trusted {
        if (cast(AuthenticationRequired) error.exception)
            res.statusCode = HTTPStatus.unauthorized;
        else if (cast(AccessDenied) error.exception)
            res.statusCode = HTTPStatus.forbidden;
        else
            res.statusCode = cast(HTTPStatusException) error.exception ? error.statusCode : HTTPStatus.badRequest;
        res.writeJsonBody(["statusMessage": error.exception.msg]);
    };
    router.registerRestInterface!ISystemRestApi(new SystemRestApi(sql), settings);
    router.registerRestInterface!ISqlRestApi(new SqlExecutionRestApi(sql), settings);
    router.registerRestInterface!ITableRestApi(new TableRestApi(sql), settings);
    router.registerRestInterface!IAuthRestApi(new AuthRestApi(access, current), settings);
    router.registerRestInterface!IUserRestApi(new UserRestApi(access, current), settings);
}

/// Echter Durchlauf über HTTP mit den aus den Schnittstellen generierten Clients, inklusive Gate und Rollen.
unittest {
    import uim.hdb.adapters.inbound.security : currentPrincipal, SecurityGate;
    import uim.hdb.infrastructure.repositories.memory : MemoryTableRepository;
    import uim.hdb.adapters.outbound.openssl_credential_crypto : OpensslCredentialCrypto;
    import uim.hdb.application.access_service : AccessService;
    import uim.hdb.application.ports : IUserStore;
    import uim.hdb.application.secured_sql : SecuredSqlUseCase;
    import uim.hdb.application.sql_service : SqlService;
    import std.exception : collectException;
    import std.functional : toDelegate;
    import vibe.core.core : exitEventLoop, runEventLoop, runTask;
    import vibe.http.client : HTTPClientRequest;
    import vibe.http.server : HTTPServerSettings, listenHTTP;
    import vibe.web.rest : RestException, RestInterfaceClient;

    static class MemStore : IUserStore {
        User[] saved;
        User[] load() {
            return saved;
        }

        void save(User[] users) {
            saved = users.dup;
        }
    }

    auto access = new AccessService(new MemStore, new OpensslCredentialCrypto);
    access.bootstrap("root", "correct-horse-root");
    auto principal = toDelegate(&currentPrincipal);
    auto router = new URLRouter;
    new SecurityGate(access).register(router);
    registerHdbRestApi(router, new SecuredSqlUseCase(new SqlService(new MemoryTableRepository), principal), access, principal);
    auto http = new HTTPServerSettings;
    http.port = 0;
    http.bindAddresses = ["127.0.0.1"];
    auto listener = listenHTTP(http, router);
    auto base = "http://127.0.0.1:" ~ listener.bindAddresses[0].port.to!string ~ "/";

    Throwable failure;
    runTask(() nothrow {
        try {
            auto client(I)(string token) {
                auto c = new RestInterfaceClient!I(base);
                c.requestFilter = (HTTPClientRequest r) @safe {
                    if (token.length)
                        r.headers["Authorization"] = "Bearer " ~ token;
                };
                return c;
            }

            int statusOf(void delegate() call) {
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
            assert(page.total == 2 && page.rows.length == 1 && page.rows[0][0].get!long == 2 && page.rows[0][1].type == Json.Type.null_);
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
            assert(statusOf({ tables.create("b", [RestColumnDef("x", "INTEGER")], "FILE"); }) == 400); // Repository ohne Dateien

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

            assert(tables.drop("t").status == "DROPPED");
            client!IAuthRestApi(token).logout("Bearer " ~ token);
            assert(statusOf({ tables.list(); }) == 401);
        } catch (Throwable t)
            failure = t;
        try
            exitEventLoop();
        catch (Exception) {
        }
    });
    runEventLoop();
    listener.stopListening();
    if (failure !is null)
        throw failure;
}
