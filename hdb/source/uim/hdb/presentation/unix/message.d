/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.unix.message;

import uim.hdb.presentation.unix.interfaces;
import std.array : appender, split;
import std.conv : to;
import std.string : icmp, indexOf, strip, stripRight, toUpper;
import vibe.data.json : Json, parseJsonString;

@safe:

/// Eine Nachricht verletzt das Protokoll; `status` geht an den Client, danach endet die Verbindung.
class UnixProtocolError : Exception {
    int status;

    this(int status, string message) {
        super(message);
        this.status = status;
    }
}

/// Format: Zeile "METHODE pfad", Header "Name: Wert", Leerzeile, Body. Zeilen enden mit \n oder \r\n,
/// Content-Length gibt die Länge des Body in Bytes an und fehlt nur bei leerem Body.
class UnixRequest : IUnixRequest {
    private string _method, _path, _body;
    private string[string] _headers;

    this(string method, string path, string body = null) {
        _method = method.toUpper;
        _path = path;
        _body = body;
    }

    string method() const {
        return _method;
    }

    string path() const {
        return _path;
    }

    string[string] headers() const {
        string[string] copy;
        foreach (name, value; _headers)
            copy[name] = value;
        return copy;
    }

    string header(string name) const {
        foreach (key, value; _headers)
            if (icmp(key, name) == 0)
                return value;
        return null;
    }

    UnixRequest setHeader(string name, string value) {
        _headers[name] = value;
        return this;
    }

    string body() const {
        return _body;
    }

    static UnixRequest parse(string message) {
        size_t position;
        string nextLine() {
            auto end = message.indexOf('\n', position);
            if (end < 0)
                throw new UnixProtocolError(400, "Incomplete message");
            auto line = message[position .. end].stripRight("\r");
            position = end + 1;
            return line;
        }

        auto start = nextLine().split(" ");
        if (start.length != 2 || start[0].length == 0 || start[1].length == 0 || start[1][0] != '/')
            throw new UnixProtocolError(400, "Request line must be: METHOD /path");
        auto request = new UnixRequest(start[0], start[1]);
        for (auto line = nextLine(); line.length; line = nextLine()) {
            auto colon = line.indexOf(':');
            if (colon <= 0)
                throw new UnixProtocolError(400, "Invalid header line");
            request.setHeader(line[0 .. colon].strip, line[colon + 1 .. $].strip);
        }
        request._body = message[position .. $];
        return request;
    }

    Json json() const {
        if (_body.length == 0)
            return Json(null);
        try
            return parseJsonString(_body);
        catch (Exception)
            return Json(null);
    }
}

class UnixResponse : IUnixResponse {
    private int _status;
    private string _body;
    private string[string] _headers;

    this(int status = 200, string body = null) {
        _status = status;
        _body = body;
    }

    /// Dasselbe Fehlerformat wie die REST-API.
    static UnixResponse error(int status, string message) {
        auto response = new UnixResponse(status);
        response.json(Json(["statusMessage": Json(message)]));
        return response;
    }

    int status() const {
        return _status;
    }

    IUnixResponse status(int value) {
        _status = value;
        return this;
    }

    string[string] headers() const {
        string[string] copy;
        foreach (name, value; _headers)
            copy[name] = value;
        return copy;
    }

    IUnixResponse header(string name, string value) {
        _headers[name] = value;
        return this;
    }

    string body() const {
        return _body;
    }

    IUnixResponse body(string value) {
        _body = value;
        return this;
    }

    IUnixResponse json(Json value) {
        _body = value.toString;
        _headers["Content-Type"] = "application/json";
        return this;
    }
}

/// Antwort im Protokollformat: Zeile "STATUS code", Header mit Content-Length, Leerzeile, Body.
string toWire(IUnixResponse response) {
    auto result = appender!string;
    result.put("STATUS " ~ response.status.to!string ~ "\n");
    foreach (name, value; response.headers)
        if (icmp(name, "Content-Length") != 0)
            result.put(name ~ ": " ~ value ~ "\n");
    result.put("Content-Length: " ~ response.body.length.to!string ~ "\n\n");
    result.put(response.body);
    return result.data;
}

unittest {
    import std.exception : assertThrown;

    auto request = UnixRequest.parse("post /api/v1/sql\r\nAuthorization: Bearer a:b\nContent-Length: 6\n\nx\n\ny\r\n");
    assert(request.method == "POST" && request.path == "/api/v1/sql");
    assert(request.header("authorization") == "Bearer a:b" && request.body == "x\n\ny\r\n");
    assert(UnixRequest.parse("GET /\n\n").body == "");

    assertThrown!UnixProtocolError(UnixRequest.parse(""));
    assertThrown!UnixProtocolError(UnixRequest.parse("GET /\n")); // Leerzeile fehlt
    assertThrown!UnixProtocolError(UnixRequest.parse("garbage\n\n"));
    assertThrown!UnixProtocolError(UnixRequest.parse("GET relative\n\n"));
    assertThrown!UnixProtocolError(UnixRequest.parse("GET / extra\n\n"));
    assertThrown!UnixProtocolError(UnixRequest.parse("GET /\nNoColon\n\n"));

    auto wire = toWire(new UnixResponse(201, "äb").header("Content-Length", "1"));
    assert(wire == "STATUS 201\nContent-Length: 3\n\näb");
}
