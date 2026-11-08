/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Eingehender Adapter des Gateways: nimmt jede Anfrage an und reicht sie an das Backend des Mandanten weiter.
/// Das Gateway prüft selbst keine Rechte: das tut das Backend, an das die Anfrage geht. Es sorgt nur dafür, dass
/// ein Token nie an ein anderes Backend gelangt als das, das es ausgestellt hat.
module uim.hdb.gateway.proxy;

import uim.hdb.gateway.routes;
import core.time : Duration, MonoTime, seconds;
import std.array : Appender;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.json : JSONType, JSONValue, parseJSON;
import std.string : icmp, startsWith, strip;
import vibe.core.log : logInfo, logWarn;
import vibe.core.stream : InputStream, pipe;
import vibe.http.client : HTTPClientRequest, HTTPClientResponse, HTTPClientSettings, requestHTTP;
import vibe.http.common : HTTPMethod;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.inet.url : URL;
import vibe.inet.webform : FormFields, formEncode, parseURLEncodedForm;
import vibe.internal.interfaceproxy : InterfaceProxy;
import vibe.stream.operations : readAll;

@safe:

/// Name des Sitzungscookies der Admin-Oberfläche, wie im Server (uim.hdb.adapters.inbound.security).
enum gatewaySessionCookie = "hdb_session";

/// Konfigurationsdatei des Gateways. Änderungen gelten ohne Neustart: die Datei wird höchstens einmal je Sekunde
/// geprüft. Ist eine geänderte Datei fehlerhaft, bleibt die bisherige Konfiguration in Kraft.
final class GatewayConfigFile {
    private string path;
    private GatewayRoutes routes;
    private SysTime modified;
    private MonoTime checked;

    this(string path) {
        import std.file : readText, timeLastModified;

        this.path = path;
        routes = GatewayRoutes.parse(readText(path));
        modified = timeLastModified(path);
        checked = MonoTime.currTime;
    }

    GatewayRoutes current() {
        import std.file : readText, timeLastModified;

        auto now = MonoTime.currTime;
        if (now - checked < 1.seconds)
            return routes;
        checked = now;
        try {
            auto stamp = timeLastModified(path);
            if (stamp != modified) {
                modified = stamp;
                routes = GatewayRoutes.parse(readText(path));
                logInfo("Gateway: Konfiguration neu geladen, Backends: %s", routes.backendIds);
            }
        } catch (Exception e)
            logWarn("Gateway: Konfiguration %s nicht übernommen, die bisherige gilt weiter: %s", path, e.msg);
        return routes;
    }
}

/// Leitet alle Anfragen weiter. Muss die letzte Route sein; davor dürfen nur Routen stehen, die das Gateway
/// selbst beantwortet (/api/v1/info).
final class GatewayProxy {
    private GatewayRoutes delegate() @safe routes;
    private HTTPClientSettings client;

    this(GatewayRoutes delegate() @safe routes, Duration connectTimeout = 5.seconds, Duration readTimeout = 300.seconds) {
        this.routes = routes;
        client = new HTTPClientSettings;
        client.connectTimeout = connectTimeout;
        client.readTimeout = readTimeout;
    }

    void register(URLRouter router) {
        router.get("/health", &health);
        router.any("*", &forward);
    }

    private void health(HTTPServerRequest req, HTTPServerResponse res) {
        auto j = JSONValue(["status": "UP", "mode": "gateway"]);
        res.writeBody(j.toString, "application/json");
    }

