module uim.hdb.adapters.inbound.security;

import uim.hdb.application.ports;
import uim.hdb.domain.entities.user;
import std.algorithm : canFind, startsWith;
import std.conv : to;
import std.string : icmp, indexOf, strip;
import vibe.core.task : TaskLocal;
import vibe.http.common : HTTPMethod, HTTPStatusException;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;

enum sessionCookie = "hdb_session";

// Eine Verbindung bedient mehrere Anfragen im selben Task: das Gate setzt den Wert deshalb bei jeder Anfrage neu.
private TaskLocal!Principal requestPrincipal;

Principal currentPrincipal() @trusted {
    return requestPrincipal;
}

/// Für Adapter, die nicht durch das SecurityGate laufen: setzt die Identität des laufenden Tasks.
void bindPrincipal(Principal principal) @trusted {
    requestPrincipal = principal;
}

/// Läuft vor allen Routen und ist standardmäßig geschlossen: frei ist nur, was in isPublicPath steht.
/// Das Cookie gilt nur für /admin, die REST-Routen akzeptieren nur Bearer-Tokens. Ein Browser kann sie also
/// nicht ungefragt mit seiner Sitzung aufrufen (CSRF).
final class SecurityGate {
    private IAccessUseCase access;

    this(IAccessUseCase access) {
        this.access = access;
    }

    /// Muss als Erstes am Router registriert werden.
    void register(URLRouter router) {
        router.any("*", &gate);
    }

    private void gate(HTTPServerRequest req, HTTPServerResponse res) {
        immutable admin = isAdminPath(req.requestPath.toString);
        auto token = admin ? req.cookies.get(sessionCookie, "") : bearerToken(req.headers.get("Authorization", ""));
        auto principal = access.authenticate(token);
        requestPrincipal = principal;

        // Das Limit für Anfragen ist wegen der Sicherungen hoch: das gilt nur für angemeldete Benutzer
        if (!principal.authenticated
            && !isAnonymousBodyAllowed(req.headers.get("Content-Length", ""), req.headers.get("Transfer-Encoding", "")))
            throw new HTTPStatusException(HTTPStatus.requestEntityTooLarge, "Request body too large");

        if (admin && req.method != HTTPMethod.GET && req.method != HTTPMethod.HEAD
            && !isSameOrigin(req.headers.get("Origin", ""), req.host, req.headers.get("Sec-Fetch-Site", "")))
            throw new HTTPStatusException(HTTPStatus.forbidden, "Cross-site request rejected");

        if (principal.authenticated || isPublicPath(req.requestPath.toString))
            return;
        if (admin)
            return res.redirect("/admin/login");
        res.statusCode = HTTPStatus.unauthorized;
        res.headers["WWW-Authenticate"] = "Bearer";
        if (req.requestPath.toString.startsWith("/odata/")) { // Clients erwarten dort das OData-Fehlerformat
            res.headers["OData-Version"] = "4.0";
            res.writeBody(`{"error":{"code":"Unauthorized","message":"Authentication required"}}`, "application/json");
        } else
            res.writeJsonBody(["statusMessage": "Authentication required"]);
    }
}

bool isAdminPath(string path) @safe {
    return path == "/admin" || path.startsWith("/admin/");
}

bool isPublicPath(string path) @safe {
    if (["/", "/health", "/api/v1/health", "/api/v1/auth/login", "/admin/login", "/admin.js", "/ui5"].canFind(path))
        return true;
    // Das Fiori-Frontend muss vor der Anmeldung laden. Die Datenablage liegt neben public/: dieser Bereich
    // darf deshalb nie aus sich herausführen, egal wie sich der Dateiserver verhält.
    return path.startsWith("/ui5/") && !path.canFind("..") && !path.canFind('\\') && !path.canFind('\0');
}

/// Ohne Anmeldung gibt es nur kleine Formulare: Anmeldung und Passwortfelder.
bool isAnonymousBodyAllowed(string contentLength, string transferEncoding) @safe {
    enum limit = 64 * 1024;
    if (transferEncoding.length)
        return false; // Länge unbekannt
    if (contentLength.length == 0)
        return true;
    try
        return contentLength.to!ulong <= limit;
    catch (Exception)
        return false;
}

/// Token aus einem Authorization-Header; leer, wenn es kein Bearer-Schema ist.
string bearerToken(string header) @safe {
    enum scheme = "bearer ";
    if (header.length <= scheme.length || icmp(header[0 .. scheme.length], scheme) != 0)
        return "";
    return header[scheme.length .. $].strip;
}

/// Schutz vor CSRF: Browser senden bei POST Origin und/oder Sec-Fetch-Site.
/// Fehlen beide, kommt die Anfrage nicht aus einem Browser (curl, Skripte).
bool isSameOrigin(string origin, string host, string fetchSite) @safe {
    if (fetchSite.length && fetchSite != "same-origin" && fetchSite != "none")
        return false;
    if (origin.length == 0)
        return true;
    auto scheme = origin.indexOf("://");
    return scheme >= 0 && icmp(origin[scheme + 3 .. $], host) == 0;
}

unittest {
    assert(isSameOrigin("", "h:1", ""));
    assert(isSameOrigin("http://h:1", "h:1", "same-origin"));
    assert(!isSameOrigin("https://evil.example", "h:1", ""));
    assert(!isSameOrigin("", "h:1", "cross-site"));
    assert(!isSameOrigin("null", "h:1", ""));

    assert(bearerToken("Bearer abc") == "abc" && bearerToken("bearer  abc ") == "abc");
    assert(bearerToken("Basic abc") == "" && bearerToken("Bearer ") == "" && bearerToken("") == "");

    assert(isAnonymousBodyAllowed("", "") && isAnonymousBodyAllowed("65536", ""));
    assert(!isAnonymousBodyAllowed("65537", "") && !isAnonymousBodyAllowed("", "chunked") && !isAnonymousBodyAllowed("x", ""));

    assert(isAdminPath("/admin") && isAdminPath("/admin/users"));
    assert(!isAdminPath("/administrator") && !isAdminPath("/sql"));
    assert(isPublicPath("/health") && !isPublicPath("/sql") && !isPublicPath("/admin") && !isPublicPath("/health/"));
    assert(isPublicPath("/ui5") && isPublicPath("/ui5/") && isPublicPath("/ui5/view/App.view.xml"));
    assert(!isPublicPath("/ui5/../../data/hdb-users.json") && !isPublicPath("/ui5x") && !isPublicPath("/ui5/a\\b"));
}
