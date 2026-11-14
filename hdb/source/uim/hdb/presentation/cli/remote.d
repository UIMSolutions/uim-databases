/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Client-Betrieb der Kommandozeile: ISqlUseCase über den Unix Domain Socket eines laufenden Servers
/// (UNIX_SOCKET, siehe uim.hdb.presentation.unix). Anmeldung, Rollen und Audit gelten wie über HTTP.
module uim.hdb.presentation.cli.remote;

import uim.hdb;

import core.time : msecs;
import std.algorithm : map;
import std.array : appender, array;
import std.conv : ConvException, to;
import std.exception : enforce;
import std.string : icmp, indexOf, lineSplitter, startsWith, strip;
import vibe.data.json : Json, parseJsonString;

@safe:

/// Schickt eine Nachricht im Protokoll des Unix-Sockets und liefert die ganze Antwort (Statuszeile, Header, Body).
interface ICliTransport {
    string exchange(string message);
    void close();
}

/// Antwort des Servers.
struct CliReply {
    int status;
    string body;

    bool ok() const {
        return status >= 200 && status < 300;
    }

    Json json() const {
        if (body.length == 0)
            return Json(null);
        try
            return parseJsonString(body);
        catch (Exception)
            return Json(null);
    }
}

/// Der Server hat abgelehnt oder ist gescheitert; `status` wie bei HTTP.
class RemoteError : Exception {
    int status;

    this(int status, string message) {
        super(message);
        this.status = status;
    }
}

/// Anfrage im Format des Unix-Sockets: "METHODE pfad", Header, Leerzeile, Body.
string requestWire(string method, string path, string token, string body) {
    auto result = appender!string;
    result.put(method ~ " " ~ path ~ "\n");
    if (token.length)
        result.put("Authorization: Bearer " ~ token ~ "\n");
    if (body.length)
        result.put("Content-Type: application/json\n");
    result.put("Content-Length: " ~ body.length.to!string ~ "\n\n");
    result.put(body);
    return result.data;
}

/// Liest eine Antwort: Zeile "STATUS code", Header, Leerzeile, Body.
CliReply parseReply(string wire) {
    auto end = wire.indexOf("\n\n");
    auto crlf = wire.indexOf("\r\n\r\n");
    size_t bodyStart;
    if (crlf >= 0 && (end < 0 || crlf < end)) {
        bodyStart = crlf + 4;
        end = crlf;
    } else {
        enforce(end >= 0, "Incomplete reply from the server");
        bodyStart = end + 2;
    }
    auto head = wire[0 .. end];
    auto lines = head.lineSplitter;
    enforce(!lines.empty && lines.front.startsWith("STATUS "), "Invalid reply from the server");
    int status;
    try
        status = lines.front["STATUS ".length .. $].strip.to!int;
    catch (ConvException)
        throw new Exception("Invalid status in reply from the server");
    return CliReply(status, wire[bodyStart .. $]);
}

/// ISqlUseCase über den Socket. Das Token kommt aus `login` oder von außen (HDB_TOKEN).
final class RemoteSqlClient : ISqlUseCase {
    enum root = "/api/v1";
    private ICliTransport transport;
    private string _token;
    /// Pause zwischen zwei Abfragen des Delta-Merge in `mergeDelta`; austauschbar für Tests.
    void delegate() @safe pause;

    this(ICliTransport transport, string token = "") {
        this.transport = transport;
        _token = token;
        pause = () => sleepBriefly();
    }

    string token() const {
        return _token;
    }

    /// Meldet an und merkt sich das Token. `tenant` leer bedeutet default. Gibt den Mandanten der Anmeldung zurück.
    string login(string tenant, string user, string password) {
        auto input = Json(["user": Json(user), "password": Json(password)]);
        if (tenant.length)
            input["tenant"] = tenant;
        auto reply = call("POST", "/auth/login", input.toString, false);
        _token = textOf(reply.json, "token");
        auto u = reply.json["user"];
        return u.type == Json.Type.object && u["tenant"].isString ? u["tenant"].get!string : "";
    }

    /// Beendet die Sitzung; ohne Token passiert nichts.
    void logout() {
        if (_token.length == 0)
            return;
        scope (exit)
            _token = null;
        call("POST", "/auth/logout");
    }

