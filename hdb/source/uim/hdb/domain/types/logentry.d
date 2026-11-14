/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.logentry;

import uim.hdb;
import std.algorithm : canFind, sort, uniq;
import std.array : array;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format : format;
import std.string : strip, toLower;

mixin(ShowModule!());

@safe:

/// Ein Eintrag in einem der drei Protokolle. Nicht jede Art nutzt jedes Feld:
///   audit:       actor, address, action, target, success und message (Grund eines Fehlschlags)
///   event:       category und message
///   application: category ist das D-Modul, das gemeldet hat
struct LogEntry {
    ulong id; // vom Speicher vergeben, steigt mit der Zeit
    string time; // ISO 8601 in UTC
    LogKind kind;
    LogSeverity severity = LogSeverity.info;
    string scope_; // Mandant oder system; Einträge des Servers stehen im Bereich des Servers
    string category;
    string actor;
    string address;
    string action;
    string target;
    bool success = true;
    string message;
}

/// Zeitstempel eines Eintrags: UTC mit Millisekunden in fester Länge, damit Texte so sortieren wie die Zeiten.
string logTime(SysTime time) {
    auto t = time.toUTC;
    return format("%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", t.year, cast(int) t.month, t.day, t.hour, t.minute,
        t.second, t.fracSecs.total!"msecs");
}

/// Kategorien des Audit-Protokolls. `logs` (Änderungen an den Protokolleinstellungen) wird immer aufgezeichnet:
/// wer die Aufzeichnung abschaltet, soll das nicht unbemerkt tun können.
immutable string[] auditCategories = [
    "auth", // Anmelden, Abmelden, fehlgeschlagene Anmeldungen, eigenes Passwort
    "users", // Benutzer anlegen, ändern, löschen, Passwörter zurücksetzen, Freigaben
    "roles", // eigene Rollen
    "network", // erlaubte Netze
    "tenants", // Mandanten (Bereich system)
    "backups", // Sicherungen anlegen, herunterladen, hochladen, wiederherstellen, löschen, Zeitplan
    "replication", // Ziel einrichten, stoppen, neu abgleichen, vollständigen Stand lesen
    "schema", // CREATE, DROP, ALTER
    "data", // INSERT, UPDATE, DELETE (nur Tabelle und Verb, keine Werte)
    "maintenance", // Checkpoint, Delta-Merge
    "logs", // Protokolleinstellungen
];

/// Kategorien des Audit-Protokolls, die sich nicht abwählen lassen.
immutable string[] mandatoryAuditCategories = ["logs"];

/// Kategorien des Ereignisprotokolls.
immutable string[] eventCategories = [
    "server", // Start, Ende, Ersteinrichtung
    "backups", // geplante Sicherungen
    "replication", // Zustandswechsel und Fehler der Replikation
];

/// Kategorien, die eine Art kennt; das Anwendungsprotokoll filtert nicht nach Kategorien.
immutable(string)[] categoriesOf(LogKind kind) {
    final switch (kind) {
    case LogKind.audit:
        return auditCategories;
    case LogKind.event:
        return eventCategories;
    case LogKind.application:
        return null;
    }
}

immutable(string)[] mandatoryCategoriesOf(LogKind kind) {
    return kind == LogKind.audit ? mandatoryAuditCategories : null;
}

/// Einstellungen eines Protokolls in einem Bereich.
struct LogSettings {
    bool enabled = true;
    LogSeverity minSeverity = LogSeverity.info;
    int retentionDays = 90; // ältere Einträge werden gelöscht
    size_t maxEntries = 20_000; // darüber hinaus werden die ältesten gelöscht
    string[] categories; // aufgezeichnete Kategorien; bei application leer

    /// Ob ein Eintrag aufgezeichnet wird.
    bool accepts(LogKind kind, LogSeverity severity, string category) const {
        if (kind == LogKind.audit && mandatoryAuditCategories.canFind(category))
            return true;
        if (!enabled || severity < minSeverity)
            return false;
        return categoriesOf(kind).length == 0 || categories.canFind(category);
    }
}

enum int maxRetentionDays = 3650;
enum size_t minEntries = 100;
enum size_t maxEntriesLimit = 1_000_000;

