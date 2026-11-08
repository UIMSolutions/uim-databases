/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.gui.api;

import std.algorithm : canFind, map;
import std.array : array;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.json : JSONType, JSONValue, parseJSON;
import std.string : strip;
import std.uri : encodeComponent;

@safe:

/// Antwort einer HTTP-Anfrage.
struct HttpReply {
    int status;
    string body;
}

/// Ausgehender Port des Admin-Clients: eine HTTP-Anfrage. In Tests ersetzt ein Fake den echten Transport.
interface IHttpTransport {
    /// Wirft bei Netzfehlern; HTTP-Fehlerstatus kommen als Antwort zurück.
    HttpReply send(string method, string url, string[string] headers, string body);
}

/// Fehler des Servers oder der Verbindung. `status` ist 0, wenn der Server nicht erreichbar war.
class ApiError : Exception {
    int status;

    this(int status, string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        this.status = status;
    }
}

/// Die angemeldete Identität mit ihren Rechten, wie der Server sie auflöst.
struct Me {
    string name, role, tenant;
    string[] permissions;
    string[][string] tables; // Tabellenrechte aus Freigaben

    bool can(string permission) const {
        return permissions.canFind(permission);
    }

    bool isSystem() const {
        return tenant == "system";
    }
}

/// Tabellarisches Ergebnis, alle Werte als Text. `nulls` markiert SQL-NULL.
struct Grid {
    string[] columns;
    string[][] rows;
    bool[][] nulls;
    long total; // bei Zeilenseiten: Treffer insgesamt
}

struct SqlOutcome {
    Grid grid;
    long affected;
    string message;
    string transaction; // von BEGIN
}

struct TableStat {
    string table, storage;
    long rows, deletedRows, columns;
}

struct UserRow {
    string name, role;
    bool active;
    size_t grants;
}

struct BackupRow {
    string name, label, created, kind;
    long size, tables, rows;
    bool readable;
}

struct TenantRow {
    string name, label;
    bool active;
    long users;
    string[] networks;
}

/// Client für die REST-API eines hdb-Servers. Hält das Sitzungstoken; jede Methode ist eine Anfrage.
final class HdbClient {
    private IHttpTransport transport;
    private string base;
    private string token;
    Me me;

    /// `serverUrl` etwa http://localhost:8080; ein Schrägstrich am Ende wird entfernt.
    this(IHttpTransport transport, string serverUrl) {
        this.transport = transport;
        base = serverUrl.strip;
        while (base.length && base[$ - 1] == '/')
            base = base[0 .. $ - 1];
        enforce(base.length > 7 && (base[0 .. 7] == "http://" || (base.length > 8 && base[0 .. 8] == "https://")),
            "The server URL must start with http:// or https://");
    }

    string serverUrl() const {
        return base;
    }

    bool signedIn() const {
        return token.length > 0;
    }

    /// Meldet an und lädt die Rechte. Ein leerer Mandant ist default.
    Me login(string tenant, string user, string password) {
        JSONValue body = ["user": user, "password": password, "tenant": tenant.strip];
        auto reply = call("POST", "/api/v1/auth/login", body, false);
        token = reply["token"].str;
        me = loadMe();
        return me;
    }

    void logout() {
        if (!signedIn)
            return;
        try
            call("POST", "/api/v1/auth/logout");
        catch (ApiError) {
        }
        token = null;
        me = Me.init;
    }

    Me loadMe() {
        auto j = call("GET", "/api/v1/auth/me");
        Me result;
        result.name = j["name"].str;
        result.role = j["role"].str;
        result.tenant = j["tenant"].str;
        result.permissions = strings(j["permissions"]);
        foreach (t; j["tables"].arrayNoRef)
            result.tables[t["table"].str] = strings(t["permissions"]);
        return result;
    }

    void changePassword(string current, string replacement) {
        JSONValue body = ["current": current, "replacement": replacement];
        call("POST", "/api/v1/auth/password", body);
        token = null; // der Server beendet dabei alle Sitzungen
    }

    // Daten

    string[] tables() {
        return strings(call("GET", "/api/v1/tables"));
    }

    /// Eine Seite Zeilen; `where` ist eine SQL-Bedingung wie in der Admin-Konsole.
    Grid rows(string table, string where, long limit, long offset) {
        auto path = format("/api/v1/tables/%s/rows?limit=%s&offset=%s", segment(table), limit, offset);
        if (where.strip.length)
            path ~= "&where=" ~ encodeComponent(where.strip);
        auto j = call("GET", path);
        auto grid = toGrid(j["columns"], j["rows"]);
        grid.total = j["total"].integer;
        return grid;
    }

    SqlOutcome sql(string statement, string transaction = "") {
        JSONValue body = ["statement": statement, "transaction": transaction];
        auto j = call("POST", "/api/v1/sql", body);
        SqlOutcome result;
        result.grid = toGrid(j["columns"], j["rows"]);
        result.affected = j["affected"].integer;
        result.message = j["message"].str;
        result.transaction = j["transaction"].str;
        return result;
    }

