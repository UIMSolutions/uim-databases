/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.unix.server;

import uim.hdb;
import core.stdc.errno : ECONNREFUSED;
import core.sys.posix.sys.stat : lstat, S_IFMT, S_IFSOCK, stat_t, umask;
import core.time : Duration, minutes;
import std.conv : octal;
import std.exception : enforce;
import std.file : remove;
import std.socket : AddressFamily, Socket, SocketOSException, SocketType, StdUnixAddress = UnixAddress;
import std.string : toStringz;
import vibe.core.log : logInfo, logWarn;
import vibe.core.net : listenTCP, NetworkAddress, TCPConnection, TCPListener;

/// Inbound adapter: accepts connections on a Unix domain socket and forwards requests to the controllers.
final class UnixServer : IUnixServer {
    enum size_t defaultMaxBodyBytes = 16 * 1024 * 1024;
    enum Duration idleTimeout = 5.minutes;

    private string path;
    private IUnixController[] controllers;
    private size_t maxBodyBytes;
    private TCPListener listener;
    private bool isRunning;
    private bool[UnixConnection] connections;

    this(string socketPath, IUnixController[] controllers, size_t maxBodyBytes = defaultMaxBodyBytes) {
        path = socketPath;
        this.controllers = controllers;
        this.maxBodyBytes = maxBodyBytes;
    }

    string socketPath() const {
        return path;
    }

    bool running() const {
        return isRunning;
    }

    void start() {
        enforce(!isRunning, "Unix socket server is already running");
        removeStaleSocket(path);
        // Die Rechte müssen schon beim Anlegen stimmen: ein späteres chmod ließe ein Zeitfenster offen
        immutable previous = umask(octal!177);
        scope (exit)
            umask(previous);
        listener = listenTCP(&serve, unixAddress(path));
        isRunning = true;
        logInfo("Listening for requests on unix socket %s", path);
    }

    void stop() {
        if (!isRunning)
            return;
        isRunning = false;
        listener.stopListening();
        foreach (connection; connections.keys)
            connection.close();
        remove(path);
    }

    /// One response per request; the identity is set by the controller for each request anew.
    IUnixResponse dispatch(IUnixRequest request) {
        foreach (controller; controllers)
            if (controller.canHandle(request))
                return controller.handle(request);
        return UnixResponse.error(404, "No route for " ~ request.method ~ " " ~ request.path);
    }

    private void serve(TCPConnection socket) @trusted nothrow {
        try {
            socket.readTimeout = idleTimeout;
            auto connection = new UnixConnection(socket, maxBodyBytes);
            connections[connection] = true;
            scope (exit) {
                connections.remove(connection);
                connection.close();
            }
            try {
                for (auto message = connection.readMessage(); message !is null; message = connection.readMessage())
                    connection.writeMessage(toWire(dispatch(UnixRequest.parse(message))));
            } catch (UnixProtocolError e)
                connection.writeMessage(toWire(UnixResponse.error(e.status, e.msg)));
        } catch (Exception e) {
            // Abbruch durch den Client, Zeitüberschreitung oder stop: die Verbindung ist ohnehin zu Ende
            try
                logWarn("Unix socket connection ended: %s", e.msg);
            catch (Exception) {
            }
        }
    }
}

/// Removes only what is certainly a stale socket. Everything else at the path belongs to someone else.
private void removeStaleSocket(string path) {
    stat_t info;
    if (lstat(path.toStringz, &info) != 0)
        return;
    enforce((info.st_mode & S_IFMT) == S_IFSOCK, "Not a socket, refusing to replace it: " ~ path);

    auto probe = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    scope (exit)
        probe.close();
    try
        probe.connect(new StdUnixAddress(path));
    catch (SocketOSException e) {
        enforce(e.errorCode == ECONNREFUSED, "Cannot check unix socket " ~ path ~ ": " ~ e.msg);
        remove(path);
        return;
    }
    throw new Exception("Unix socket is in use: " ~ path);
}

/// Address for listenTCP and connectTCP.
NetworkAddress unixAddress(string path) @trusted {
    import core.sys.posix.sys.un : sockaddr_un;

    NetworkAddress address;
    address.family = AddressFamily.UNIX;
    sockaddr_un* unix = address.sockAddrUnix;
    enforce(path.length > 0 && path.length < unix.sun_path.length, "Invalid unix socket path: " ~ path);
    unix.sun_family = AddressFamily.UNIX;
    unix.sun_path[0 .. path.length] = cast(typeof(unix.sun_path[0 .. 1]))path;
    unix.sun_path[path.length] = 0;
    return address;
}

