module uim.hdb.adapters.outbound.file_user_store;

import uim.hdb;
import std.conv : octal;
import std.file : exists, mkdirRecurse, readText, rename, setAttributes;
import std.path : dirName;
import std.stdio : File;
import vibe.data.json : Json, parseJsonString;

@safe:

/// Ausgehender Adapter: Benutzer als JSON-Datei. Sie liegt getrennt vom Anweisungsprotokoll, damit Passwort-Hashes
/// nicht in Checkpoints oder Sicherungen der Daten landen, und ist nur für den Besitzer lesbar.
/// Eine beschädigte Datei bricht den Start ab, statt die Benutzer stillschweigend zu verlieren.
final class FileUserStore : IUserStore {
    private string path;

    this(string path) {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    HdbUser[] load() {
        HdbUser[] users;
        if (!exists(path))
            return users;
        // Benutzer aus der Zeit vor den Mandanten gehören zu default
        // Benutzer ohne Tabellenfreigaben stammen aus der Zeit vor RBAC
        foreach (j; parseJsonString(readText(path))["users"].byValue) {
            TableGrant[] grants;
            if (j["grants"].type != Json.Type.undefined)
                foreach (g; j["grants"].byValue)
                    grants ~= TableGrant(g["table"].get!string, g["role"].get!string);
            users ~= HdbUser(j["name"].get!string, j["passwordHash"].get!string,
                j["role"].get!string, j["active"].get!bool,
                j["tenant"].type == Json.Type.undefined ? defaultTenant : j["tenant"].get!string, grants);
        }
        return users;
    }

    void save(HdbUser[] users) {
        auto list = Json.emptyArray;
        foreach (u; users) {
            auto j = Json.emptyObject;
            j["name"] = u.name;
            j["passwordHash"] = u.passwordHash;
            j["role"] = u.role;
            j["active"] = u.active;
            j["tenant"] = u.tenant;
            auto grants = Json.emptyArray;
            foreach (g; u.grants) {
                auto gj = Json.emptyObject;
                gj["table"] = g.table;
                gj["role"] = g.role;
                grants ~= gj;
            }
            j["grants"] = grants;
            list ~= j;
        }
        auto document = Json.emptyObject;
        document["users"] = list;

        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        setAttributes(tmp, octal!600); // vor dem Schreiben: die Hashes sind nie für andere lesbar
        f.write(document.toPrettyString());
        f.flush();
        f.close();
        rename(tmp, path); // atomar auf POSIX
    }
}

unittest {
    import std.file : getAttributes, remove, tempDir, write;
    import std.exception : assertThrown;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir, "hdb-users-" ~ randomUUID().toString ~ ".json");
    scope (exit)
        if (exists(path))
            remove(path);

    auto store = new FileUserStore(path);
    assert(store.load().length == 0);
    auto saved = [HdbUser("a", "hash", "editor", false),
        HdbUser("a", "h2", "", true, "acme", [TableGrant("orders", "viewer"), TableGrant("orders", "clerk")])];
    store.save(saved);
    assert(store.load() == saved);
    assert((getAttributes(path) & octal!777) == octal!600);

    // Altbestand ohne Mandant
    write(path, `{"users":[{"name":"old","passwordHash":"x","role":"admin","active":true}]}`);
    assert(store.load() == [HdbUser("old", "x", "admin", true, defaultTenant)]);

    write(path, "{broken");
    assertThrown(store.load());
}

/// Ausgehender Adapter: eigene Rollen aller Bereiche als JSON-Datei. Vordefinierte Rollen stehen nicht darin.
/// Eine beschädigte Datei oder ein unbekanntes Recht bricht den Start ab.
final class FileRoleStore : IRoleStore {
    private string path;

    this(string path) {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    RoleDef[] load() {
        RoleDef[] roles;
        if (!exists(path))
            return roles;
        foreach (j; parseJsonString(readText(path))["roles"].byValue) {
            string[] permissions;
            foreach (p; j["permissions"].byValue)
                permissions ~= p.get!string;
            roles ~= RoleDef(j["tenant"].get!string, validRoleName(j["name"].get!string), j["description"].get!string,
                PermissionSet.parse(permissions), false);
        }
        return roles;
    }

    void save(RoleDef[] roles) {
        auto list = Json.emptyArray;
        foreach (r; roles) {
            auto j = Json.emptyObject;
            j["tenant"] = r.tenant;
            j["name"] = r.name;
            j["description"] = r.description;
            auto permissions = Json.emptyArray;
            foreach (n; r.permissions.names)
                permissions ~= Json(n);
            j["permissions"] = permissions;
            list ~= j;
        }
        auto document = Json.emptyObject;
        document["roles"] = list;
        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        f.write(document.toPrettyString());
        f.flush();
        f.close();
        rename(tmp, path);
    }
}

unittest {
    import std.exception : assertThrown;
    import std.file : remove, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir, "hdb-roles-" ~ randomUUID().toString ~ ".json");
    scope (exit)
        if (exists(path))
            remove(path);
    auto store = new FileRoleStore(path);
    assert(store.load().length == 0);
    auto roles = [RoleDef("acme", "clerk", "Enters orders", PermissionSet.of(Permission.select, Permission.insert), false),
        RoleDef("system", "ops", "", PermissionSet.of(Permission.viewTenants), false)];
    store.save(roles);
    assert(store.load() == roles);
    write(path, `{"roles":[{"tenant":"a","name":"x","description":"","permissions":["root"]}]}`);
    assertThrown(store.load());
}