    TableStat[] stats() {
        TableStat[] result;
        foreach (t; call("GET", "/api/v1/stats").arrayNoRef)
            result ~= TableStat(t["table"].str, t["storage"].str, t["rows"].integer, t["deletedRows"].integer,
                t["columns"].arrayNoRef.length);
        return result;
    }

    // Benutzer

    UserRow[] users() {
        UserRow[] result;
        foreach (u; call("GET", "/api/v1/users").arrayNoRef)
            result ~= UserRow(u["name"].str, u["role"].str, u["active"].boolean,
                "grants" in u ? u["grants"].arrayNoRef.length : 0);
        return result;
    }

    string[] roles() {
        return call("GET", "/api/v1/roles").arrayNoRef.map!(r => r["name"].str).array;
    }

    void createUser(string name, string password, string role) {
        JSONValue body = ["name": name, "password": password, "role": role];
        call("POST", "/api/v1/users", body);
    }

    void updateUser(string name, string role, bool active) {
        JSONValue body = ["role": JSONValue(role), "active": JSONValue(active)];
        call("PUT", "/api/v1/users/" ~ segment(name), body);
    }

    void resetPassword(string name, string password) {
        JSONValue body = ["password": password];
        call("POST", "/api/v1/users/" ~ segment(name) ~ "/password", body);
    }

    void deleteUser(string name) {
        call("DELETE", "/api/v1/users/" ~ segment(name));
    }

    // Sicherungen

    BackupRow[] backups() {
        BackupRow[] result;
        foreach (b; call("GET", "/api/v1/backups").arrayNoRef)
            result ~= toBackup(b);
        return result;
    }

    BackupRow createBackup(string label) {
        JSONValue body = ["label": label];
        return toBackup(call("POST", "/api/v1/backups", body));
    }

    /// Gibt den Namen der Sicherheitskopie zurück, die vorher angelegt wurde.
    string restoreBackup(string name) {
        return call("POST", "/api/v1/backups/" ~ segment(name) ~ "/restore")["safetyBackup"]["name"].str;
    }

    void deleteBackup(string name) {
        call("DELETE", "/api/v1/backups/" ~ segment(name));
    }

    // Mandanten (nur Bereich system)

    TenantRow[] tenants() {
        TenantRow[] result;
        foreach (t; call("GET", "/api/v1/tenants").arrayNoRef)
            result ~= TenantRow(t["name"].str, t["label"].str, t["active"].boolean, t["users"].integer,
                "networks" in t ? strings(t["networks"]) : null);
        return result;
    }

    void createTenant(string name, string label, string adminName, string adminPassword) {
        JSONValue body = ["name": name, "label": label, "adminName": adminName, "adminPassword": adminPassword];
        call("POST", "/api/v1/tenants", body);
    }

    void updateTenant(string name, string label, bool active) {
        JSONValue body = ["label": JSONValue(label), "active": JSONValue(active)];
        call("PUT", "/api/v1/tenants/" ~ segment(name), body);
    }

    void deleteTenant(string name) {
        call("DELETE", "/api/v1/tenants/" ~ segment(name));
    }

    /// Eine Anfrage mit JSON. Fehler des Servers werden zu ApiError mit seiner Meldung.
    private JSONValue call(string method, string path, JSONValue body = JSONValue.init, bool authenticated = true) {
        string[string] headers;
        if (authenticated) {
            if (!signedIn)
                throw new ApiError(401, "Not signed in");
            headers["Authorization"] = "Bearer " ~ token;
        }
        string payload;
        if (body.type != JSONType.null_) {
            headers["Content-Type"] = "application/json";
            payload = body.toString;
        }
        HttpReply reply;
        try
            reply = transport.send(method, base ~ path, headers, payload);
        catch (ApiError e)
            throw e;
        catch (Exception e)
            throw new ApiError(0, "The server can't be reached: " ~ e.msg);
        if (reply.status == 401 && authenticated)
            token = null; // abgelaufen oder nicht mehr erlaubt: neu anmelden
        if (reply.status < 200 || reply.status >= 300)
            throw new ApiError(reply.status, errorText(reply));
        if (reply.body.strip.length == 0)
            return JSONValue.init;
        try
            return parseJSON(reply.body);
        catch (Exception e)
            throw new ApiError(reply.status, "The server sent an invalid answer: " ~ e.msg);
    }
}

/// Meldung aus einer Fehlerantwort; der Server schickt {"statusMessage": ...}.
private string errorText(HttpReply reply) {
    try {
        auto j = parseJSON(reply.body);
        if (j.type == JSONType.object) {
            if (auto m = "statusMessage" in j)
                return m.str;
            if (auto e = "error" in j) // OData-Format
                return (*e)["message"].str;
        }
    } catch (Exception) {
    }
    return "HTTP " ~ reply.status.to!string;
}

private string[] strings(JSONValue j) {
    return j.arrayNoRef.map!(v => v.str).array;
}

private string segment(string name) {
    return encodeComponent(name);
}

private BackupRow toBackup(JSONValue b) {
    return BackupRow(b["name"].str, b["label"].str, b["created"].str, b["kind"].str, b["size"].integer,
        b["tables"].integer, b["rows"].integer, b["readable"].boolean);
}

