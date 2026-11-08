/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.application.services.logging;

import uim.hdb;
import core.time : days;
import std.algorithm : canFind;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.exception : enforce;
import std.format : format;
import std.array : join;
import std.string : CaseSensitive, icmp, indexOf, strip, toLower;
import std.traits : EnumMembers;

@safe:

enum size_t maxLogPage = 1000;

/// Die drei Protokolle: nimmt Einträge an, filtert sie nach den Einstellungen ihres Bereichs, sucht und räumt auf.
///
/// Bereiche: jeder Mandant hat ein eigenes Audit- und Ereignisprotokoll mit eigenen Einstellungen. Der Bereich des
/// Servers (system, im Einzelmandanten-Betrieb default) hat zusätzlich das Anwendungsprotokoll und sieht die
/// Einträge aller Bereiche. Mandanten sehen nur ihre eigenen.
///
/// Nicht threadsicher: Einträge aus anderen Threads gehen über ApplicationLogCapture, das sie im Hauptthread abgibt.
final class LogService : ILogUseCase, IAuditTrail, IEventLog {
    private ILogStore store;
    private ILogSettingsStore settingsStore;
    private LogPolicy[string] policies;
    private string serverScope;
    private bool delegate(string) @safe knownScope;
    private SysTime delegate() @safe now;
    private size_t dropped;

    /// Wird nach einer Änderung der Einstellungen des Anwendungsprotokolls aufgerufen.
    void delegate(LogSettings) @safe onApplicationSettings;

    /// `knownScope`: ob es einen Bereich gibt. Einträge für unbekannte Bereiche (etwa eine Anmeldung bei einem
    /// erfundenen Mandanten) landen im Bereich des Servers, damit niemand beliebig viele Bereiche anlegen kann.
    this(ILogStore store, ILogSettingsStore settingsStore, string serverScope = systemTenant,
        bool delegate(string) @safe knownScope = null, SysTime delegate() @safe now = null) {
        this.store = store;
        this.settingsStore = settingsStore;
        this.serverScope = serverScope;
        this.knownScope = knownScope;
        this.now = now !is null ? now : () => Clock.currTime(UTC());
        foreach (name, policy; settingsStore.load()) {
            LogPolicy checked;
            foreach (kind; [EnumMembers!LogKind])
                checked[kind] = validated(kind, policy[kind]);
            policies[name] = checked;
        }
    }

    /// Bereich, dem das Anwendungsprotokoll gehört.
    string serverScopeName() const {
        return serverScope;
    }

    /// Einträge, die wegen eines Fehlers der Ablage verloren gingen.
    size_t droppedEntries() const {
        return dropped;
    }

    LogSettings applicationSettings() {
        return policyOf(serverScope).application;
    }

    // --- Aufzeichnen ---

    void audit(AuditRecord r) nothrow {
        try {
            auto scope_ = resolveScope(r.scope_);
            immutable severity = r.success ? LogSeverity.info : LogSeverity.warning;
            if (!policyOf(scope_).audit.accepts(LogKind.audit, severity, r.category))
                return;
            LogEntry e;
            e.kind = LogKind.audit;
            e.severity = severity;
            e.scope_ = scope_;
            e.category = r.category;
            e.actor = r.actor;
            e.address = r.address;
            e.action = r.action;
            e.target = r.target;
            e.success = r.success;
            e.message = r.message;
            append(e);
        } catch (Exception)
            ++dropped;
    }

    void event(string scope_, string category, LogSeverity severity, string message) nothrow {
        try {
            auto s = resolveScope(scope_);
            if (!policyOf(s).event.accepts(LogKind.event, severity, category))
                return;
            LogEntry e;
            e.kind = LogKind.event;
            e.severity = severity;
            e.scope_ = s;
            e.category = category;
            e.message = message;
            append(e);
        } catch (Exception)
            ++dropped;
    }

    /// Eine Meldung des Servers. `time` leer: jetzt.
    void application(LogSeverity severity, string source, string message, string time = "") nothrow {
        try {
            if (!policyOf(serverScope).application.accepts(LogKind.application, severity, source))
                return;
            LogEntry e;
            e.kind = LogKind.application;
            e.severity = severity;
            e.scope_ = serverScope;
            e.category = source;
            e.message = message;
            e.time = time;
            append(e);
        } catch (Exception)
            ++dropped;
    }

