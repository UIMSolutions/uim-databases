/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.enumerations.logkind;

import std.string : strip, toLower;

@safe:

/// Die drei Protokolle des Servers.
enum LogKind {
    audit, /// Wer hat wann was getan: Anmeldungen, Verwaltung, Schemaänderungen, Sicherungen
    application, /// Technische Meldungen des Servers (alles, was über vibe.core.log geht)
    event /// Betriebsereignisse: Start, geplante Sicherungen, Zustand der Replikation
}

string logKindName(LogKind kind) {
    final switch (kind) {
    case LogKind.audit:
        return "audit";
    case LogKind.application:
        return "application";
    case LogKind.event:
        return "event";
    }
}

LogKind parseLogKind(string name) {
    switch (name.strip.toLower) {
    case "audit":
        return LogKind.audit;
    case "application":
        return LogKind.application;
    case "event":
    case "events":
        return LogKind.event;
    default:
        throw new Exception("Unknown log: " ~ name ~ " (expected audit, application or event)");
    }
}

/// Schwere eines Eintrags. Ein Protokoll nimmt nur Einträge ab seiner Mindestschwere auf.
enum LogSeverity {
    debug_,
    info,
    warning,
    error
}

string severityName(LogSeverity severity) {
    final switch (severity) {
    case LogSeverity.debug_:
        return "debug";
    case LogSeverity.info:
        return "info";
    case LogSeverity.warning:
        return "warning";
    case LogSeverity.error:
        return "error";
    }
}

LogSeverity parseSeverity(string name) {
    switch (name.strip.toLower) {
    case "debug":
        return LogSeverity.debug_;
    case "info":
        return LogSeverity.info;
    case "warning":
    case "warn":
        return LogSeverity.warning;
    case "error":
        return LogSeverity.error;
    default:
        throw new Exception("Unknown severity: " ~ name ~ " (expected debug, info, warning or error)");
    }
}

unittest {
    import std.exception : assertThrown;
    import std.traits : EnumMembers;

    foreach (k; [EnumMembers!LogKind])
        assert(parseLogKind(logKindName(k)) == k);
    foreach (s; [EnumMembers!LogSeverity])
        assert(parseSeverity(severityName(s)) == s);
    assert(parseLogKind(" Events ") == LogKind.event && parseSeverity("WARN") == LogSeverity.warning);
    assertThrown(parseLogKind("trace"));
    assertThrown(parseSeverity("fatal"));
    assert(LogSeverity.debug_ < LogSeverity.info && LogSeverity.warning < LogSeverity.error);
}
