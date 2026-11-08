/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Verteilter Betrieb: wohin das Gateway eine Anfrage schickt. Reine Logik ohne Netz, damit sie sich prüfen lässt.
///
/// Jeder Mandant liegt auf genau einem hdb-Server (Backend). Benutzer, Rollen und Sitzungen bleiben dort; das
/// Gateway reicht die Anmeldung an das Backend des Mandanten weiter und gibt dessen Token mit vorangestellter
/// Backend-Kennung zurück ("eu.<token>"). Spätere Anfragen gehen anhand dieser Kennung an dasselbe Backend,
/// ohne Kennung.
module uim.hdb.gateway.routes;

import std.algorithm : all, canFind, sort;
import std.array : array, join, split;
import std.ascii : isDigit, isLower;
import std.exception : enforce;
import std.json : JSONType, JSONValue, parseJSON;
import std.string : indexOf, startsWith, strip, toLower;

@safe:

/// Bereich der Systemadministratoren, wie im Server (uim.hdb.domain.entities.tenant).
enum gatewaySystemTenant = "system";
/// Mandant bei leerer Angabe, wie im Server.
enum gatewayDefaultTenant = "default";

/// Ziel einer Anmeldung.
struct LoginRoute {
    string backend; // Kennung des Backends
    string url; // Basis-URL ohne Schrägstrich am Ende
    string tenant; // Mandant, wie ihn das Backend erhält (ohne "@backend")
}

/// Konfiguration des Gateways, aus JSON:
/// ---
/// {
///   "backends": { "eu": "http://10.0.0.1:8080", "us": "http://10.0.0.2:8080" },
///   "tenants":  { "default": "eu", "acme": "us" },
///   "fallback": "eu"
/// }
/// ---
/// `fallback` (optional) nimmt Mandanten ohne Eintrag auf und liefert die öffentlichen Seiten (Anmeldeformular,
/// Fiori-Client). Ohne `fallback` scheitert die Anmeldung eines unbekannten Mandanten, und die öffentlichen
/// Seiten kommen vom ersten Backend nach Namen.
final class GatewayRoutes {
    private string[string] backends; // Kennung -> URL
    private string[string] tenants; // Mandant -> Kennung
    private string fallback;

    this(string[string] backends, string[string] tenants, string fallback = "") {
        enforce(backends.length, "The gateway needs at least one backend");
        foreach (id, url; backends) {
            enforce(isBackendId(id), "Backend names use lowercase letters, digits, '_' or '-': " ~ id);
            this.backends[id] = normalizeUrl(url);
        }
        foreach (tenant, id; tenants) {
            enforce(id in this.backends, "Tenant " ~ tenant ~ " points to an unknown backend: " ~ id);
            this.tenants[tenant.strip.toLower] = id;
        }
        enforce(fallback.length == 0 || fallback in this.backends, "The fallback is not a backend: " ~ fallback);
        this.fallback = fallback;
    }

    static GatewayRoutes parse(string json) {
        auto j = parseJSON(json);
        enforce(j.type == JSONType.object, "The gateway configuration must be a JSON object");
        string[string] read(string key) {
            string[string] result;
            if (auto section = key in j.objectNoRef) {
                enforce(section.type == JSONType.object, key ~ " must be an object");
                foreach (k, v; section.objectNoRef) {
                    enforce(v.type == JSONType.string, key ~ "." ~ k ~ " must be a string");
                    result[k] = v.str;
                }
            }
            return result;
        }

        string fallback;
        if (auto f = "fallback" in j.objectNoRef) {
            enforce(f.type == JSONType.string, "fallback must be a string");
            fallback = f.str;
        }
        return new GatewayRoutes(read("backends"), read("tenants"), fallback);
    }

    /// Ziel für die Anmeldung mit diesem Mandanten; null-Kennung, wenn es keins gibt.
    /// "system@eu" meldet einen Systemadministrator am Backend eu an: jedes Backend hat seinen eigenen Systembereich.
    LoginRoute route(string loginTenant) const {
        auto t = loginTenant.strip.toLower;
        auto at = t.indexOf('@');
        if (at >= 0) {
            auto id = t[at + 1 .. $];
            auto name = t[0 .. at];
            if (name != gatewaySystemTenant || (id in backends) is null)
                return LoginRoute.init;
            return LoginRoute(id, backends[id], gatewaySystemTenant);
        }
        auto key = t.length ? t : gatewayDefaultTenant;
        auto id = key in tenants;
        auto target = id !is null ? *id : fallback;
        if (target.length == 0)
            return LoginRoute.init;
        return LoginRoute(target, backends[target], t);
    }

    /// Backend für Anfragen ohne Sitzung (öffentliche Seiten).
    string publicBackend() const {
        if (fallback.length)
            return fallback;
        auto ids = backends.keys.dup;
        ids.sort();
        return ids[0];
    }

    /// URL eines Backends; leer, wenn es die Kennung nicht gibt.
    string urlOf(string backend) const {
        auto url = backend in backends;
        return url is null ? "" : *url;
    }

    string[] backendIds() const {
        auto ids = backends.keys.dup;
        ids.sort();
        return ids;
    }
}

/// Token für den Client: Backend-Kennung, Punkt, Token des Backends. Die Tokens des Servers sind Base64URL und
/// enthalten keinen Punkt.
string gatewayToken(string backend, string token) {
    return token.length ? backend ~ "." ~ token : token;
}

/// Zerlegt ein Token des Gateways. Ohne gültige Kennung bleibt beides leer.
struct SplitToken {
    string backend;
    string token;
}