/// Prüft und vereinheitlicht Einstellungen: Kategorien klein, sortiert, ohne Doppelte, Pflichtkategorien immer dabei.
LogSettings validated(LogKind kind, LogSettings s) {
    enforce(s.retentionDays >= 1 && s.retentionDays <= maxRetentionDays,
        "Retention must be between 1 and " ~ maxRetentionDays.to!string ~ " days");
    enforce(s.maxEntries >= minEntries && s.maxEntries <= maxEntriesLimit,
        "Maximum entries must be between " ~ minEntries.to!string ~ " and " ~ maxEntriesLimit.to!string);
    auto known = categoriesOf(kind);
    string[] cats;
    foreach (c; s.categories) {
        auto n = c.strip.toLower;
        enforce(known.canFind(n), known.length
                ? "Unknown " ~ logKindName(kind) ~ " category: " ~ c
                : "The " ~ logKindName(kind) ~ " log has no categories");
        cats ~= n;
    }
    foreach (m; mandatoryCategoriesOf(kind))
        cats ~= m;
    LogSettings result = s;
    result.categories = cats.sort.uniq.array;
    return result;
}

/// Voreinstellungen: Audit ein Jahr ohne die Kategorie data, Ereignisse 90 Tage, Anwendung 30 Tage.
LogSettings defaultSettings(LogKind kind) {
    final switch (kind) {
    case LogKind.audit:
        string[] audit;
        foreach (c; auditCategories)
            if (c != "data")
                audit ~= c;
        return validated(kind, LogSettings(true, LogSeverity.info, 365, 50_000, audit));
    case LogKind.event:
        string[] events;
        foreach (c; eventCategories)
            events ~= c;
        return validated(kind, LogSettings(true, LogSeverity.info, 90, 20_000, events));
    case LogKind.application:
        return LogSettings(true, LogSeverity.info, 30, 20_000, null);
    }
}

/// Einstellungen aller Protokolle eines Bereichs. Ein Mandant hat kein eigenes Anwendungsprotokoll.
struct LogPolicy {
    LogSettings audit = defaultSettings(LogKind.audit);
    LogSettings application = defaultSettings(LogKind.application);
    LogSettings event = defaultSettings(LogKind.event);

    ref inout(LogSettings) opIndex(LogKind kind) inout return {
        final switch (kind) {
        case LogKind.audit:
            return audit;
        case LogKind.application:
            return application;
        case LogKind.event:
            return event;
        }
    }
}

unittest {
    import std.exception : assertThrown;

    auto audit = defaultSettings(LogKind.audit);
    assert(!audit.categories.canFind("data") && audit.categories.canFind("auth") && audit.categories.canFind("logs"));
    assert(audit.accepts(LogKind.audit, LogSeverity.info, "auth"));
    assert(!audit.accepts(LogKind.audit, LogSeverity.info, "data"));

    // Abgeschaltet: nur noch die Pflichtkategorie
    audit.enabled = false;
    assert(!audit.accepts(LogKind.audit, LogSeverity.error, "auth") && audit.accepts(LogKind.audit, LogSeverity.info, "logs"));

    auto s = validated(LogKind.audit, LogSettings(true, LogSeverity.warning, 7, 100, [" Auth ", "auth", "schema"]));
    assert(s.categories == ["auth", "logs", "schema"]);
    assert(!s.accepts(LogKind.audit, LogSeverity.info, "auth") && s.accepts(LogKind.audit, LogSeverity.warning, "auth"));
    assertThrown(validated(LogKind.audit, LogSettings(true, LogSeverity.info, 0, 100)));
    assertThrown(validated(LogKind.audit, LogSettings(true, LogSeverity.info, 1, 99)));
    assertThrown(validated(LogKind.event, LogSettings(true, LogSeverity.info, 1, 100, ["auth"])));
    assertThrown(validated(LogKind.application, LogSettings(true, LogSeverity.info, 1, 100, ["server"])));

    auto app = defaultSettings(LogKind.application);
    assert(app.accepts(LogKind.application, LogSeverity.info, "vibe.http.server"));
    assert(!app.accepts(LogKind.application, LogSeverity.debug_, "app"));

    import core.time : msecs;

    auto t = SysTime.fromISOExtString("2026-11-08T18:00:00+01:00");
    assert(logTime(t) == "2026-11-08T17:00:00.000Z" && logTime(t + 5.msecs) == "2026-11-08T17:00:00.005Z");
    assert(logTime(t) < logTime(t + 5.msecs));

    LogPolicy policy;
    policy[LogKind.event].retentionDays = 5;
    assert(policy.event.retentionDays == 5 && policy[LogKind.audit].retentionDays == 365);
}
