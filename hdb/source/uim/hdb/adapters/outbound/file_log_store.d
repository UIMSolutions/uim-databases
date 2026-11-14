/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.adapters.outbound.file_log_store;

import uim.hdb;
import std.conv : octal;
import std.file : exists, mkdirRecurse, readText, rename, setAttributes;
import std.path : buildPath, dirName;
import std.stdio : File;
import std.traits : EnumMembers;
import vibe.data.json : Json, parseJsonString;

@safe:

/// Ausgehender Adapter: eine Datei je Protokoll im Verzeichnis `dir` (audit.jsonl, application.jsonl,
/// event.jsonl), ein JSON-Objekt je Zeile. Neue Einträge werden angehängt; nach dem Aufräumen wird die Datei
/// atomar ersetzt. Alle Einträge liegen zusätzlich im Speicher, gesucht wird dort.
/// Die Dateien sind nur für den Besitzer lesbar: das Audit-Protokoll nennt Benutzer und Adressen.
/// Unlesbare Zeilen (etwa nach einem Absturz mitten im Schreiben) werden beim Laden übersprungen.
final class FileLogStore : ILogStore {
    private string dir;
    private MemoryLogStore memory;
    private size_t skipped;

    this(string dir) {
        this.dir = dir;
        if (!exists(dir))
            mkdirRecurse(dir);
        memory = new MemoryLogStore;
        foreach (kind; [EnumMembers!LogKind])
            memory.restore(load(kind));
    }

    /// Zeilen, die beim Laden nicht lesbar waren.
    size_t skippedLines() const {
        return skipped;
    }

    LogEntry append(LogEntry entry) {
        auto stored = memory.append(entry);
        auto path = pathOf(stored.kind);
        immutable created = !exists(path);
        auto f = File(path, "a");
        scope (exit)
            f.close();
        if (created)
            setAttributes(path, octal!600);
        f.writeln(toJson(stored).toString);
        f.flush();
        return stored;
    }

    LogPage find(LogKind kind, scope bool delegate(ref const LogEntry) @safe match, ulong before, size_t limit) {
        return memory.find(kind, match, before, limit);
    }

    size_t prune(LogKind kind, scope LogRetention delegate(string scope_) @safe retentionOf) {
        auto removed = memory.prune(kind, retentionOf);
        if (removed)
            rewrite(kind);
        return removed;
    }

    private void rewrite(LogKind kind) {
        auto path = pathOf(kind);
        auto tmp = path ~ ".tmp";
        {
            auto f = File(tmp, "w");
            setAttributes(tmp, octal!600);
            foreach (ref e; memory.all(kind))
                f.writeln(toJson(e).toString);
            f.flush();
        }
        rename(tmp, path); // atomar auf POSIX
    }

    private LogEntry[] load(LogKind kind) {
        LogEntry[] result;
        auto path = pathOf(kind);
        if (!exists(path))
            return result;
        foreach (line; readText(path).splitter('\n')) {
            if (line.strip.length == 0)
                continue;
            try {
                auto e = fromJson(parseJsonString(line));
                e.kind = kind;
                result ~= e;
            } catch (Exception)
                ++skipped;
        }
        return result;
    }

    private string pathOf(LogKind kind) {
        return buildPath(dir, logKindName(kind) ~ ".jsonl");
    }
}

private Json toJson(ref const LogEntry e) {
    auto j = Json.emptyObject;
    j["id"] = e.id;
    j["time"] = e.time;
    j["severity"] = severityName(e.severity);
    j["scope"] = e.scope_;
    j["category"] = e.category;
    if (e.kind == LogKind.audit) {
        j["actor"] = e.actor;
        j["address"] = e.address;
        j["action"] = e.action;
        j["target"] = e.target;
        j["success"] = e.success;
    }
    j["message"] = e.message;
    return j;
}

private LogEntry fromJson(Json j) {
    string text(string key) {
        auto v = j[key];
        return v.isString ? v.get!string : "";
    }

    LogEntry e;
    e.id = j["id"].get!ulong;
    e.time = text("time");
    e.severity = parseSeverity(text("severity"));
    e.scope_ = text("scope");
    e.category = text("category");
    e.actor = text("actor");
    e.address = text("address");
    e.action = text("action");
    e.target = text("target");
    e.success = j["success"].type == Json.Type.bool_ ? j["success"].get!bool : true;
    e.message = text("message");
    return e;
}

/// Ausgehender Adapter: Einstellungen der Protokolle je Bereich als JSON-Datei.
/// Eine beschädigte Datei bricht den Start ab, statt stillschweigend zu den Voreinstellungen zurückzukehren:
/// sonst wäre etwa eine abgeschaltete Kategorie unbemerkt wieder an oder eine eingeschaltete aus.
final class FileLogSettingsStore : ILogSettingsStore {
    private string path;

    this(string path) {
        this.path = path;
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
    }

    LogPolicy[string] load() {
        LogPolicy[string] result;
        if (!exists(path))
            return result;
        auto document = parseJsonString(readText(path));
        foreach (string name, j; document["scopes"].byKeyValue) {
            LogPolicy policy;
            foreach (kind; [EnumMembers!LogKind]) {
                auto s = j[logKindName(kind)];
                if (s.type == Json.Type.object)
                    policy[kind] = settingsFromJson(s, policy[kind]);
            }
            result[name] = policy;
        }
        return result;
    }