/// Werte als Text, wie sie in einer Tabelle erscheinen. Zahlen bleiben so, wie der Server sie schickt.
Grid toGrid(JSONValue columns, JSONValue rows) {
    Grid grid;
    grid.columns = strings(columns);
    foreach (row; rows.arrayNoRef) {
        string[] texts;
        bool[] nulls;
        foreach (v; row.arrayNoRef) {
            nulls ~= v.type == JSONType.null_;
            texts ~= cellText(v);
        }
        grid.rows ~= texts;
        grid.nulls ~= nulls;
    }
    return grid;
}

string cellText(JSONValue v) {
    final switch (v.type) {
    case JSONType.null_:
        return "NULL";
    case JSONType.string:
        return v.str;
    case JSONType.integer:
        return v.integer.to!string;
    case JSONType.uinteger:
        return v.uinteger.to!string;
    case JSONType.float_:
        return format("%.17g", v.floating).shortestDouble(v.floating);
    case JSONType.true_:
        return "true";
    case JSONType.false_:
        return "false";
    case JSONType.array:
    case JSONType.object:
        return v.toString;
    }
}

/// Kürzeste Darstellung, die den double genau wiedergibt (0.3 statt 0.29999999999999999).
private string shortestDouble(string fallback, double value) {
    foreach (digits; 1 .. 18) {
        auto text = format("%.*g", digits, value);
        if (text.to!double == value)
            return text;
    }
    return fallback;
}

unittest {
    import std.exception : assertThrown, collectException;

    static class Fake : IHttpTransport {
        string[] log;
        HttpReply[string] replies; // Schlüssel: "METHODE pfad"
        string lastBody;
        string[string] lastHeaders;

        HttpReply send(string method, string url, string[string] headers, string body) {
            auto key = method ~ " " ~ url["http://db:8080".length .. $];
            log ~= key;
            lastBody = body;
            lastHeaders = headers;
            if (auto r = key in replies)
                return *r;
            return HttpReply(404, `{"statusMessage":"No route"}`);
        }
    }

    auto fake = new Fake;
    fake.replies["POST /api/v1/auth/login"] = HttpReply(200, `{"token":"t1","expiresIn":3600,"user":{}}`);
    fake.replies["GET /api/v1/auth/me"] = HttpReply(200,
        `{"name":"ann","role":"","tenant":"acme","permissions":["select"],"tables":[{"table":"orders","permissions":["insert"]}]}`);
    fake.replies["GET /api/v1/tables/my%20t/rows?limit=50&offset=100&where=a%20%3D%20'x'"] = HttpReply(200,
        `{"columns":["id","price","note"],"rows":[[1,0.3,null],[2,1e21,"it's"]],"total":2,"limit":50,"offset":100}`);
    fake.replies["POST /api/v1/sql"] = HttpReply(400, `{"statusMessage":"Requires permission select on table secret"}`);
    fake.replies["DELETE /api/v1/users/x%2Fy"] = HttpReply(401, `{"statusMessage":"Authentication required"}`);

    assertThrown(new HdbClient(fake, "ftp://db"));
    auto c = new HdbClient(fake, "http://db:8080/");
    assert(c.serverUrl == "http://db:8080" && !c.signedIn);
    assertThrown!ApiError(c.tables()); // nicht angemeldet: keine Anfrage
    assert(fake.log.length == 0);

    auto me = c.login(" acme ", "ann", "pw");
    assert(c.signedIn && me.tenant == "acme" && me.can("select") && !me.can("insert") && me.tables["orders"] == ["insert"]);
    assert(fake.lastHeaders["Authorization"] == "Bearer t1");

    auto page = c.rows("my t", " a = 'x' ", 50, 100);
    assert(page.columns == ["id", "price", "note"] && page.total == 2);
    assert(page.rows == [["1", "0.3", "NULL"], ["2", "1e+21", "it's"]] && page.nulls[0] == [false, false, true]);

    auto e = collectException!ApiError(c.sql("SELECT * FROM secret"));
    assert(e.status == 400 && e.msg == "Requires permission select on table secret");
    assert(fake.lastBody == `{"statement":"SELECT * FROM secret","transaction":""}`);

    // 401: das Token gilt nicht mehr, der Client verlangt eine neue Anmeldung
    e = collectException!ApiError(c.deleteUser("x/y"));
    assert(e.status == 401 && !c.signedIn);

    // Nicht erreichbar
    static class Down : IHttpTransport {
        HttpReply send(string, string, string[string], string) {
            throw new Exception("Connection refused");
        }
    }

    auto down = new HdbClient(new Down, "http://db:8080");
    e = collectException!ApiError(down.login("", "a", "b"));
    assert(e.status == 0 && e.msg == "The server can't be reached: Connection refused");

    // Literale statt 0.1 + 0.2: der Compiler rechnet das mit höherer Genauigkeit und erhält genau 0.3
    assert(cellText(JSONValue(0.30000000000000004)) == "0.30000000000000004");
    assert(cellText(JSONValue(0.3)) == "0.3" && cellText(JSONValue(true)) == "true");
}
