module uim.hdb.adapters.outbound.file_user_store;

import uim.hdb.application.ports;
import uim.hdb.domain.entities.user;
import std.conv : octal;
import std.file : exists, mkdirRecurse, readText, rename, setAttributes;
import std.path : dirName;
import std.stdio : File;
import vibe.data.json : Json, parseJsonString;

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

    User[] load() {
        User[] users;
        if (!exists(path))
            return users;
        foreach (j; parseJsonString(readText(path))["users"])
            users ~= User(j["name"].get!string, j["passwordHash"].get!string,
                parseRole(j["role"].get!string), j["active"].get!bool);
        return users;
    }

    void save(User[] users) {
        auto list = Json.emptyArray;
        foreach (u; users) {
            auto j = Json.emptyObject;
            j["name"] = u.name;
            j["passwordHash"] = u.passwordHash;
            j["role"] = roleName(u.role);
            j["active"] = u.active;
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
    store.save([User("a", "hash", Role.editor, false)]);
    assert(store.load() == [User("a", "hash", Role.editor, false)]);
    assert((getAttributes(path) & octal!777) == octal!600);

    write(path, "{broken");
    assertThrown(store.load());
}