    /// true, wenn der Server antwortet (ohne Anmeldung).
    bool healthy() {
        return call("GET", "/health", null, false).ok;
    }

    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto input = Json(["statement": Json(sql)]);
        if (txId.length)
            input["transaction"] = txId;
        auto r = call("POST", "/sql", input.toString).json;
        enforce(r.type == Json.Type.object, "Invalid result from the server");
        QueryResult result;
        if (r["columns"].isArray)
            foreach (c; r["columns"].toArray)
                result.columns ~= c.isString ? c.get!string : c.toString;
        if (r["rows"].isArray)
            foreach (row; r["rows"]) {
                Value[] values;
                if (row.isArray)
                    values = row.toArray.map!(cell => valueOf(cell)).array;
                result.rows ~= values;
            }
        result.affected = longOf(r["affected"]);
        result.message = r["message"].isString ? r["message"].get!string : "";
        result.transaction = r["transaction"].isString ? r["transaction"].get!string : "";
        return result;
    }

    string[] listTables() {
        auto r = call("GET", "/tables").json;
        enforce(r.isArray, "Invalid table list from the server");
        return r.toArray.map!(t => t.get!string).array;
    }

    void checkpoint() {
        call("POST", "/checkpoint");
    }

    /// Stößt den Merge an und wartet, bis er fertig ist. Ein Fehler des Merge steht danach in mergeStatus.
    void mergeDelta() {
        mergeDeltaAsync();
        while (mergeStatus().running)
            pause();
    }

    bool mergeDeltaAsync() {
        auto r = call("POST", "/merge").json;
        return r["status"].isString && r["status"].get!string == "STARTED";
    }

    MergeStatus mergeStatus() {
        auto r = call("GET", "/merge").json;
        enforce(r.isObject, "Invalid merge status from the server");
        return MergeStatus(r["running"].isBoolean && r["running"].get!bool,
            cast(size_t) longOf(r["completed"]),
            r["lastError"].isString ? r["lastError"].get!string : "");
    }

    TableStats[] stats() {
        auto r = call("GET", "/stats").json;
        enforce(r.isArray, "Invalid statistics from the server");
        TableStats[] result;
        foreach (t; r) {
            TableStats s;
            s.table = textOf(t, "table");
            s.storage = parseStorage(textOf(t, "storage"));
            s.rows = cast(size_t) longOf(t["rows"]);
            s.deletedRows = cast(size_t) longOf(t["deletedRows"]);
            if (t["columns"].isArray)
                foreach (c; t["columns"].toArray) {
                    ColumnStats column;
                    column.name = textOf(c, "name");
                    column.type = parseTypeName(textOf(c, "type"));
                    column.rows = cast(size_t) longOf(c["rows"]);
                    column.mainRows = cast(size_t) longOf(c["mainRows"]);
                    column.deltaRows = cast(size_t) longOf(c["deltaRows"]);
                    column.mainDistinct = cast(size_t) longOf(c["mainDistinct"]);
                    column.deltaDistinct = cast(size_t) longOf(c["deltaDistinct"]);
                    column.mainBits = cast(uint) longOf(c["mainBits"]);
                    column.mainCodeBytes = cast(size_t) longOf(c["mainCodeBytes"]);
                    s.columns ~= column;
                }
            result ~= s;
        }
        return result;
    }

    void close() {
        transport.close();
    }

    private CliReply call(string method, string path, string body = null, bool authenticated = true) {
        auto reply = parseReply(transport.exchange(requestWire(method, root ~ path, authenticated ? _token : null,
                body)));
        if (reply.ok)
            return reply;
        auto j = reply.json;
        auto message = j.isObject && j["statusMessage"].isString
            ? j["statusMessage"].get!string : "Server replied with status " ~ reply.status.to!string;
        if (reply.status == 401 && authenticated)
            message ~= " (not logged in or session expired)";
        throw new RemoteError(reply.status, message);
    }
}

/// Zelle aus JSON. NUMERIC kommt als Text an (damit es exakt bleibt) und bleibt Text.
Value valueOf(Json cell) {
    switch (cell.type) {
    case Json.Type.int_:
        return Value(cell.get!long);
    case Json.Type.bigInt:
        return Value(cell.toString);
    case Json.Type.float_:
        return Value(cell.get!double);
    case Json.Type.string:
        return Value(cell.get!string);
    case Json.Type.bool_:
        return Value(cell.get!bool);
    default:
        return Value(uim.hdb.domain.value.Null());
    }
}

private long longOf(Json j) {
    if (j.isInteger)
        return j.get!long;
    if (j.type == Json.Type.float_)
        return cast(long) j.get!double;
    return 0;
}

