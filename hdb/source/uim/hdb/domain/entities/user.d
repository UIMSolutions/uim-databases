module uim.hdb.domain.entities.user;

import uim.hdb;

struct HdbUser {
    string name;
    string passwordHash;
    HdbRole role;
    bool active = true;
}

/// Die angemeldete Identität einer Anfrage. Der Standardwert ist anonym.
struct Principal {
    string name;
    HdbRole role;
    bool authenticated;
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

HdbRole parseRole(string name) {
    switch (name.strip.toLower) {
    case "viewer":
        return HdbRole.viewer;
    case "editor":
        return HdbRole.editor;
    case "admin":
        return HdbRole.admin;
    default:
        throw new Exception("Unknown role: " ~ name);
    }
}

/// Prüft die Rolle; wirft AuthenticationRequired oder AccessDenied.
void requireRole(Principal principal, HdbRole role) {
    if (!principal.authenticated)
        throw new AuthenticationRequired;
    if (principal.role < role)
        throw new AccessDenied("Requires role " ~ roleName(role));
}

/// Nötige Rolle einer Anweisung. Normalisiert wie SqlService.executeIn, damit beide dasselbe Verb sehen;
/// Unbekanntes verlangt admin.
HdbRole requiredRole(string statement) {
    auto words = statement.strip.chomp(";").strip.split();
    if (words.length == 0)
        return HdbRole.viewer; // leere Anweisung lehnt der Kern ab
    switch (words[0].toUpper) {
    case "SELECT":
        return HdbRole.viewer;
    case "INSERT":
    case "UPDATE":
    case "DELETE":
    case "BEGIN":
    case "COMMIT":
    case "ROLLBACK":
        return HdbRole.editor;
    default:
        return HdbRole.admin;
    }
}

unittest {
    import std.exception : assertThrown;

    assert(requiredRole("  select * from t;") == HdbRole.viewer);
    assert(requiredRole("COMMIT;") == HdbRole.editor);
    assert(requiredRole("delete from t") == HdbRole.editor);
    assert(requiredRole("DROP TABLE t") == HdbRole.admin);
    assert(requiredRole("CREATE TABLE t (a INTEGER)") == HdbRole.admin);
    assert(requiredRole("VACUUM") == HdbRole.admin);
    assert(requiredRole("SELECT* FROM t") == HdbRole.admin); // für den Kern kein SELECT

    assert(parseRole(" Editor ") == HdbRole.editor);
    assertThrown(parseRole("root"));

    assertThrown!AuthenticationRequired(requireRole(Principal.init, HdbRole.viewer));
    assertThrown!AccessDenied(requireRole(Principal("v", HdbRole.viewer, true), HdbRole.editor));
    requireRole(Principal("a", HdbRole.admin, true), HdbRole.editor);
}