    /// Löscht, was die Aufbewahrung überschreitet; für den Zeitgeber der Anwendung.
    size_t maintain() {
        size_t removed;
        foreach (kind; [EnumMembers!LogKind])
            removed += maintain(kind);
        return removed;
    }

    private size_t maintain(LogKind kind) {
        auto current = now();
        return store.prune(kind, (string s) {
            auto settings = policyOf(kind == LogKind.application ? serverScope : s)[kind];
            return LogRetention(logTime(current - settings.retentionDays.days), settings.maxEntries);
        });
    }

    // --- ILogUseCase ---

    LogInfo[] logs(Principal actor) {
        requirePermission(actor, Permission.viewLogs);
        LogInfo[] result;
        foreach (kind; [EnumMembers!LogKind])
            if (kind != LogKind.application || actor.tenant == serverScope)
                result ~= LogInfo(kind, policyOf(actor.tenant)[kind], actor.can(Permission.manageLogs));
        return result;
    }

    LogPage read(Principal actor, LogQuery q) {
        requirePermission(actor, Permission.viewLogs);
        requireKind(actor, q.kind);
        enforce(q.limit >= 1 && q.limit <= maxLogPage, "limit must be between 1 and " ~ maxLogPage.to!string);
        // Nur der Bereich system sieht über alle Mandanten; im Einzelmandanten-Betrieb gibt es nur einen
        immutable scopeFilter = actor.tenant == systemTenant ? q.scope_.strip.toLower : actor.tenant;
        immutable from = boundary(q.from), until = boundary(q.until);
        immutable category = q.category.strip.toLower, who = q.actor.strip, text = q.text.strip;
        immutable minimum = q.minSeverity;

        bool match(ref const LogEntry e) {
            return (scopeFilter.length == 0 || e.scope_ == scopeFilter) && e.severity >= minimum
                && (category.length == 0 || e.category == category)
                && (who.length == 0 || icmp(e.actor, who) == 0)
                && (from.length == 0 || e.time >= from) && (until.length == 0 || e.time < until)
                && (text.length == 0 || contains(e.action, text) || contains(e.target, text)
                    || contains(e.message, text) || contains(e.category, text));
        }

        return store.find(q.kind, &match, q.before, q.limit);
    }

    LogSettings settings(Principal actor, LogKind kind) {
        requirePermission(actor, Permission.viewLogs);
        requireKind(actor, kind);
        return policyOf(actor.tenant)[kind];
    }

    LogSettings configure(Principal actor, LogKind kind, LogSettings next, string address) {
        auto record = AuditRecord(actor.tenant, actor.name, address, "logs", "configure", logKindName(kind));
        LogSettings checked;
        try {
            requirePermission(actor, Permission.manageLogs);
            requireKind(actor, kind);
            checked = validated(kind, next);
            auto all = policies.dup;
            auto policy = policyOf(actor.tenant);
            policy[kind] = checked;
            all[actor.tenant] = policy;
            settingsStore.save(all); // erst gespeichert, dann gültig
            policies = all;
        } catch (Exception e) {
            record.success = false;
            record.message = e.msg;
            audit(record);
            throw e;
        }
        record.message = describe(kind, checked);
        audit(record);
        if (kind == LogKind.application && onApplicationSettings !is null)
            onApplicationSettings(checked);
        maintain(kind); // kürzere Aufbewahrung wirkt sofort
        return checked;
    }

    // --- Hilfen ---

    private LogEntry append(LogEntry e) {
        if (e.time.length == 0)
            e.time = logTime(now());
        return store.append(e);
    }

    private LogPolicy policyOf(string scope_) {
        if (auto p = scope_ in policies)
            return *p;
        return LogPolicy.init;
    }

    private string resolveScope(string scope_) {
        auto s = scope_.strip.toLower;
        if (s.length == 0 || s == serverScope)
            return serverScope;
        if (knownScope !is null && !knownScope(s))
            return serverScope;
        return s;
    }

    private void requireKind(Principal actor, LogKind kind) {
        if (kind == LogKind.application && actor.tenant != serverScope)
            throw new AccessDenied("The application log belongs to the server and is only available in the "
                    ~ serverScope ~ " area");
    }
}