private string textOf(Json j, string name) {
    enforce(j.type == Json.Type.object && j[name].isString, "Field missing in reply: " ~ name);
    return j[name].get!string;
}

private void sleepBriefly() @trusted {
    import core.thread : Thread;

    Thread.sleep(100.msecs);
}

/// Blockierender Client für den Unix-Socket, ohne Ereignisschleife. Eine Verbindung dient allen Anfragen.
/// Schließt der Server eine untätige Verbindung (nach 5 Minuten), verbindet sich der Client neu und schickt die
/// Anfrage noch einmal: der Server hat sie dann nicht gelesen, sie lief also nicht doppelt.
final class UnixSocketTransport : ICliTransport {
    import std.socket : AddressFamily, Socket, SocketFlags, SocketShutdown, SocketType, UnixAddress;

    enum size_t maxReplyHeaderBytes = 64 * 1024;
    private string path;
    private Socket socket;
    private ubyte[] buffer;

    this(string path) {
        enforce(path.length, "A socket path is required");
        this.path = path;
    }

    string socketPath() const {
        return path;
    }

    string exchange(string message) {
        foreach (attempt; 0 .. 2) {
            if (socket is null)
                connect();
            bool received;
            try {
                if (!sendAll(message))
                    throw new Exception("Connection to " ~ path ~ " lost while sending");
                return readReply(received);
            } catch (Exception e) {
                disconnect();
                if (attempt == 0 && !received)
                    continue;
                throw e;
            }
        }
        assert(false);
    }

    void close() {
        disconnect();
    }

    /// @trusted: std.socket ist größtenteils @system; hier gehen nur eigene Puffer an die Aufrufe.
    private void connect() @trusted {
        auto s = new Socket(AddressFamily.UNIX, SocketType.STREAM);
        try
            s.connect(new UnixAddress(path));
        catch (Exception e) {
            s.close();
            throw new Exception("Cannot connect to " ~ path ~ ": " ~ e.msg
                    ~ " (is the server running with UNIX_SOCKET=" ~ path ~ "?)");
        }
        socket = s;
        buffer = null;
    }

    private void disconnect() @trusted {
        if (socket is null)
            return;
        try {
            socket.shutdown(SocketShutdown.BOTH);
            socket.close();
        } catch (Exception) {
        }
        socket = null;
        buffer = null;
    }

    /// Ohne SIGPIPE: schreibt man auf eine vom Server geschlossene Verbindung, soll das ein Fehler sein, kein Abbruch.
    private bool sendAll(string message) @trusted {
        version (linux) {
            import core.sys.posix.sys.socket : MSG_NOSIGNAL;

            immutable flags = cast(SocketFlags) MSG_NOSIGNAL;
        } else
            immutable flags = SocketFlags.NONE;
        const(void)[] rest = message;
        while (rest.length) {
            auto sent = socket.send(rest, flags);
            if (sent <= 0 || sent == Socket.ERROR)
                return false;
            rest = rest[sent .. $];
        }
        return true;
    }

    /// Liest bis zum Ende des Body. `received` wird true, sobald ein Byte der Antwort da ist.
    private string readReply(ref bool received) @trusted {
        ptrdiff_t headerEnd = -1;
        size_t separator;
        while (headerEnd < 0) {
            headerEnd = (cast(string) buffer).indexOf("\n\n");
            separator = 2;
            auto crlf = (cast(string) buffer).indexOf("\r\n\r\n");
            if (crlf >= 0 && (headerEnd < 0 || crlf < headerEnd)) {
                headerEnd = crlf;
                separator = 4;
            }
            if (headerEnd >= 0)
                break;
            enforce(buffer.length <= maxReplyHeaderBytes, "Reply headers too large");
            fill(received);
        }
        size_t length;
        foreach (line; (cast(string) buffer[0 .. headerEnd]).lineSplitter) {
            auto colon = line.indexOf(':');
            if (colon > 0 && icmp(line[0 .. colon].strip, "Content-Length") == 0)
                length = line[colon + 1 .. $].strip.to!size_t;
        }
        immutable total = headerEnd + separator + length;
        while (buffer.length < total)
            fill(received);
        auto reply = cast(string) buffer[0 .. total].idup;
        buffer = buffer[total .. $].dup;
        return reply;
    }

    private void fill(ref bool received) @trusted {
        ubyte[16 * 1024] chunk;
        auto n = socket.receive(chunk[]);
        if (n == 0 || n == Socket.ERROR)
            throw new Exception("Connection to " ~ path ~ " closed by the server");
        received = true;
        buffer ~= chunk[0 .. n];
    }
}

