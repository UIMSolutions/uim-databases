/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.entities.permission;

import uim.hdb;

mixin(ShowModule!());

@safe:

/// Einzelnes Recht. Rollen sind Mengen davon.
///
/// Drei Ebenen:
///   Server (Rollen im Bereich system):  viewTenants, manageTenants, manageAccess, viewLogs, manageLogs
///   Mandant (Rolle eines Benutzers):     alle Datenrechte und create, transact, maintain, manage*, replicate, *Logs,
///                                        execute
///   Tabelle (Freigabe einer Rolle):      nur select, insert, update, delete, drop
enum Permission {
    select, /// SELECT auf einer Tabelle; sieht die Tabelle in Listen und Statistik
    insert,
    update,
    delete_,
    drop, /// DROP TABLE
    create, /// CREATE TABLE
    transact, /// BEGIN, COMMIT, ROLLBACK; eine offene Transaktion sperrt den ganzen Mandanten
    maintain, /// Checkpoint und Delta-Merge
    manageBackups, /// Sicherungen anlegen, herunterladen, hochladen, wiederherstellen, Zeitplan
    replicate, /// Änderungsstrom und Stand für Replikationsziele lesen (enthält alle Daten)
    manageReplication, /// den Mandanten zum Ziel einer Quelle machen
    manageAccess, /// Benutzer, Rollen und Tabellenfreigaben verwalten (im Bereich system: Systembenutzer)
    viewTenants, /// Mandantenliste lesen (nur Bereich system)
    manageTenants, /// Mandanten anlegen, ändern, löschen (nur Bereich system)
    viewLogs, /// Audit- und Ereignisprotokoll des Bereichs lesen; im Bereich des Servers auch das Anwendungsprotokoll
    manageLogs, /// Einstellungen der Protokolle des Bereichs ändern
    execute, /// gespeicherte Prozeduren aufrufen (CALL) und ansehen (SHOW PROCEDURE); jede Anweisung darin prüft die eigenen Rechte
    manageProcedures, /// gespeicherte Prozeduren anlegen, ersetzen und löschen
}

/// Name eines Rechts in APIs und Dateien.
string permissionName(Permission p) {
    return p == Permission.delete_ ? "delete" : p.to!string;
}

Permission parsePermission(string name) {
    auto n = name.strip;
    foreach (p; [EnumMembers!Permission])
        if (permissionName(p) == n)
            return p;
    throw new Exception("Unknown permission: " ~ name);
}

private import std.traits : EnumMembers;

/// Rechte, die sich einzeln je Tabelle freigeben lassen.
enum PermissionSet tablePermissions = PermissionSet.of(Permission.select, Permission.insert, Permission.update,
        Permission.delete_, Permission.drop);

/// Rechte, die im Bereich system gelten.
enum PermissionSet serverPermissions = PermissionSet.of(Permission.viewTenants, Permission.manageTenants,
        Permission.manageAccess, Permission.viewLogs, Permission.manageLogs);

/// Rechte, die in einem Mandanten gelten.
enum PermissionSet tenantPermissions = PermissionSet.of(Permission.select, Permission.insert, Permission.update,
        Permission.delete_, Permission.drop, Permission.create, Permission.transact, Permission.maintain,
        Permission.manageBackups, Permission.replicate, Permission.manageReplication, Permission.manageAccess,
        Permission.viewLogs, Permission.manageLogs, Permission.execute, Permission.manageProcedures);

/// Menge von Rechten.
struct PermissionSet {
    uint bits;

    static PermissionSet of(Permission[] items...) {
        PermissionSet s;
        foreach (p; items)
            s.bits |= 1u << p;
        return s;
    }

    static PermissionSet parse(string[] names) {
        PermissionSet s;
        foreach (n; names)
            s.bits |= 1u << parsePermission(n);
        return s;
    }

    bool has(Permission p) const {
        return (bits & (1u << p)) != 0;
    }

    bool empty() const {
        return bits == 0;
    }

    bool subsetOf(PermissionSet other) const {
        return (bits & ~other.bits) == 0;
    }

    PermissionSet opBinary(string op)(PermissionSet other) const if (op == "|" || op == "&") {
        return PermissionSet(mixin("bits " ~ op ~ " other.bits"));
    }

    Permission[] items() const {
        Permission[] result;
        foreach (p; [EnumMembers!Permission])
            if (has(p))
                result ~= p;
        return result;
    }

    string[] names() const {
        return items.map!permissionName.array;
    }
}

/// Rolle eines Mandanten oder des Bereichs system: ein Name für eine Menge von Rechten.
struct RoleDef {
    string tenant; // Bereich der Rolle; system für Serverrollen
    string name;
    string description;
    PermissionSet permissions;
    bool builtin; // vordefiniert, nicht änderbar oder löschbar
}

/// Zusätzliche Rolle eines Benutzers, auf Wunsch befristet.
/// Mit `table` gilt sie nur für diese Tabelle, und davon nur die Tabellenrechte der Rolle. Ohne `table` gilt sie im
/// ganzen Bereich wie eine zweite Rolle, etwa "admin bis Freitag 18 Uhr".
/// `from` und `until` sind UTC-Zeitpunkte (2026-11-08T18:00:00Z); leer heißt ohne Grenze. Außerhalb des Zeitraums
/// hat die Freigabe keine Wirkung; geprüft wird bei jeder Anfrage.
struct TableGrant {
    string table; // klein geschrieben; leer: ganzer Bereich
    string role;
    string from; // gilt ab (einschließlich)
    string until; // gilt bis (ausschließlich)