/// Zeitgrenze einer Suche im Format der Einträge; leer bleibt leer.
private string boundary(string text) {
    auto normalized = normalizeInstant(text);
    return normalized.length ? logTime(SysTime.fromISOExtString(normalized)) : "";
}

private bool contains(string haystack, string needle) {
    return haystack.indexOf(needle, CaseSensitive.no) >= 0;
}

/// Einstellungen als Text für das Audit-Protokoll.
string describe(LogKind kind, LogSettings s) {
    auto text = format("enabled=%s minSeverity=%s retentionDays=%s maxEntries=%s", s.enabled,
        severityName(s.minSeverity), s.retentionDays, s.maxEntries);
    if (categoriesOf(kind).length)
        text ~= " categories=" ~ s.categories.join(",");
    return text;
}

/// Einträge nur im Speicher; Grundlage von FileLogStore und Ablage für Tests.
final class MemoryLogStore : ILogStore {
    private LogEntry[][LogKind] entries; // je Art, ältester zuerst
    private ulong lastId;

    LogEntry append(LogEntry entry) {
        entry.id = ++lastId;
        entries[entry.kind] ~= entry;
        return entry;
    }

    LogPage find(LogKind kind, scope bool delegate(ref const LogEntry) @safe match, ulong before, size_t limit) {
        LogPage page;
        auto list = kind in entries;
        if (list is null)
            return page;
        foreach_reverse (ref e; *list) {
            if (!match(e))
                continue;
            ++page.total;
            if ((before == 0 || e.id < before) && page.entries.length < limit)
                page.entries ~= e;
        }
        return page;
    }

    size_t prune(LogKind kind, scope LogRetention delegate(string scope_) @safe retentionOf) {
        auto list = kind in entries;
        if (list is null)
            return 0;
        LogRetention[string] retention;
        size_t[string] kept;
        LogEntry[] survivors;
        foreach_reverse (ref e; *list) {
            auto r = e.scope_ in retention;
            if (r is null) {
                retention[e.scope_] = retentionOf(e.scope_);
                r = e.scope_ in retention;
            }
            auto count = kept.get(e.scope_, 0);
            if (count >= r.maxEntries || e.time < r.cutoff)
                continue;
            kept[e.scope_] = count + 1;
            survivors ~= e;
        }
        immutable removed = list.length - survivors.length;
        if (removed == 0)
            return 0;
        // survivors ist neuester zuerst
        LogEntry[] ordered;
        ordered.reserve(survivors.length);
        foreach_reverse (ref e; survivors)
            ordered ~= e;
        entries[kind] = ordered;
        return removed;
    }

    /// Alle Einträge einer Art, ältester zuerst.
    const(LogEntry)[] all(LogKind kind) const {
        if (auto list = kind in entries)
            return *list;
        return null;
    }

    /// Übernimmt gespeicherte Einträge mit ihren Ids (beim Laden), ältester zuerst.
    void restore(LogEntry[] loaded) {
        foreach (e; loaded) {
            entries[e.kind] ~= e;
            if (e.id > lastId)
                lastId = e.id;
        }
    }
}

/// Einstellungen nur im Speicher.
final class MemoryLogSettingsStore : ILogSettingsStore {
    LogPolicy[string] saved;

    LogPolicy[string] load() {
        return saved.dup;
    }

    void save(LogPolicy[string] policies) {
        saved = policies.dup;
    }
}

