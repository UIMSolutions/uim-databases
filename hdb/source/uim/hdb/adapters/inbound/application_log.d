/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.adapters.inbound.application_log;

import uim.hdb;
import core.sync.mutex : Mutex;
import core.time : msecs;
import std.array : Appender, appender;
import vibe.core.core : setTimer, Timer;
import vibe.core.log : deregisterLogger, LogLevel, LogLine, Logger, registerLogger;

@safe:

/// Eingehender Adapter: nimmt alles an, was über vibe.core.log gemeldet wird (logInfo, logWarn, ... auch aus
/// vibe.d selbst), und gibt es an das Anwendungsprotokoll weiter. Die Konsolenausgabe bleibt, wie sie ist.
///
/// vibe ruft Logger auch aus anderen Threads auf, LogService ist aber nicht threadsicher. Deshalb landen die Zeilen
/// zuerst in einem Eingangspuffer mit Mutex, und `flush` gibt sie im Hauptthread ab (alle 500 ms über `start`).
final class ApplicationLogCapture : Logger {
    enum size_t maxPending = 10_000;

    private struct Pending {
        LogSeverity severity;
        string source, text, time;
    }

    private Mutex mutex;
    private Pending[] pending; // nur unter mutex
    private size_t overflow; // nur unter mutex
    private LogLine line; // nur unter der Sperre, die vibe um jede Zeile legt
    private Appender!string text;
    private LogService logs;
    private Timer timer;

    this(LogService logs) {
        this.logs = logs;
        mutex = new Mutex;
        apply(logs.applicationSettings);
        logs.onApplicationSettings = &apply;
    }

    /// Meldet den Erfasser bei vibe an und gibt den Puffer regelmäßig im aufrufenden (Haupt-)Thread ab.
    void start() {
        register(this);
        timer = setTimer(500.msecs, () nothrow { flush(); }, true);
    }

    void stop() {
        if (timer)
            timer.stop();
        unregister(this);
        flush();
    }

    /// Gibt gesammelte Zeilen an das Anwendungsprotokoll. Nur im Hauptthread aufrufen.
    void flush() nothrow {
        Pending[] lines;
        size_t lost;
        mutex.lock_nothrow();
        lines = pending;
        pending = null;
        lost = overflow;
        overflow = 0;
        mutex.unlock_nothrow();
        foreach (p; lines)
            logs.application(p.severity, p.source, p.text, p.time);
        if (lost)
            logs.application(LogSeverity.warning, "hdb.logging", formatLost(lost));
    }

    override void beginLine(ref LogLine info) {
        line = info;
        text = appender!string();
    }

    override void put(scope const(char)[] part) {
        text.put(part);
    }

    override void endLine() {
        auto p = Pending(severityOf(line.level), sourceOf(line.file), text.data, logTime(line.time));
        text = Appender!string.init;
        mutex.lock_nothrow();
        scope (exit)
            mutex.unlock_nothrow();
        if (pending.length < maxPending)
            pending ~= p;
        else
            ++overflow;
    }

    /// Neue Einstellungen: vibe formatiert dann nur noch Zeilen ab der Mindestschwere.
    private void apply(LogSettings settings) {
        minLevel = settings.enabled ? levelOf(settings.minSeverity) : LogLevel.none;
    }
}

private string formatLost(size_t lost) nothrow {
    import std.conv : to;

    try
        return lost.to!string ~ " log lines were dropped because the server logged faster than it could store them";
    catch (Exception)
        return "Log lines were dropped";
}

/// @trusted: registerLogger verlangt eine shared-Referenz. Mit anderen Threads teilt der Erfasser nur seinen
/// Eingangspuffer, und der ist durch den Mutex geschützt; Zeilen schreibt vibe immer unter der Sperre des Loggers.
private void register(ApplicationLogCapture capture) @trusted {
    registerLogger(cast(shared) capture);
}

/// @trusted: wie register.
private void unregister(ApplicationLogCapture capture) @trusted {
    deregisterLogger(cast(shared) capture);
}

/// Modulname aus dem Quellpfad, den vibe mitgibt (LogLine.mod bleibt leer): .../source/vibe/http/server.d wird
/// zu vibe.http.server.
string sourceOf(string file) {
    import std.array : replace;
    import std.path : baseName, stripExtension;
    import std.string : lastIndexOf;

    auto path = file.replace("\\", "/");
    auto at = path.lastIndexOf("source/");
    auto rest = at >= 0 ? path[at + "source/".length .. $] : baseName(path);
    return rest.stripExtension.replace("/", ".");
}

LogSeverity severityOf(LogLevel level) {
    if (level <= LogLevel.diagnostic)
        return LogSeverity.debug_;
    if (level == LogLevel.info)
        return LogSeverity.info;
    if (level == LogLevel.warn)
        return LogSeverity.warning;
    return LogSeverity.error;
}

LogLevel levelOf(LogSeverity severity) {
    final switch (severity) {
    case LogSeverity.debug_:
        return LogLevel.debug_;
    case LogSeverity.info:
        return LogLevel.info;
    case LogSeverity.warning:
        return LogLevel.warn;
    case LogSeverity.error:
        return LogLevel.error;
    }
}

unittest {
    import std.algorithm : canFind, map;
    import std.array : array;
    import vibe.core.log : logDebug, logError, logInfo, logWarn;

    assert(severityOf(LogLevel.trace) == LogSeverity.debug_ && severityOf(LogLevel.diagnostic) == LogSeverity.debug_);
    assert(severityOf(LogLevel.critical) == LogSeverity.error && severityOf(LogLevel.warn) == LogSeverity.warning);

    auto logs = new LogService(new MemoryLogStore, new MemoryLogSettingsStore);
    auto capture = new ApplicationLogCapture(logs);
    register(capture);
    logInfo("Captured %s", 1);
    logDebug("Not captured");
    logWarn("Careful");
    capture.flush();

    auto sys = Principal("sys", HdbRole.admin, true, systemTenant);
    auto entries = logs.read(sys, LogQuery(LogKind.application)).entries;
    assert(entries.map!(e => e.message).array == ["Careful", "Captured 1"]);
    assert(entries[0].severity == LogSeverity.warning);
    assert(entries[1].category == "uim.hdb.adapters.inbound.application_log", entries[1].category);
    assert(sourceOf("../../.dub/packages/vibe-http/1.5.1/vibe-http/source/vibe/http/server.d") == "vibe.http.server");
    assert(sourceOf("app.d") == "app");

    // Mindestschwere über die Einstellungen; abgeschaltet nimmt der Erfasser nichts mehr an
    auto s = logs.settings(sys, LogKind.application);
    s.minSeverity = LogSeverity.error;
    logs.configure(sys, LogKind.application, s, "");
    logWarn("Now ignored");
    logError("Still captured");
    capture.flush(); // abgegeben wird nach den Einstellungen zum Zeitpunkt von flush
    s.enabled = false;
    logs.configure(sys, LogKind.application, s, "");
    logError("Off");
    unregister(capture);
    capture.flush();
    entries = logs.read(sys, LogQuery(LogKind.application)).entries;
    assert(entries.map!(e => e.message).array == ["Still captured", "Careful", "Captured 1"]);
}