SplitToken splitToken(string token) {
    auto dot = token.indexOf('.');
    if (dot <= 0 || dot + 1 >= token.length || !isBackendId(token[0 .. dot]))
        return SplitToken.init;
    return SplitToken(token[0 .. dot], token[dot + 1 .. $]);
}

/// Ersetzt im Cookie-Header den Wert von `name`; die anderen Cookies bleiben unverändert.
string replaceCookie(string header, string name, string value) {
    string[] parts;
    foreach (part; header.split(";")) {
        auto p = part.strip;
        if (p.length == 0)
            continue;
        if (p.startsWith(name ~ "="))
            p = value.length ? name ~ "=" ~ value : "";
        if (p.length)
            parts ~= p;
    }
    return parts.join("; ");
}

/// Wert eines Cookies aus dem Cookie-Header; leer, wenn es fehlt.
string cookieValue(string header, string name) {
    foreach (part; header.split(";")) {
        auto p = part.strip;
        if (p.startsWith(name ~ "="))
            return p[name.length + 1 .. $];
    }
    return "";
}

/// Set-Cookie eines Backends: das Sitzungscookie bekommt die Kennung vorangestellt. Ein leerer Wert (Abmelden)
/// bleibt leer.
string prefixSetCookie(string setCookie, string name, string backend) {
    if (!setCookie.startsWith(name ~ "="))
        return setCookie;
    auto rest = setCookie[name.length + 1 .. $];
    auto end = rest.indexOf(';');
    auto value = end >= 0 ? rest[0 .. end] : rest;
    auto tail = end >= 0 ? rest[end .. $] : "";
    if (value.length == 0 || value == `""`)
        return setCookie;
    return name ~ "=" ~ gatewayToken(backend, value) ~ tail;
}

/// Kopfzeilen, die nur für eine Verbindung gelten und nicht weitergereicht werden (RFC 9110, 7.6.1).
bool isHopByHop(string header) {
    return ["connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "proxy-connection", "te",
        "trailer", "transfer-encoding", "upgrade"].canFind(header.toLower);
}

private bool isBackendId(string id) {
    return id.length >= 1 && id.length <= 32 && (isLower(id[0]) || isDigit(id[0]))
        && id.all!(c => isLower(c) || isDigit(c) || c == '_' || c == '-');
}

private string normalizeUrl(string url) {
    auto u = url.strip;
    while (u.length && u[$ - 1] == '/')
        u = u[0 .. $ - 1];
    enforce(u.startsWith("http://") || u.startsWith("https://"), "A backend URL must start with http:// or https://: " ~ url);
    return u;
}

unittest {
    import std.exception : assertThrown;

    auto r = GatewayRoutes.parse(`{
        "backends": {"eu": "http://10.0.0.1:8080/", "us": "https://us.example:8443"},
        "tenants": {"default": "eu", "ACME": "us"},
        "fallback": "eu"}`);
    assert(r.route("") == LoginRoute("eu", "http://10.0.0.1:8080", ""));
    assert(r.route(" Acme ") == LoginRoute("us", "https://us.example:8443", "acme"));
    assert(r.route("globex").backend == "eu"); // ohne Eintrag: fallback
    assert(r.route("system").backend == "eu");
    assert(r.route("system@us") == LoginRoute("us", "https://us.example:8443", "system"));
    assert(r.route("system@nowhere").backend == "" && r.route("acme@us").backend == "");
    assert(r.publicBackend == "eu" && r.urlOf("us") == "https://us.example:8443" && r.urlOf("x") == "");
    assert(r.backendIds == ["eu", "us"]);

    auto strict = new GatewayRoutes(["b": "http://b", "a": "http://a"], ["acme": "b"]);
    assert(strict.route("globex").backend == "" && strict.route("").backend == "");
    assert(strict.publicBackend == "a");

    assertThrown(GatewayRoutes.parse(`{"backends": {}}`));
    assertThrown(GatewayRoutes.parse(`{"backends": {"eu": "ftp://x"}}`));
    assertThrown(GatewayRoutes.parse(`{"backends": {"EU": "http://x"}}`));
    assertThrown(GatewayRoutes.parse(`{"backends": {"eu": "http://x"}, "tenants": {"a": "us"}}`));
    assertThrown(GatewayRoutes.parse(`{"backends": {"eu": "http://x"}, "fallback": "us"}`));
    assertThrown(GatewayRoutes.parse(`[]`));

    assert(gatewayToken("eu", "abc-_1") == "eu.abc-_1" && gatewayToken("eu", "") == "");
    assert(splitToken("eu.abc") == SplitToken("eu", "abc"));
    assert(splitToken("abc") == SplitToken.init && splitToken(".abc") == SplitToken.init);
    assert(splitToken("eu.") == SplitToken.init && splitToken("E U.abc") == SplitToken.init);

    assert(replaceCookie("a=1; hdb_session=eu.x; b=2", "hdb_session", "x") == "a=1; hdb_session=x; b=2");
    assert(replaceCookie("hdb_session=junk", "hdb_session", "") == "");
    assert(cookieValue("a=1; hdb_session=eu.x", "hdb_session") == "eu.x" && cookieValue("a=1", "hdb_session") == "");

    assert(prefixSetCookie("hdb_session=tok; Path=/admin; HttpOnly", "hdb_session", "us")
            == "hdb_session=us.tok; Path=/admin; HttpOnly");
    assert(prefixSetCookie("hdb_session=; Max-Age=0", "hdb_session", "us") == "hdb_session=; Max-Age=0");
    assert(prefixSetCookie("hdb_tenant=acme; Path=/admin", "hdb_session", "us") == "hdb_tenant=acme; Path=/admin");

    assert(isHopByHop("Transfer-Encoding") && isHopByHop("connection") && !isHopByHop("Content-Type"));
}