    private void forward(HTTPServerRequest req, HTTPServerResponse res) {
        auto table = routes();
        auto path = req.requestPath.toString;
        if (req.method == HTTPMethod.POST && path == "/api/v1/auth/login")
            return restLogin(table, req, res);
        if (req.method == HTTPMethod.POST && path == "/admin/login")
            return adminLogin(table, req, res);

        // Wie im Server: die Admin-Oberfläche nutzt das Cookie, alles andere das Bearer-Token
        immutable admin = path == "/admin" || path.startsWith("/admin/");
        auto bearer = splitToken(bearerOf(req.headers.get("Authorization", "")));
        auto cookie = splitToken(cookieValue(req.headers.get("Cookie", ""), gatewaySessionCookie));
        auto session = admin ? cookie : bearer;
        auto backend = session.backend.length && table.urlOf(session.backend).length ? session.backend
            : table.publicBackend;

        proxy(table, backend, req, res, (scope HTTPClientRequest up) {
            // Ein Token geht nur an das Backend, das es ausgestellt hat
            up.headers.remove("Authorization");
            if (bearer.backend == backend)
                up.headers["Authorization"] = "Bearer " ~ bearer.token;
            if (auto c = "Cookie" in up.headers) {
                auto rewritten = replaceCookie(*c, gatewaySessionCookie, cookie.backend == backend ? cookie.token : "");
                if (rewritten.length)
                    up.headers["Cookie"] = rewritten;
                else
                    up.headers.remove("Cookie");
            }
            req.bodyReader.pipe(up.bodyWriter);
        }, null);
    }

    /// REST-Anmeldung: {"user", "password", "tenant"}. Die Antwort trägt das Token mit Backend-Kennung.
    private void restLogin(GatewayRoutes table, HTTPServerRequest req, HTTPServerResponse res) {
        JSONValue body;
        try
            body = parseJSON(cast(string) readAll(req.bodyReader, maxLoginBody).idup);
        catch (Exception)
            return reject(res, HTTPStatus.badRequest, "Invalid login request");
        if (body.type != JSONType.object)
            return reject(res, HTTPStatus.badRequest, "Invalid login request");
        string tenant;
        if (auto t = "tenant" in body.objectNoRef)
            if (t.type == JSONType.string)
                tenant = t.str;
        auto target = table.route(tenant);
        if (target.backend.length == 0)
            return reject(res, HTTPStatus.unauthorized, "Invalid tenant, user name or password");
        body["tenant"] = target.tenant;
        auto payload = body.toString;

        proxy(table, target.backend, req, res, (scope HTTPClientRequest up) {
            up.headers.remove("Authorization");
            up.headers.remove("Cookie");
            up.headers.remove("Content-Length");
            up.writeBody(cast(const(ubyte)[]) payload, "application/json");
        }, (scope HTTPClientResponse down) {
            auto text = cast(string) readAll(down.bodyReader).idup;
            if (down.statusCode == HTTPStatus.ok)
                try {
                    auto answer = parseJSON(text);
                    if (answer.type == JSONType.object)
                        if (auto token = "token" in answer.objectNoRef)
                            if (token.type == JSONType.string) {
                                answer["token"] = gatewayToken(target.backend, token.str);
                                text = answer.toString;
                            }
                } catch (Exception) {
                }
            res.writeBody(text, down.headers.get("Content-Type", "application/json"));
        });
    }

    /// Formular der Admin-Oberfläche. Das Sitzungscookie bekommt die Kennung in proxy().
    private void adminLogin(GatewayRoutes table, HTTPServerRequest req, HTTPServerResponse res) {
        FormFields form;
        try
            parseURLEncodedForm(cast(string) readAll(req.bodyReader, maxLoginBody).idup, form);
        catch (Exception)
            return reject(res, HTTPStatus.badRequest, "Invalid login request");
        auto target = table.route(form.get("tenant", ""));
        if (target.backend.length == 0) {
            res.statusCode = HTTPStatus.unauthorized;
            return res.writeBody(`<!doctype html><meta charset="utf-8"><title>Sign in - hdb</title>`
                    ~ `<p>Invalid tenant, user name or password.</p><p><a href="/admin/login">Back to sign in</a></p>`,
                    "text/html; charset=utf-8");
        }
        form["tenant"] = target.tenant;
        Appender!string encoded;
        encoded.formEncode(form);
        auto payload = encoded[];

        proxy(table, target.backend, req, res, (scope HTTPClientRequest up) {
            up.headers.remove("Authorization");
            up.headers.remove("Cookie");
            up.headers.remove("Content-Length");
            up.writeBody(cast(const(ubyte)[]) payload, "application/x-www-form-urlencoded");
        }, null);
    }

