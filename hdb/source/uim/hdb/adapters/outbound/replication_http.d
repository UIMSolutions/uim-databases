module uim.hdb.adapters.outbound.replication_http;

import uim.hdb;
import core.time : seconds;
import std.algorithm : canFind;
import std.conv : octal, to;
import std.exception : enforce;
import std.file : exists, mkdirRecurse, readText, rename, setAttributes;
import std.path : dirName;
import std.stdio : File;
import std.string : toLower;
import vibe.data.json : Json, parseJsonString;
import vibe.http.client : HTTPClientRequest, HTTPClientResponse, HTTPClientSettings, requestHTTP;
import vibe.http.common : HTTPMethod;
import vibe.inet.url : URL;
import vibe.stream.operations : readAllUTF8;
import vibe.textfilter.urlencode : urlEncode;

@safe:

/// Ausgehender Adapter: ein Ziel ruft seine Quelle über deren REST-API ab, wie jeder andere Client.
/// Antworten gelten als nicht vertrauenswürdig: der Stand wird wie eine hochgeladene Sicherung vollständig geprüft.
final class HttpReplicationClient : IReplicationClient {
    private string[] allowedHosts;
    private HTTPClientSettings settings;

    /// `allowedHosts` leer: jede Quelle ist erlaubt. Sonst nur diese Hosts (ohne Port, klein geschrieben);
    /// das verhindert, dass ein Mandanten-Admin den Server beliebige interne Adressen abfragen lässt.
    this(string[] allowedHosts = null) {
        foreach (h; allowedHosts)
            if (h.length)
                this.allowedHosts ~= h.toLower;
        settings = new HTTPClientSettings;
        settings.connectTimeout = 10.seconds;
        settings.readTimeout = 120.seconds;
    }

    void validate(string url) {
        URL parsed;
        try
            parsed = URL(url);
        catch (Exception)
            throw new Exception("Invalid source URL: " ~ url);
        enforce(parsed.schema == "http" || parsed.schema == "https", "The source URL must use http or https");
        enforce(parsed.username.length == 0 && parsed.password.length == 0,
            "Put the user name and password in their own fields, not in the URL");
        enforce(parsed.queryString.length == 0 && parsed.anchor.length == 0, "The source URL can't have a query or fragment");
        enforce(allowedHosts.length == 0 || allowedHosts.canFind(parsed.host.toLower),
            "Replication from " ~ parsed.host ~ " is not allowed on this server (REPLICATION_ALLOWED_HOSTS)");
    }

    string login(string url, string tenant, string user, string password) {
        validate(url);
        auto body_ = Json.emptyObject;
        body_["tenant"] = tenant;
        body_["user"] = user;
        body_["password"] = password;
        string token;
        call(url ~ "/api/v1/auth/login", "", (scope HTTPClientRequest req) {
            req.method = HTTPMethod.POST;
            req.writeJsonBody(body_);
        }, (string text, scope HTTPClientResponse res) {
            auto j = parseJsonString(text);
            enforce(j["token"].isString, "The source sent no session token");
            token = j["token"].get!string;
        });
        return token;
    }

    ReplicationSnapshot snapshot(string url, string token) {
        validate(url);
        ReplicationSnapshot result;
        call(url ~ "/api/v1/replication/snapshot", token, null, (string text, scope HTTPClientResponse res) {
            result.epoch = res.headers.get("X-Hdb-Epoch", "");
            enforce(result.epoch.length, "The source sent no epoch");
            result.sequence = res.headers.get("X-Hdb-Sequence", "").to!ulong;
            result.tables = decodeSnapshot(text);
        });
        return result;
    }

    ChangeBatch changes(string url, string token, string epoch, ulong since, size_t limit) {
        validate(url);
        ChangeBatch batch;
        auto target = url ~ "/api/v1/replication/changes?epoch=" ~ urlEncode(epoch) ~ "&since=" ~ since.to!string
            ~ "&max=" ~ limit.to!string;
        call(target, token, null, (string text, scope HTTPClientResponse res) {
            batch = parseChangeBatch(text);
        });
        return batch;
    }

    /// Fehler der Quelle: 401 wird zu AuthenticationRequired (neu anmelden), alles andere zu einer Meldung.
    private void call(string target, string token, scope void delegate(scope HTTPClientRequest) @safe prepare,
        scope void delegate(string, scope HTTPClientResponse) @safe read) {
        requestHTTP(target, (scope HTTPClientRequest req) {
            if (token.length)
                req.headers["Authorization"] = "Bearer " ~ token;
            if (prepare !is null)
                prepare(req);
        }, (scope HTTPClientResponse res) {
            auto text = res.bodyReader.readAllUTF8();
            if (res.statusCode == 401)
                throw new AuthenticationRequired("The source rejected the login: " ~ messageOf(text, res.statusCode));
            enforce(res.statusCode >= 200 && res.statusCode < 300,
                "The source answered " ~ res.statusCode.to!string ~ ": " ~ messageOf(text, res.statusCode));
            read(text, res);
        }, settings);
    }
}

