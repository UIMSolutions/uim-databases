/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.unix.controller;

import uim.hdb;

import std.algorithm : map, startsWith;
import std.array : array;
import std.exception : enforce;
import std.string : toUpper;
import vibe.data.json : Json, serializeToJson;

/// Eingehender Adapter: dieselben Pfade und dasselbe JSON wie die REST-API unter /api/v1.
/// Das SecurityGate läuft nur für HTTP, deshalb meldet handle jede Anfrage selbst an. `sql` muss der
/// SecuredSqlUseCase sein: die Rollen prüft er, hier wird nur die Identität gesetzt.
final class UnixController : IUnixController {
    enum root = "/api/v1";
    private ISqlUseCase sql;
    private IAccessUseCase access;

    this(ISqlUseCase sql, IAccessUseCase access) {
        this.sql = sql;
        this.access = access;
    }

    string routePrefix() const {
        return root;
    }

    bool canHandle(IUnixRequest request) {
        return request.path == root || request.path.startsWith(root ~ "/");
    }

    IUnixResponse handle(IUnixRequest request) {
        // Eine Verbindung bedient mehrere Anfragen im selben Task: keine darf die Identität der vorigen erben.
        scope (exit)
            bindPrincipal(Principal.init);
        try {
            bindPrincipal(access.authenticate(tokenOf(request)));
            return route(request);
        } catch (AuthenticationRequired e)
            return UnixResponse.error(401, e.msg);
        catch (AccessDenied e)
            return UnixResponse.error(403, e.msg);
        catch (Exception e)
            return UnixResponse.error(400, e.msg); // Meldungen des Kerns, etwa eine gesperrte Datenbank
    }

    private IUnixResponse route(IUnixRequest request) {
        auto path = request.path.startsWith(root) ? request.path[root.length .. $] : request.path;
        switch (request.method.toUpper ~ " " ~ path) {
        case "GET /health":
            return reply(RestStatus("UP"));
        case "POST /auth/login":
            auto input = objectOf(request);
            auto tenant = input["tenant"].type == Json.Type.string ? input["tenant"].get!string : "";
            auto r = access.login(tenant, textOf(input, "user"), textOf(input, "password"));
            return reply(RestLogin(r.token, r.expiresInSeconds,
                RestUser(r.principal.name, r.principal.role, true, r.principal.tenant)));
        case "POST /auth/logout":
            requireAuthenticated(currentPrincipal());
            access.logout(tokenOf(request));
            return reply(RestStatus("LOGGED_OUT"));
        case "POST /sql":
            auto input = objectOf(request);
            auto transaction = input["transaction"].type == Json.Type.string
                ? input["transaction"].get!string : request.header("X-Transaction-Id");
            return reply(toRest(sql.executeIn(transaction, textOf(input, "statement"))));
        case "GET /tables":
            return reply(sql.listTables());
        case "GET /stats":
            return reply(sql.stats().map!(t => toRest(t)).array);
        case "POST /checkpoint":
            sql.checkpoint();
            return reply(RestStatus("CHECKPOINTED"));
        case "GET /merge":
            return reply(toRest(sql.mergeStatus()));
        case "POST /merge":
            return reply(RestStatus(sql.mergeDeltaAsync() ? "STARTED" : "RUNNING"), 202);
        default:
            return UnixResponse.error(404, "No route for " ~ request.method ~ " " ~ request.path);
        }
    }

    private string tokenOf(IUnixRequest request) {
        return bearerToken(request.header("Authorization"));
    }

    private Json objectOf(IUnixRequest request) {
        auto input = request.json;
        enforce(input.type == Json.Type.object, "JSON object expected");
        return input;
    }

    private string textOf(Json input, string name) {
        enforce(input[name].type == Json.Type.string, "Text field required: " ~ name);
        return input[name].get!string;
    }

    private IUnixResponse reply(T)(T value, int status = 200) {
        return new UnixResponse(status).json(serializeToJson(value));
    }
}

