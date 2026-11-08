module uim.hdb.adapters.outbound.file_tenant_store;

import uim.hdb;
import std.file : exists, mkdirRecurse, readText, rename;
import std.path : dirName;
import std.stdio : File;
import vibe.data.json : Json, parseJsonString;

/// Ausgehender Adapter: Liste der Mandanten als JSON-Datei. Eine beschädigte Datei bricht den Start ab,
/// statt Mandanten stillschweigend zu verlieren.
final class FileTenantStore : ITenantStore {
    private string path;

    this(string path) {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    Tenant[] load() {
        Tenant[] tenants;
        if (!exists(path))
            return tenants;
        foreach (j; parseJsonString(readText(path))["tenants"])
            tenants ~= Tenant(validTenantName(j["name"].get!string), j["label"].get!string, j["active"].get!bool);
        return tenants;
    }

    void save(Tenant[] tenants) {
        auto list = Json.emptyArray;
        foreach (t; tenants) {
            auto j = Json.emptyObject;
            j["name"] = t.name;
            j["label"] = t.label;
            j["active"] = t.active;
            list ~= j;
        }
        auto document = Json.emptyObject;
        document["tenants"] = list;

        auto tmp = path ~ ".tmp";
        auto f = File(tmp, "w");
        f.write(document.toPrettyString());
        f.flush();
        f.close();
        rename(tmp, path); // atomar auf POSIX
    }
}

unittest {
    import std.exception : assertThrown;
    import std.file : remove, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir, "hdb-tenants-" ~ randomUUID().toString ~ ".json");
    scope (exit)
        if (exists(path))
            remove(path);

    auto store = new FileTenantStore(path);
    assert(store.load().length == 0);
    store.save([Tenant("acme", "Acme Corp", false), Tenant("default", "Default", true)]);
    assert(store.load() == [Tenant("acme", "Acme Corp", false), Tenant("default", "Default", true)]);

    write(path, `{"tenants":[{"name":"../x","label":"","active":true}]}`);
    assertThrown(store.load());
    write(path, "{broken");
    assertThrown(store.load());
}