/// Liest eine Antwort von GET /api/v1/replication/changes; alles, was nicht passt, ist ein Fehler.
ChangeBatch parseChangeBatch(string text) {
    auto j = parseJsonString(text);
    ChangeBatch batch;
    batch.epoch = j["epoch"].get!string;
    batch.sequence = j["sequence"].get!long.to!ulong;
    batch.resync = j["resync"].get!bool;
    foreach (c; j["changes"].byValue) {
        Change change;
        change.sequence = c["sequence"].get!long.to!ulong;
        foreach (st; c["statements"].byValue)
            change.statements ~= st.get!string;
        enforce(change.statements.length, "Empty change from the source");
        batch.changes ~= change;
    }
    return batch;
}

/// Gegenstück zu parseChangeBatch.
Json changeBatchJson(ChangeBatch batch) {
    auto changes = Json.emptyArray;
    foreach (c; batch.changes) {
        auto statements = Json.emptyArray;
        foreach (st; c.statements)
            statements ~= Json(st);
        auto j = Json.emptyObject;
        j["sequence"] = cast(long) c.sequence;
        j["statements"] = statements;
        changes ~= j;
    }
    auto j = Json.emptyObject;
    j["epoch"] = batch.epoch;
    j["sequence"] = cast(long) batch.sequence;
    j["resync"] = batch.resync;
    j["changes"] = changes;
    return j;
}

private string messageOf(string text, int status) {
    try {
        auto j = parseJsonString(text);
        if (j["statusMessage"].isString)
            return j["statusMessage"].get!string;
    } catch (Exception) {
    }
    return "HTTP " ~ status.to!string;
}

/// Ausgehender Adapter: Einstellungen der Replikation eines Mandanten als JSON-Datei. Sie enthält das Passwort
/// für die Quelle und ist deshalb nur für den Besitzer lesbar.
final class FileReplicationConfigStore : IReplicationConfigStore {
    private string path;

    this(string path) {
        this.path = path;
    }

    ReplicationConfig load() {
        ReplicationConfig c;
        if (!exists(path))
            return c;
        auto j = parseJsonString(readText(path));
        c.enabled = j["enabled"].get!bool;
        c.url = j["url"].get!string;
        c.tenant = j["tenant"].get!string;
        c.user = j["user"].get!string;
        c.password = j["password"].get!string;
        c.intervalSeconds = j["intervalSeconds"].get!int;
        return c;
    }

    void save(ReplicationConfig c) {
        auto j = Json.emptyObject;
        j["enabled"] = c.enabled;
        j["url"] = c.url;
        j["tenant"] = c.tenant;
        j["user"] = c.user;
        j["password"] = c.password;
        j["intervalSeconds"] = c.intervalSeconds;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        setAttributes(tmp, octal!600); // vor dem Schreiben: das Passwort ist nie für andere lesbar
        f.write(j.toPrettyString());
        f.flush();
        f.close();
        rename(tmp, path);
    }
}

unittest {
    import std.exception : assertThrown;
    import std.file : getAttributes, remove, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto open = new HttpReplicationClient;
    open.validate("http://primary:8080");
    open.validate("https://db.example.org/hdb");
    assertThrown(open.validate("ftp://primary"));
    assertThrown(open.validate("http://user:pw@primary"));
    assertThrown(open.validate("http://primary/?x=1"));
    assertThrown(open.validate("not a url"));
    auto limited = new HttpReplicationClient(["Primary.example.org", ""]);
    limited.validate("https://primary.example.org:8443");
    assertThrown(limited.validate("http://169.254.169.254"));

    auto batch = ChangeBatch("e1", 7, false, [Change(6, ["INSERT INTO t VALUES (1)"]), Change(7, ["A", "B"])]);
    assert(parseChangeBatch(changeBatchJson(batch).toString) == batch);
    assertThrown(parseChangeBatch(`{"epoch":"e","sequence":1,"resync":false,"changes":[{"sequence":1,"statements":[]}]}`));
    assertThrown(parseChangeBatch(`{"epoch":"e"}`));

    auto path = buildPath(tempDir, "hdb-replication-" ~ randomUUID().toString, "replication.json");
    scope (exit)
        if (exists(dirName(path)))
            rmdirRecurse(dirName(path));
    auto store = new FileReplicationConfigStore(path);
    assert(!store.load().enabled);
    auto config = ReplicationConfig(true, "http://p", "acme", "repl", "secret-password", 3);
    store.save(config);
    assert(store.load() == config);
    assert((getAttributes(path) & octal!777) == octal!600);
}