unittest {
    import std.algorithm : canFind;
    import std.functional : toDelegate;
    import vibe.core.core : exitEventLoop, runEventLoop, runTask;
    import vibe.data.json : parseJsonString;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.map!"a".array;
        }
    }

    auto access = new AccessService(new MemStore, new OpensslCredentialCrypto);
    access.bootstrap("root", "correct-horse-root");
    auto controller = new UnixController(new SecuredSqlUseCase(new SqlService(new MemoryTableRepository),
        toDelegate(&currentPrincipal)), access);

    IUnixResponse call(string method, string path, string token = "", string body = null, string transaction = "") {
        auto request = new UnixRequest(method, UnixController.root ~ path, body);
        if (token.length)
            request.setHeader("authorization", "Bearer " ~ token);
        if (transaction.length)
            request.setHeader("X-Transaction-Id", transaction);
        return controller.handle(request);
    }

    IUnixResponse sql(string token, string statement, string transaction = "") {
        return call("POST", "/sql", token, Json(["statement": Json(statement)]).toString, transaction);
    }

    string login(string name, string password) {
        auto r = call("POST", "/auth/login", "", Json(["user": Json(name), "password": Json(password)]).toString);
        assert(r.status == 200);
        return parseJsonString(r.body)["token"].get!string;
    }

    // TaskLocal braucht einen Task
    Throwable failure;
    runTask(() nothrow {
        try {
            assert(controller.routePrefix == "/api/v1");
            assert(controller.canHandle(new UnixRequest("GET", "/api/v1")));
            assert(controller.canHandle(new UnixRequest("GET", "/api/v1/stats")));
            assert(!controller.canHandle(new UnixRequest("GET", "/api/v1x")));
            assert(!controller.canHandle(new UnixRequest("GET", "/admin")));

            // Ohne Token ist nur health und die Anmeldung erreichbar
            assert(call("GET", "/health").status == 200);
            foreach (route; [["GET", "/tables"], ["GET", "/stats"], ["GET", "/merge"], ["POST", "/merge"], ["POST", "/checkpoint"], ["POST", "/auth/logout"]])
                assert(call(route[0], route[1]).status == 401);
            assert(sql("", "SELECT 1").status == 401);
            assert(call("GET", "/tables", "forged").status == 401);
            assert(call("POST", "/auth/login", "", `{"user":"root","password":"wrong-password"}`).status == 401);

            auto root = login("root", "correct-horse-root");

            // Der Mandant ist optional: ohne gilt default, ein anderer Mandant kennt root nicht
            auto withTenant = call("POST", "/auth/login", "", `{"user":"root","password":"correct-horse-root","tenant":"Default"}`);
            assert(withTenant.status == 200 && parseJsonString(withTenant.body)["user"]["tenant"].get!string == "default");
            assert(call("POST", "/auth/login", "", `{"user":"root","password":"correct-horse-root","tenant":"acme"}`).status == 401);
            assert(sql(root, "CREATE TABLE t (id INTEGER, n NUMERIC)").status == 200);
            assert(sql(root, "INSERT INTO t VALUES (1, 12345678901234567890.55)").status == 200);
            assert(call("GET", "/tables", root).body == `["t"]`);
            assert(call("GET", "/tables", root).headers["Content-Type"] == "application/json");

            // Dieselbe Darstellung wie die REST-API: NUMERIC bleibt exakt
            auto selected = parseJsonString(sql(root, "SELECT * FROM t").body);
            assert(selected["columns"].length == 2 && selected["rows"][0][1].get!string == "12345678901234567890.55");
            assert(parseJsonString(call("GET", "/stats", root).body)[0]["storage"].get!string == "MEMORY");

            // Die Identität gilt nur für eine Anfrage, auch auf derselben Verbindung
            assert(currentPrincipal() == Principal.init);
            assert(call("GET", "/tables").status == 401);

            // Rollen entscheidet der Kern
            access.createUser(Principal("root", HdbRole.admin, true, defaultTenant), "vera", "correct-horse-vera", HdbRole.viewer);
            auto vera = login("vera", "correct-horse-vera");
            assert(sql(vera, "SELECT * FROM t").status == 200);
            assert(sql(vera, "INSERT INTO t VALUES (2, 1)").status == 403);
            assert(call("POST", "/checkpoint", vera).status == 403);
            assert(call("POST", "/merge", vera).status == 403);

            // Transaktion über den Header, und das Feld im Body hat Vorrang
            auto transaction = parseJsonString(sql(root, "BEGIN").body)["transaction"].get!string;
            assert(sql(root, "INSERT INTO t VALUES (2, 1)", transaction).status == 200);
            assert(sql(vera, "SELECT * FROM t").status == 400); // gesperrt
            assert(sql(vera, "SELECT * FROM t", transaction).status == 403); // fremde Transaktion
            assert(call("POST", "/sql", root, Json(["statement": Json("ROLLBACK"), "transaction": Json(transaction)]).toString,
                "wrong").status == 200);
            assert(parseJsonString(sql(root, "SELECT COUNT(*) FROM t").body)["rows"][0][0].get!long == 1);

            // Ungültige Eingaben
            assert(call("POST", "/sql", root, "not json").status == 400);
            assert(call("POST", "/sql", root, `["SELECT 1"]`).status == 400);
            assert(call("POST", "/sql", root, `{"statement":5}`).status == 400);
            assert(sql(root, "SELEC").status == 400);
            auto missing = call("GET", "/nope", root);
            assert(missing.status == 404 && parseJsonString(missing.body)["statusMessage"].get!string.canFind("/api/v1/nope"));
            assert(call("DELETE", "/tables", root).status == 404);

            assert(call("POST", "/merge", root).status == 202);
            assert(call("GET", "/merge", root).status == 200);
            assert(call("POST", "/checkpoint", root).status == 200);

            assert(call("POST", "/auth/logout", vera).status == 200);
            assert(call("GET", "/tables", vera).status == 401);
        } catch (Throwable t)
            failure = t;
        try
            exitEventLoop();
        catch (Exception) {
        }
    });
    runEventLoop();
    if (failure !is null)
        throw failure;
}
