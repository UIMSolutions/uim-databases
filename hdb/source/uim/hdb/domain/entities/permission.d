/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.entities.permission;

import uim.hdb.domain.entities.tenant : systemTenant;
import std.algorithm : all, canFind, map, sort;
import std.array : array;
import std.ascii : isAlphaNum;
import std.conv : to;
import std.exception : enforce;
import std.string : strip, toLower;

/// Einzelnes Recht. Rollen sind Mengen davon.
///
/// Drei Ebenen:
///   Server (Rollen im Bereich system):  viewTenants, manageTenants, manageAccess
///   Mandant (Rolle eines Benutzers):     alle Datenrechte und create, transact, maintain, manage*, replicate
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
        Permission.manageAccess);

/// Rechte, die in einem Mandanten gelten.
enum PermissionSet tenantPermissions = PermissionSet.of(Permission.select, Permission.insert, Permission.update,
        Permission.delete_, Permission.drop, Permission.create, Permission.transact, Permission.maintain,
        Permission.manageBackups, Permission.replicate, Permission.manageReplication, Permission.manageAccess);

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

/// Freigabe einer Rolle für eine einzelne Tabelle. Davon gelten nur die Tabellenrechte der Rolle.
struct TableGrant {
    string table; // klein geschrieben
    string role;
}

/// Vordefinierte Rollen. Ihre Namen entsprechen den bisherigen festen Rollen, bestehende Benutzer behalten so ihre Rechte.
RoleDef[] builtinRoles(string tenant) {
    if (tenant == systemTenant)
        return [
            RoleDef(tenant, "viewer", "Reads the tenant list", PermissionSet.of(Permission.viewTenants), true),
            RoleDef(tenant, "admin", "Manages tenants and system users", serverPermissions, true),
        ];
    auto viewer = PermissionSet.of(Permission.select, Permission.replicate);
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

    assert(validRoleName(" Accountant ") == "accountant");
    assertThrown(validRoleName("a b"));
    assertThrown(validRoleName(""));
}
