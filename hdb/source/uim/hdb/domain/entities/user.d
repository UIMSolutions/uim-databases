module uim.hdb.domain.entities.user;

import std.exception : enforce;
import std.string : chomp, split, strip, toLower, toUpper;

/// Rollen bauen aufeinander auf: jede enthält alle Rechte der vorherigen.
enum Role {
    viewer, // SELECT
    editor, // zusätzlich INSERT, UPDATE, DELETE und Transaktionen
    admin // zusätzlich CREATE, DROP, Wartung und Benutzerverwaltung
}

struct User {
    string name;
    string passwordHash;
    Role role;
    bool active = true;
}

/// Die angemeldete Identität einer Anfrage. Der Standardwert ist anonym.
struct Principal {
    string name;
    Role role;
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

string roleName(Role role) {
    final switch (role) {
    case Role.viewer:
        return "viewer";
    case Role.editor:
        return "editor";
    case Role.admin:
        return "admin";
    }
}

Role parseRole(string name) {
    switch (name.strip.toLower) {
    case "viewer":
        return Role.viewer;
    case "editor":
        return Role.editor;
    case "admin":
        return Role.admin;
    default:
        throw new Exception("Unknown role: " ~ name);
    }
}

/// Prüft die Rolle; wirft AuthenticationRequired oder AccessDenied.
void requireRole(Principal principal, Role role) {
    if (!principal.authenticated)
        throw new AuthenticationRequired;
    if (principal.role < role)
        throw new AccessDenied("Requires role " ~ roleName(role));
}

/// Nötige Rolle einer Anweisung. Normalisiert wie SqlService.executeIn, damit beide dasselbe Verb sehen;
/// Unbekanntes verlangt admin.
Role requiredRole(string statement) {
    auto words = statement.strip.chomp(";").strip.split();
    if (words.length == 0)
        return Role.viewer; // leere Anweisung lehnt der Kern ab
    switch (words[0].toUpper) {
    case "SELECT":
        return Role.viewer;
    case "INSERT":
    case "UPDATE":
    case "DELETE":
    case "BEGIN":
    case "COMMIT":
    case "ROLLBACK":
        return Role.editor;
    default:
        return Role.admin;
    }
}

unittest {
    import std.exception : assertThrown;

    assert(requiredRole("  select * from t;") == Role.viewer);
    assert(requiredRole("COMMIT;") == Role.editor);
    assert(requiredRole("delete from t") == Role.editor);
    assert(requiredRole("DROP TABLE t") == Role.admin);
    assert(requiredRole("CREATE TABLE t (a INTEGER)") == Role.admin);
    assert(requiredRole("VACUUM") == Role.admin);
    assert(requiredRole("SELECT* FROM t") == Role.admin); // für den Kern kein SELECT

    assert(parseRole(" Editor ") == Role.editor);
    assertThrown(parseRole("root"));

    assertThrown!AuthenticationRequired(requireRole(Principal.init, Role.viewer));
    assertThrown!AccessDenied(requireRole(Principal("v", Role.viewer, true), Role.editor));
    requireRole(Principal("a", Role.admin, true), Role.editor);
}