    void save(LogPolicy[string] policies) {
        auto scopes = Json.emptyObject;
        foreach (name, policy; policies) {
            auto j = Json.emptyObject;
            foreach (kind; [EnumMembers!LogKind])
                j[logKindName(kind)] = settingsToJson(policy[kind]);
            scopes[name] = j;
        }
        auto document = Json.emptyObject;
        document["scopes"] = scopes;
        auto tmp = path ~ ".tmp";
        {
            auto f = File(tmp, "w");
            f.write(document.toPrettyString());
            f.flush();
        }
        rename(tmp, path); // atomar auf POSIX
    }
}

private Json settingsToJson(LogSettings s) {
    auto j = Json.emptyObject;
    j["enabled"] = s.enabled;
    j["minSeverity"] = severityName(s.minSeverity);
    j["retentionDays"] = s.retentionDays;
    j["maxEntries"] = s.maxEntries;
    auto cats = Json.emptyArray;
    foreach (c; s.categories)
        cats ~= Json(c);
    j["categories"] = cats;
    return j;
}

/// Fehlende Felder behalten den Wert von `base` (Dateien älterer Versionen).
private LogSettings settingsFromJson(Json j, LogSettings base) {
    auto s = base;
    if (j["enabled"].isBoolean)
        s.enabled = j["enabled"].get!bool;
    if (j["minSeverity"].isString)
        s.minSeverity = parseSeverity(j["minSeverity"].get!string);
    if (j["retentionDays"].isInteger)
        s.retentionDays = j["retentionDays"].get!int;
    if (j["maxEntries"].isInteger)
        s.maxEntries = j["maxEntries"].get!size_t;
    if (j["categories"].isArray) {
        s.categories = null;
        foreach (c; j["categories"].byValue)
            s.categories ~= c.get!string;
    }
    return s;
}

unittest {
    import std.algorithm : map;
    import std.array : array;
    import std.exception : assertThrown;
    import std.file : append, getAttributes, rmdirRecurse, tempDir, write;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir, "hdb-logs-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dir))
            rmdirRecurse(dir);

    auto store = new FileLogStore(buildPath(dir, "logs"));
    LogEntry a;
    a.kind = LogKind.audit;
    a.time = "2026-11-08T10:00:00.000Z";
    a.scope_ = "acme";
    a.category = "auth";
    a.actor = "ann";
    a.address = "10.0.0.1";
    a.action = "login";
    a.success = false;
    a.severity = LogSeverity.warning;
    a.message = "Invalid tenant, user name or password\nsecond line";
    store.append(a);
    LogEntry ev;
    ev.kind = LogKind.event;
    ev.time = "2026-11-08T11:00:00.000Z";
    ev.scope_ = "system";
    ev.category = "server";
    ev.message = "Server started";
    store.append(ev);
    a.time = "2026-11-08T12:00:00.000Z";
    a.success = true;
    a.severity = LogSeverity.info;
    a.message = "";
    store.append(a);
    assert((getAttributes(buildPath(dir, "logs", "audit.jsonl")) & octal!777) == octal!600);

    // Ein abgebrochener Schreibvorgang hinterlässt eine halbe Zeile
    append(buildPath(dir, "logs", "audit.jsonl"), `{"id":99,"time":"2026-`);

    bool everything(ref const LogEntry) {
        return true;
    }

    auto reloaded = new FileLogStore(buildPath(dir, "logs"));
    assert(reloaded.skippedLines == 1);
    auto page = reloaded.find(LogKind.audit, &everything, 0, 10);
    assert(page.total == 2 && page.entries[1].message == "Invalid tenant, user name or password\nsecond line");
    assert(!page.entries[1].success && page.entries[1].severity == LogSeverity.warning && page.entries[1].address == "10.0.0.1");
    assert(reloaded.find(LogKind.event, &everything, 0, 10).entries[0].message == "Server started");
    // Ids laufen nach dem Laden weiter
    auto next = reloaded.append(ev);
    assert(next.id == 4);

    // Aufräumen ersetzt die Datei
    assert(reloaded.prune(LogKind.audit, (string) => LogRetention("2026-11-08T11:00:00.000Z", 100)) == 1);
    auto pruned = new FileLogStore(buildPath(dir, "logs"));
    assert(pruned.skippedLines == 0);
    assert(pruned.find(LogKind.audit, &everything, 0, 10).entries.map!(e => e.time).array == ["2026-11-08T12:00:00.000Z"]);

    // Einstellungen
    auto settingsPath = buildPath(dir, "hdb-logs.json");
    auto settings = new FileLogSettingsStore(settingsPath);
    assert(settings.load().length == 0);
    LogPolicy policy;
    policy.audit.categories = ["auth", "data", "logs"];
    policy.event.minSeverity = LogSeverity.warning;
    policy.application.retentionDays = 7;
    settings.save(["acme": policy]);
    auto loaded = settings.load();
    assert(loaded["acme"].audit.categories == ["auth", "data", "logs"]);
    assert(loaded["acme"].event.minSeverity == LogSeverity.warning && loaded["acme"].application.retentionDays == 7);

    // Ältere Datei ohne manche Felder: Voreinstellung
    write(settingsPath, `{"scopes":{"beta":{"audit":{"enabled":false}}}}`);
    auto partial = settings.load()["beta"];
    assert(!partial.audit.enabled && partial.audit.retentionDays == 365 && partial.event.enabled);
    write(settingsPath, "{broken");
    assertThrown(settings.load());
}