    bool temporary() const {
        return from.length || until.length;
    }

    /// active, scheduled oder expired
    string stateAt(SysTime now) const {
        if (from.length && now < SysTime.fromISOExtString(from))
            return "scheduled";
        if (until.length && now >= SysTime.fromISOExtString(until))
            return "expired";
        return "active";
    }

    bool activeAt(SysTime now) const {
        return stateAt(now) == "active";
    }
}

/// Zeitpunkt in kanonischer UTC-Form ohne Sekundenbruchteile; leer bleibt leer.
/// Akzeptiert ISO 8601 mit oder ohne Sekunden und Zeitzone; ohne Zeitzone gilt UTC (wie in den Formularen).
string normalizeInstant(string text) {
    import std.datetime.timezone : UTC;
    import std.regex : ctRegex, matchFirst;

    auto t = text.strip;
    if (t.length == 0)
        return "";
    if (!matchFirst(t, ctRegex!`^\d{4}-\d\d-\d\dT\d\d:\d\d$`).empty)
        t ~= ":00";
    if (matchFirst(t, ctRegex!`(Z|[+-]\d\d:\d\d)$`).empty)
        t ~= "Z";
    SysTime time;
    try
        time = SysTime.fromISOExtString(t);
    catch (Exception)
        throw new Exception("Invalid time: " ~ text ~ " (expected e.g. 2026-11-08T18:00:00Z)");
    time = time.toUTC;
    time.fracSecs = typeof(time.fracSecs).zero;
    return time.toISOExtString;
}

/// Vordefinierte Rollen. Ihre Namen entsprechen den bisherigen festen Rollen, bestehende Benutzer behalten so ihre Rechte.
RoleDef[] builtinRoles(string tenant) {
    if (tenant == systemTenant)
        return [
            RoleDef(tenant, "viewer", "Reads the tenant list", PermissionSet.of(Permission.viewTenants), true),
            RoleDef(tenant, "admin", "Manages tenants and system users", serverPermissions, true),
        ];
    auto viewer = PermissionSet.of(Permission.select, Permission.replicate, Permission.execute);
    auto editor = viewer | PermissionSet.of(Permission.insert, Permission.update, Permission.delete_, Permission.transact);
    return [
        RoleDef(tenant, "viewer", "Reads all tables", viewer, true),
        RoleDef(tenant, "editor", "Reads and changes rows in all tables", editor, true),
        RoleDef(tenant, "admin", "Everything in this tenant", tenantPermissions, true),
    ];
}

/// Rechte, die in einem Bereich vergeben werden können.
PermissionSet allowedPermissions(string tenant) {
    return tenant == systemTenant ? serverPermissions : tenantPermissions;
}

/// Name einer Rolle: wie Benutzernamen, 1 bis 64 Zeichen aus Buchstaben, Ziffern, '_', '-' und '.'.
string validRoleName(string name) {
    auto normalized = name.strip.toLower;
    enforce(normalized.length >= 1 && normalized.length <= 64
            && normalized.all!(c => isAlphaNum(c) || c == '_' || c == '-' || c == '.'),
        "Role names use 1 to 64 letters, digits, '_', '-' or '.'");
    return normalized;
}

unittest {
    import std.exception : assertThrown;

    auto s = PermissionSet.parse(["select", "delete"]);
    assert(s.has(Permission.select) && s.has(Permission.delete_) && !s.has(Permission.insert));
    assert(s.names == ["select", "delete"]);
    assert(s.subsetOf(tablePermissions) && !tenantPermissions.subsetOf(tablePermissions));
    assert((s & PermissionSet.of(Permission.select)).names == ["select"]);
    assertThrown(PermissionSet.parse(["root"]));
    assert(parsePermission(" manageTenants ") == Permission.manageTenants);

    auto roles = builtinRoles("acme");
    assert(roles.map!(r => r.name).array == ["viewer", "editor", "admin"]);
    assert(roles[1].permissions.has(Permission.update) && !roles[1].permissions.has(Permission.create));
    assert(roles[2].permissions == tenantPermissions);
    assert(builtinRoles(systemTenant)[1].permissions == serverPermissions);
    assert(!tenantPermissions.has(Permission.manageTenants) && serverPermissions.has(Permission.manageAccess));

    import std.datetime.timezone : UTC;
    import core.time : hours;

    assert(normalizeInstant("2026-11-08T18:00") == "2026-11-08T18:00:00Z");
    assert(normalizeInstant(" 2026-11-08T18:00:00+01:00 ") == "2026-11-08T17:00:00Z");
    assert(normalizeInstant("2026-11-08T18:00:00.123Z") == "2026-11-08T18:00:00Z");
    assert(normalizeInstant("") == "");
    assertThrown(normalizeInstant("tomorrow"));
    assertThrown(normalizeInstant("2026-13-01T00:00"));

    auto noon = SysTime.fromISOExtString("2026-11-08T12:00:00Z");
    auto g = TableGrant("", "admin", "2026-11-08T10:00:00Z", "2026-11-08T14:00:00Z");
    assert(g.temporary && g.activeAt(noon));
    assert(g.stateAt(noon - 3.hours) == "scheduled" && g.stateAt(noon + 2.hours) == "expired");
    assert(TableGrant("t", "viewer").activeAt(noon) && !TableGrant("t", "viewer").temporary);

    assert(validRoleName(" Accountant ") == "accountant");
    assertThrown(validRoleName("a b"));
    assertThrown(validRoleName(""));
}