    /// Schickt die Anfrage an `backend`. `send` schreibt den Rumpf, `receive` (optional) liest die Antwort; ohne
    /// `receive` wird sie unverändert weitergereicht. Kopfzeilen kopiert proxy() in beide Richtungen, dabei bekommt
    /// das Sitzungscookie aus Set-Cookie die Kennung des Backends.
    private void proxy(GatewayRoutes table, string backend, HTTPServerRequest req, HTTPServerResponse res,
        scope void delegate(scope HTTPClientRequest) @safe send, scope void delegate(scope HTTPClientResponse) @safe receive) {
        auto url = URL.parse(table.urlOf(backend) ~ req.requestURI);
        try
            requestHTTP(url, (scope HTTPClientRequest up) {
                up.method = req.method;
                foreach (key, value; req.headers.byKeyValue)
                    if (!isHopByHop(key) && icmp(key, "Host") != 0 && icmp(key, "Accept-Encoding") != 0)
                        up.headers.addField(key, value);
                // Der Host des Clients bleibt: das Backend prüft damit die Herkunft von Formularen (CSRF).
                // Das Backend sieht die Adresse des Clients, wenn TRUSTED_PROXIES das Gateway enthält.
                up.headers["Host"] = req.headers.get("Host", url.host);
                auto forwarded = req.headers.get("X-Forwarded-For", "");
                up.headers["X-Forwarded-For"] = forwarded.length ? forwarded ~ ", " ~ req.peer : req.peer;
                up.headers["X-Forwarded-Proto"] = req.tls ? "https" : "http";
                send(up);
            }, (scope HTTPClientResponse down) {
                res.statusCode = down.statusCode;
                res.statusPhrase = down.statusPhrase;
                foreach (key, value; down.headers.byKeyValue) {
                    if (isHopByHop(key) || icmp(key, "Content-Length") == 0)
                        continue;
                    res.headers.addField(key, icmp(key, "Set-Cookie") == 0
                        ? prefixSetCookie(value, gatewaySessionCookie, backend) : value);
                }
                if (receive !is null)
                    return receive(down);
                if (req.method == HTTPMethod.HEAD || ("Content-Length" !in down.headers
                        && "Transfer-Encoding" !in down.headers)) {
                    down.dropBody();
                    return res.writeVoidBody();
                }
                if (auto length = "Content-Length" in down.headers) {
                    auto size = (*length).to!size_t;
                    return down.readRawBody((scope InterfaceProxy!InputStream raw) {
                        res.writeRawBody(raw, size);
                    });
                }
                res.headers.remove("Content-Encoding"); // bodyReader liefert den entpackten Inhalt
                down.bodyReader.pipe(res.bodyWriter);
            }, client);
        catch (Exception e) {
            if (res.headerWritten)
                throw e; // die Antwort läuft schon: nur noch die Verbindung abbrechen
            logWarn("Gateway: Backend %s (%s) nicht erreichbar: %s", backend, table.urlOf(backend), e.msg);
            res.headers.remove("Set-Cookie");
            reject(res, HTTPStatus.badGateway, "The database server for this tenant can't be reached");
        }
    }
}

private enum maxLoginBody = 64 * 1024;

private void reject(HTTPServerResponse res, int status, string message) {
    res.statusCode = status;
    res.writeBody(JSONValue(["statusMessage": message]).toString, "application/json");
}

private string bearerOf(string header) {
    enum scheme = "bearer ";
    if (header.length <= scheme.length || icmp(header[0 .. scheme.length], scheme) != 0)
        return "";
    return header[scheme.length .. $].strip;
}
