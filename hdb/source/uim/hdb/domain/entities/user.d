module uim.hdb.domain.entities.user;

import uim.hdb;
import std.algorithm : any;

@safe:

/// Ein Benutzer gehört zu genau einem Mandanten; der Name ist nur innerhalb des Mandanten eindeutig.
/// `role` ist seine Rolle im Mandanten (leer: keine), `grants` gibt ihm zusätzlich Rollen für einzelne Tabellen.
struct HdbUser {
    string name;
    string passwordHash;
    string role;
    bool active = true;
    string tenant = defaultTenant;
    TableGrant[] grants;
}

/// Die angemeldete Identität einer Anfrage mit ihren aufgelösten Rechten. Der Standardwert ist anonym.
/// `tenant` bestimmt, welche Daten und welche Benutzer die Anfrage sieht. Rechte addieren sich: die der Rolle im
/// Mandanten gelten für alle Tabellen, die aus Tabellenfreigaben nur für die jeweilige Tabelle.
struct Principal {
    string name;
    bool authenticated;
    string tenant;
    string role; // Rolle im Mandanten, nur zur Anzeige
    PermissionSet permissions; // gilt im ganzen Mandanten bzw. auf dem Server
    PermissionSet[string] tables; // Schlüssel: Tabellenname klein geschrieben

    /// Identität mit einer vordefinierten Rolle, etwa für Tests und Werkzeuge.
    this(string name, HdbRole builtin, bool authenticated, string tenant = "") {
        this.name = name;
        this.authenticated = authenticated;
        this.tenant = tenant;
        role = roleName(builtin);
        foreach (r; builtinRoles(tenant.length ? tenant : defaultTenant))
            if (r.name == role)
                permissions = r.permissions;
    }

    /// Systembenutzer verwalten den Server und haben keinen Zugriff auf Daten der Mandanten.
    bool isSystem() const {
        return authenticated && tenant == systemTenant;
    }

    bool can(Permission p) const {
        return authenticated && permissions.has(p);
    }

    /// Recht auf einer Tabelle: aus der Rolle im Mandanten oder aus einer Freigabe der Tabelle.
    bool can(Permission p, string table) const {
        if (can(p))
            return true;
        if (!authenticated)
            return false;
        auto grant = table.toLower in tables;
        return grant !is null && grant.has(p);
    }

    /// Ob die Tabelle in Listen, Statistik und $metadata erscheint: bei irgendeinem Recht auf ihr.
    bool canSee(string table) const {
        if (can(Permission.select))
            return true;
        if (!authenticated)
            return false;
        auto grant = table.toLower in tables;
        return grant !is null && !grant.empty;
    }
}

/// Keine gültige Anmeldung (HTTP 401).
class AuthenticationRequired : Exception {
    this(string msg = "Authentication required", string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Angemeldet, aber ohne das nötige Recht (HTTP 403).
class AccessDenied : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Namen der vordefinierten Rollen.
string roleName(HdbRole role) {
    final switch (role) {
    case HdbRole.viewer:
        return "viewer";
    case HdbRole.editor:
        return "editor";
    case HdbRole.admin:
        return "admin";
    }
}

/// Prüft ein Recht im ganzen Mandanten bzw. auf dem Server; wirft AuthenticationRequired oder AccessDenied.
void requirePermission(Principal principal, Permission p) {
    if (!principal.authenticated)
        throw new AuthenticationRequired;
    if (!principal.can(p))
        throw new AccessDenied("Requires permission " ~ permissionName(p));
}

/// Prüft ein Recht auf einer Tabelle (Rolle im Mandanten oder Freigabe).
void requirePermission(Principal principal, Permission p, string table) {
    if (!principal.authenticated)
        throw new AuthenticationRequired;
    if (!principal.can(p, table))
        throw new AccessDenied("Requires permission " ~ permissionName(p) ~ " on table " ~ table);
}

/// Nur angemeldet, ohne bestimmtes Recht.
void requireAuthenticated(Principal principal) {
    if (!principal.authenticated)
        throw new AuthenticationRequired;
}

/// Ob eine Anweisung nur liest. Normalisiert wie SqlService.executeIn, damit beide dasselbe Verb sehen.
bool isReadOnlyStatement(string statement) {
    auto words = statement.strip.chomp(";").strip.split();
    return words.length == 0 || words[0].toUpper == "SELECT";
}

unittest {
    import std.exception : assertThrown;

    assert(isReadOnlyStatement("  select * from t;") && isReadOnlyStatement(""));
    assert(!isReadOnlyStatement("COMMIT;") && !isReadOnlyStatement("DROP TABLE t") && !isReadOnlyStatement("VACUUM"));

    auto viewer = Principal("v", HdbRole.viewer, true);
    assert(viewer.can(Permission.select) && !viewer.can(Permission.insert) && viewer.role == "viewer");
    assertThrown!AuthenticationRequired(requirePermission(Principal.init, Permission.select));
    assertThrown!AccessDenied(requirePermission(viewer, Permission.insert));
    requirePermission(Principal("a", HdbRole.admin, true), Permission.create);

    // Tabellenfreigaben gelten nur für ihre Tabelle und addieren sich zur Rolle
    Principal p;
    p.name = "t";
    p.authenticated = true;
    p.tables["orders"] = PermissionSet.of(Permission.select, Permission.insert);
    assert(p.can(Permission.insert, "Orders") && !p.can(Permission.insert, "other") && !p.can(Permission.insert));
    assert(p.canSee("orders") && !p.canSee("other"));
    assertThrown!AccessDenied(requirePermission(p, Permission.update, "orders"));
    requirePermission(p, Permission.insert, "ORDERS");
    viewer.tables["orders"] = PermissionSet.of(Permission.update);
    assert(viewer.can(Permission.update, "orders") && viewer.can(Permission.select, "other") && viewer.canSee("x"));
    p.authenticated = false;
    assert(!p.can(Permission.select, "orders") && !p.canSee("orders"));

    // Serverrechte gibt es nur im Bereich system
    auto sys = Principal("s", HdbRole.admin, true, systemTenant);
    assert(sys.isSystem && sys.can(Permission.manageTenants) && !sys.can(Permission.select));
    assert(!Principal("a", HdbRole.admin, true, defaultTenant).can(Permission.viewTenants));
    assert(!Principal("s", HdbRole.editor, true, systemTenant).can(Permission.viewTenants)); // keine Systemrolle
}