unittest {
    import std.algorithm : canFind, startsWith;
    import std.array : replicate;
    import std.conv : to;
    import std.exception : assertThrown;
    import std.file : exists, mkdirRecurse, readText, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.string : indexOf, representation;
    import std.uuid : randomUUID;
    import vibe.core.core : exitEventLoop, runEventLoop, runTask;
    import vibe.core.net : connectTCP;

    static class Echo : IUnixController {
        string routePrefix() const {
            return "/echo";
        }

        bool canHandle(IUnixRequest request) {
            return request.path.startsWith("/echo");
        }

        IUnixResponse handle(IUnixRequest request) {
            return new UnixResponse(200, request.method ~ "|" ~ request.header("X-Id") ~ "|" ~ request.body);
        }
    }

    auto dir = buildPath(tempDir, "hdb-unix-" ~ randomUUID().toString[0 .. 8]);
    mkdirRecurse(dir);
    scope (exit)
        rmdirRecurse(dir);
    auto path = buildPath(dir, "s.sock");

    static string response(ref TCPConnection c) {
        char[] data;
        ubyte[1] next;
        while (!data.canFind("\n\n")) {
            c.read(next[]);
            data ~= cast(char)next[0];
        }
        auto marker = data.indexOf("Content-Length: ");
        auto length = data[marker + 16 .. data.indexOf("\n\n")].to!size_t;
        auto content = new ubyte[length];
        if (length)
            c.read(content);
        return data.idup ~ cast(string)content;
    }

    Throwable failure;
    runTask(() nothrow {
        try {
            auto server = new UnixServer(path, [new Echo], 32);
            assert(server.socketPath == path && !server.running);
            server.start();
            assert(server.running);
            assertThrown(server.start());

            stat_t info;
            assert(lstat(path.toStringz, &info) == 0 && (info.st_mode & octal!777) == octal!600);
            assert((info.st_mode & S_IFMT) == S_IFSOCK);

            // Mehrere Anfragen auf einer Verbindung, der Body endet genau nach Content-Length
            auto c = connectTCP(unixAddress(path));
            c.write("POST /echo\nX-Id: 1\nContent-Length: 5\n\na\n\nbc".representation);
            auto first = response(c);
            assert(first.startsWith("STATUS 200\n") && first.canFind("\n\nPOST|1|a\n\nbc"));
            c.write("GET /echo\r\nX-Id: 2\r\n\r\nPOST /echo\nX-Id: 3\nContent-Length: 1\n\nz".representation);
            assert(response(c).canFind("\n\nGET|2|"));
            assert(response(c).canFind("\n\nPOST|3|z"));
            c.write("GET /nope\n\n".representation);
            assert(response(c).startsWith("STATUS 404\n"));
            c.close();

            // Protokollfehler: Antwort, dann Ende der Verbindung
            foreach (test; [["garbage\n\n", "STATUS 400\n"], ["GET /echo\nContent-Length: x\n\n", "STATUS 400\n"],
                ["POST /echo\nContent-Length: 33\n\n", "STATUS 413\n"], ["GET /echo\nX: " ~ "a".replicate(70_000), "STATUS 413\n"],
                ["POST /echo\nContent-Length: 1\n\n\xFF", "STATUS 400\n"]]) {
                c = connectTCP(unixAddress(path));
                c.write(test[0].representation);
                assert(response(c).startsWith(test[1]));
                assert(c.empty);
                c.close();
            }

            // Ein laufender Socket wird nicht ersetzt
            auto second = new UnixServer(path, [new Echo]);
            assertThrown(second.start());
            assert(!second.running);

            // stop schließt offene Verbindungen und räumt den Pfad auf
            c = connectTCP(unixAddress(path));
            c.write("GET /echo\n\n".representation);
            response(c);
            server.stop();
            assert(!server.running && !exists(path) && c.empty);
            c.close();
            server.stop(); // zweimal ist kein Fehler

            // Ein verwaister Socket wird ersetzt, ein anderer Pfad nie angefasst
            auto dead = new Socket(AddressFamily.UNIX, SocketType.STREAM);
            dead.bind(new StdUnixAddress(path));
            dead.close();
            assert(exists(path));
            server.start();
            server.stop();

            auto file = buildPath(dir, "data.txt");
            write(file, "keep");
            assertThrown(new UnixServer(file, [new Echo]).start());
            assert(readText(file) == "keep");

            assertThrown(new UnixServer(buildPath(dir, "x".replicate(200)), [new Echo]).start());
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