unittest {
    import std.algorithm : map;
    import std.array : array;
    import std.exception : assertThrown, collectException;
    import core.time : hours, msecs;

    auto clock = SysTime.fromISOExtString("2026-11-08T12:00:00Z");
    auto store = new MemoryLogStore;
    auto settings = new MemoryLogSettingsStore;
    auto known = ["system", "acme", "beta"];
    auto logs = new LogService(store, settings, systemTenant, (string s) => known.canFind(s), () => clock);

    auto sys = Principal("sys", HdbRole.admin, true, systemTenant);
    auto acmeAdmin = Principal("ann", HdbRole.admin, true, "acme");
    auto acmeViewer = Principal("vic", HdbRole.viewer, true, "acme");
    auto betaAdmin = Principal("bob", HdbRole.admin, true, "beta");

    // Aufzeichnen nach den Voreinstellungen: data ist im Audit aus, debug im Anwendungsprotokoll
    logs.audit(AuditRecord("acme", "ann", "10.0.0.1", "auth", "login"));
    logs.audit(AuditRecord("acme", "ann", "10.0.0.1", "data", "insert", "orders"));
    logs.audit(AuditRecord("ACME", "eve", "10.0.0.9", "auth", "login", "", false, "Invalid tenant, user name or password"));
    logs.audit(AuditRecord("nowhere", "eve", "10.0.0.9", "auth", "login", "", false, "Invalid"));
    logs.audit(AuditRecord("beta", "bob", "10.0.0.2", "users", "createUser", "carl"));
    clock += 1.hours;
    logs.event("acme", "backups", LogSeverity.info, "Scheduled backup created");
    logs.event("", "server", LogSeverity.info, "Server started");
    logs.application(LogSeverity.debug_, "app", "noise");
    logs.application(LogSeverity.warning, "vibe.http.server", "Slow request");

    // Mandanten sehen nur ihren Bereich; das Anwendungsprotokoll nur der Server
    auto acme = logs.read(acmeAdmin, LogQuery(LogKind.audit));
    assert(acme.total == 2 && acme.entries.map!(e => e.actor).array == ["eve", "ann"]);
    assert(acme.entries[0].severity == LogSeverity.warning && !acme.entries[0].success);
    assert(logs.read(betaAdmin, LogQuery(LogKind.audit, "acme")).total == 1); // Bereich ist fest der eigene
    assert(logs.read(sys, LogQuery(LogKind.audit)).total == 4); // der unbekannte Mandant landet bei system
    assert(logs.read(sys, LogQuery(LogKind.audit, "system")).entries[0].actor == "eve");
    assert(logs.read(sys, LogQuery(LogKind.audit, "acme")).total == 2);
    assert(collectException!AccessDenied(logs.read(acmeAdmin, LogQuery(LogKind.application))) !is null);
    assert(collectException!AccessDenied(logs.read(acmeViewer, LogQuery(LogKind.audit))) !is null);
    auto app = logs.read(sys, LogQuery(LogKind.application));
    assert(app.total == 1 && app.entries[0].category == "vibe.http.server");
    assert(logs.read(acmeAdmin, LogQuery(LogKind.event)).entries[0].message == "Scheduled backup created");
    assert(logs.logs(acmeAdmin).map!(i => i.kind).array == [LogKind.audit, LogKind.event]);
    assert(logs.logs(sys).length == 3 && logs.logs(sys)[0].editable);

    // Filter
    LogQuery q = LogQuery(LogKind.audit);
    q.minSeverity = LogSeverity.warning;
    assert(logs.read(sys, q).total == 2);
    q = LogQuery(LogKind.audit);
    q.text = "INVALID";
    assert(logs.read(sys, q).total == 2);
    q = LogQuery(LogKind.audit);
    q.actor = "BOB";
    q.category = "users";
    assert(logs.read(sys, q).entries[0].target == "carl");
    q = LogQuery(LogKind.event);
    q.from = "2026-11-08T12:30";
    assert(logs.read(sys, q).total == 2);
    q.from = "";
    q.until = "2026-11-08T12:30:00Z";
    assert(logs.read(sys, q).total == 0);
    q.limit = 0;
    assertThrown(logs.read(sys, q));

    // Blättern: before ist die kleinste Id der vorigen Seite
    q = LogQuery(LogKind.audit);
    q.limit = 2;
    auto first = logs.read(sys, q);
    q.before = first.entries[$ - 1].id;
    auto second = logs.read(sys, q);
    assert(first.total == 4 && second.entries.length == 2 && second.entries[$ - 1].actor == "ann");

    // Einstellungen: nur der eigene Bereich, jede Änderung steht im Audit
    auto s = logs.settings(acmeAdmin, LogKind.audit);
    s.categories = ["auth", "data"];
    s.minSeverity = LogSeverity.info;
    auto saved = logs.configure(acmeAdmin, LogKind.audit, s, "10.0.0.1");
    assert(saved.categories == ["auth", "data", "logs"] && settings.saved["acme"].audit.categories.canFind("data"));
    logs.audit(AuditRecord("acme", "ann", "10.0.0.1", "data", "insert", "orders"));
    logs.audit(AuditRecord("acme", "ann", "10.0.0.1", "users", "createUser", "x")); // users ist jetzt aus
    logs.audit(AuditRecord("beta", "bob", "10.0.0.2", "data", "insert", "t")); // beta hat die Voreinstellung
    q = LogQuery(LogKind.audit, "acme");
    auto latest = logs.read(sys, q).entries;
    assert(latest[0].action == "insert" && latest[1].category == "logs" && latest[1].target == "audit");
    assert(latest[1].message.canFind("categories=auth,data,logs"));
    assert(logs.read(sys, LogQuery(LogKind.audit, "beta")).total == 1);

    // Abschalten wird trotzdem aufgezeichnet, ebenso ein verweigerter Versuch
    s.enabled = false;
    logs.configure(acmeAdmin, LogKind.audit, s, "10.0.0.1");
    assert(collectException!AccessDenied(logs.configure(acmeViewer, LogKind.audit, s, "10.0.0.3")) !is null);
    assertThrown(logs.configure(acmeAdmin, LogKind.audit, LogSettings(true, LogSeverity.info, 0, 100), ""));
    assert(collectException!AccessDenied(logs.configure(acmeAdmin, LogKind.application, s, "")) !is null);
    latest = logs.read(sys, q).entries;
    assert(latest.length >= 4 && latest[0..4].map!(e => e.category).array == ["logs", "logs", "logs", "logs"]);
    assert(!latest[1].success && latest[2].actor == "vic" && latest[3].success);

    // Anwendungsprotokoll umstellen benachrichtigt den Erfasser
    LogSettings applied;
    logs.onApplicationSettings = (LogSettings next) { applied = next; };
    auto appSettings = logs.settings(sys, LogKind.application);
    appSettings.minSeverity = LogSeverity.debug_;
    logs.configure(sys, LogKind.application, appSettings, "");
    assert(applied.minSeverity == LogSeverity.debug_ && logs.applicationSettings.minSeverity == LogSeverity.debug_);

    // Gespeicherte Einstellungen gelten nach einem Neustart
    auto restarted = new LogService(store, settings, systemTenant, null, () => clock);
    assert(restarted.settings(acmeAdmin, LogKind.audit).categories == ["auth", "data", "logs"]);

    // Aufbewahrung: nach Alter und Anzahl, je Bereich
    auto events = logs.settings(sys, LogKind.event);
    events.retentionDays = 1;
    logs.configure(sys, LogKind.event, events, "");
    clock += 30.hours;
    logs.event("", "server", LogSeverity.info, "later");
    assert(logs.maintain() >= 1);
    assert(logs.read(sys, LogQuery(LogKind.event, "system")).entries.map!(e => e.message).array == ["later"]);
    assert(logs.read(sys, LogQuery(LogKind.event, "acme")).total == 1); // acme behält 90 Tage

    auto acmeEvents = logs.settings(acmeAdmin, LogKind.event);
    acmeEvents.maxEntries = 100;
    logs.configure(acmeAdmin, LogKind.event, acmeEvents, "");
    foreach (i; 0 .. 150) {
        clock += 1.msecs;
        logs.event("acme", "backups", LogSeverity.info, "b" ~ i.to!string);
    }
    logs.maintain();
    auto kept = logs.read(sys, LogQuery(LogKind.event, "acme", LogSeverity.debug_, "", "", "", "", "", 1000));
    assert(kept.total == 100 && kept.entries[0].message == "b149" && kept.entries[$ - 1].message == "b50");

    // Eine kaputte Ablage verhindert keine Aktion
    static class Broken : ILogStore {
        LogEntry append(LogEntry) {
            throw new Exception("disk full");
        }

        LogPage find(LogKind, scope bool delegate(ref const LogEntry) @safe, ulong, size_t) {
            return LogPage.init;
        }

        size_t prune(LogKind, scope LogRetention delegate(string) @safe) {
            return 0;
        }
    }

    auto broken = new LogService(new Broken, new MemoryLogSettingsStore);
    broken.audit(AuditRecord("system", "sys", "", "auth", "login"));
    broken.event("", "server", LogSeverity.error, "x");
    assert(broken.droppedEntries == 2);
}