unittest {
    import std.exception : assertThrown;

    assert(requestWire("GET", "/api/v1/tables", "a:b", "")
            == "GET /api/v1/tables\nAuthorization: Bearer a:b\nContent-Length: 0\n\n");
    assert(requestWire("POST", "/x", "", "{}") == "POST /x\nContent-Type: application/json\nContent-Length: 2\n\n{}");

    auto reply = parseReply("STATUS 201\nContent-Length: 4\n\nä\n\n");
    assert(reply.status == 201 && reply.ok && reply.body == "ä\n\n");
    assert(parseReply("STATUS 404\r\nContent-Length: 0\r\n\r\n").status == 404);
    assertThrown(parseReply("STATUS 200\n"));
    assertThrown(parseReply("HTTP/1.1 200\n\n"));
    assertThrown(parseReply("STATUS abc\n\n"));
}

unittest {
    import std.algorithm : canFind;
    import std.functional : toDelegate;
    import std.exception : assertThrown;
    import uim.hdb.presentation.cli.format : CliFormat, formatResult, formatStats;
    import uim.hdb.testing : runInEventLoop;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.map!"a".array;
        }
    }

    // Der Server im selben Prozess: dieselbe Verarbeitung wie hinter dem Socket, nur ohne Socket dazwischen
    static class InProcessTransport : ICliTransport {
        UnixController controller;
        size_t requests;
        this(UnixController controller) {
            this.controller = controller;
        }

        string exchange(string message) {
            requests++;
            return toWire(controller.handle(UnixRequest.parse(message)));
        }

        void close() {
        }
    }

    auto access = new AccessService(new MemStore, new OpensslCredentialCrypto);
    access.bootstrap("root", "correct-horse-root");
    auto transport = new InProcessTransport(new UnixController(new SecuredSqlUseCase(
            new SqlService(new MemoryTableRepository), toDelegate(&currentPrincipal)), access));

    auto failure = runInEventLoop({
        auto client = new RemoteSqlClient(transport);
        assert(client.healthy);
        auto e = collectRemote(client.listTables());
        assert(e !is null && e.status == 401 && e.msg.canFind("session expired"));
        assert(collectRemote(client.login("", "root", "wrong-password")).status == 401);

        assert(client.login("", "root", "correct-horse-root") == "default");
        client.execute("CREATE TABLE t (id INTEGER, name VARCHAR, n NUMERIC, f DOUBLE, b BOOLEAN)");
        client.execute("INSERT INTO t VALUES (1, 'a', 12345678901234567890.55, 1.5, TRUE)");
        client.execute("INSERT INTO t VALUES (2, NULL, NULL, NULL, NULL)");
        assert(client.listTables() == ["t"]);

        auto r = client.execute("SELECT * FROM t ORDER BY id");
        assert(r.columns.length == 5 && r.rows.length == 2);
        assert(formatResult(r, CliFormat.csv).canFind("\n1,a,12345678901234567890.55,1.5,TRUE\n2,,,,\n"),
            formatResult(r, CliFormat.csv));

        // Fehler des Kerns kommen mit seiner Meldung an
        auto syntax = collectRemote(client.execute("SELEC 1"));
        assert(syntax !is null && syntax.status == 400);

        // Transaktionen laufen über das Feld transaction
        auto tx = client.execute("BEGIN").transaction;
        assert(tx.length);
        client.executeIn(tx, "INSERT INTO t VALUES (3, 'c', 1, 1, FALSE)");
        client.executeIn(tx, "ROLLBACK");
        assert(client.execute("SELECT COUNT(*) FROM t").rows[0][0].get!long == 2);

        auto stats = client.stats();
        assert(stats.length == 1 && stats[0].table == "t" && stats[0].rows == 2 && stats[0].columns.length == 5);
        assert(formatStats(stats, CliFormat.table, "t").canFind("NUMERIC"));

        size_t pauses;
        client.pause = () { pauses++; };
        client.mergeDelta();
        assert(!client.mergeStatus().running);
        client.checkpoint();

        client.logout();
        assert(client.token.length == 0);
        assert(collectRemote(client.listTables()).status == 401);
    });
    if (failure !is null)
        throw failure;
}

version (unittest) private RemoteError collectRemote(T)(lazy T expression) {
    try
        expression();
    catch (RemoteError e)
        return e;
    return null;
}
