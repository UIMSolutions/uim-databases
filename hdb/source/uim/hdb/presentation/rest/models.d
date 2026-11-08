/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.rest.models;

import uim.hdb;
import std.algorithm : map;
import std.array : array;
import vibe.data.json : Json;
import vibe.data.serialization : optional, wireName = name;

@safe:

/// Response formats of the REST interfaces. They decouple the public API from the domain model.

struct RestStatus {
    string status;
}

struct RestUser {
    string name;
    string role; // Rolle im Mandanten (vordefiniert oder eigene), leer: keine
    bool active;
    @optional string tenant; // Mandant; system für Systembenutzer
    @optional RestGrant[] grants; // Tabellenfreigaben
}

/// Rolle für eine einzelne Tabelle; davon gelten nur select, insert, update, delete und drop.
/// Ohne `table` gilt die Rolle im ganzen Mandanten. `from`/`until` befristen sie (UTC, ISO 8601).
struct RestGrant {
    string table;
    string role;
    @optional string from;
    @optional string until;
    @optional string state; // nur in Antworten: active, scheduled oder expired
}

struct RestRole {
    string name, description;
    string[] permissions;
    bool builtin;
    long users;
}

/// Rechte der angemeldeten Identität: im ganzen Mandanten (bzw. auf dem Server) und je Tabelle.
struct RestTableAccess {
    string table;
    string[] permissions;
}

struct RestMe {
    string name, role, tenant;
    string[] permissions;
    RestTableAccess[] tables;
}

struct RestNetworks {
    string[] networks;
    string yourAddress; // Adresse dieser Anfrage, wie der Server sie sieht
}

struct RestTenant {
    string name, label;
    bool active;
    long users;
    @optional string[] networks;
}

struct RestLogin {
    string token;
    long expiresIn; // Sekunden
    RestUser user;
}

struct RestBackup {
    string name, label, created;
    long size, tables, rows;
    bool readable;
    string kind; // manual, scheduled, safety oder uploaded
}

struct RestBackupSchedule {
    bool enabled;
    int intervalHours, keepScheduled, keepSafety;
    string lastRun, lastError, nextRun;
}

struct RestRestore {
    string status;
    RestBackup safetyBackup; // Stand vor der Wiederherstellung
}

struct RestMergeStatus {
    bool running;
    long completed;
    string lastError;
}

struct RestColumnDef {
    string name;
    string type; // SQL- oder EDM-Name, siehe typeSpecs
}

struct RestColumnStats {
    string name;
    string type;
    long rows, mainRows, deltaRows, mainDistinct, deltaDistinct;
    uint mainBits;
    long mainCodeBytes;
}

struct RestTableInfo {
    string table;
    string storage;
    long rows, deletedRows;
    RestColumnStats[] columns;
}

struct RestSqlResult {
    string[] columns;
    Json[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}

struct RestRowPage {
    string[] columns;
    Json[][] rows;
    long total; // Treffer insgesamt, unabhängig von limit und offset
    long limit, offset;
}

RestBackup toRest(BackupInfo b) {
    return RestBackup(b.name, b.label, b.created, b.size, b.tables, b.rows, b.readable, b.kind);
}

RestBackupSchedule toRest(BackupSchedule s) {
    return RestBackupSchedule(s.enabled, s.intervalHours, s.keepScheduled, s.keepSafety, s.lastRun, s.lastError, s.nextRun);
}

RestTenant toRest(TenantInfo t) {
    return RestTenant(t.name, t.label, t.active, t.users, t.networks);
}

RestUser toRest(UserInfo u) {
    import std.datetime.systime : Clock;
    import std.datetime.timezone : UTC;

    auto now = Clock.currTime(UTC());
    return RestUser(u.name, u.role, u.active, u.tenant,
        u.grants.map!(g => RestGrant(g.table, g.role, g.from, g.until, g.stateAt(now))).array);
}

RestRole toRest(RoleInfo r) {
    return RestRole(r.name, r.description, r.permissions, r.builtin, r.users);
}

RestMe toRestMe(Principal p) {
    import std.algorithm : sort;

    RestMe me = RestMe(p.name, p.role, p.tenant, p.permissions.names);
    foreach (table, set; p.tables)
        me.tables ~= RestTableAccess(table, set.names);
    me.tables.sort!((a, b) => a.table < b.table);
    return me;
}

Json toRestJson(Value v) {
    if (auto l = v.peek!long)
        return Json(*l);
    if (auto d = v.peek!double)
        return Json(*d);
    if (auto s = v.peek!string)
        return Json(*s);
    if (auto b = v.peek!bool)
        return Json(*b);
    if (auto e = v.peek!Exact)
        return Json(e.text); // als Text, weil eine JSON-Zahl hier ein double würde
    return Json(null);
}

Json[][] toRestRows(Value[][] rows) {
    return rows.map!(row => row.map!(toRestJson).array).array;
}

RestSqlResult toRest(QueryResult r) {
    return RestSqlResult(r.columns, toRestRows(r.rows), r.affected, r.message, r.transaction);
}

RestMergeStatus toRest(MergeStatus s) {
    return RestMergeStatus(s.running, s.completed, s.lastError);
}

RestColumnStats toRest(ColumnStats c) {
    return RestColumnStats(c.name, typeName(c.type), c.rows, c.mainRows, c.deltaRows,
        c.mainDistinct, c.deltaDistinct, c.mainBits, c.mainCodeBytes);
}

RestTableInfo toRest(TableStats t) {
    return RestTableInfo(t.table, storageName(t.storage), t.rows, t.deletedRows, t.columns.map!(c => toRest(c)).array);
}

// --- Protokolle ---

/// Einstellungen eines Protokolls. `categories`: aufgezeichnete Kategorien (beim Anwendungsprotokoll leer).
struct RestLogSettings {
    bool enabled;
    string minSeverity; // debug, info, warning oder error
    int retentionDays;
    long maxEntries;
    string[] categories;
}

/// Ein Protokoll, das die Anmeldung lesen darf.
struct RestLogInfo {
    string kind; // audit, application oder event
    RestLogSettings settings;
    string[] availableCategories;
    string[] mandatoryCategories; // immer aufgezeichnet
    bool editable; // Recht manageLogs
}

struct RestLogEntry {
    long id;
    string time; // ISO 8601 in UTC mit Millisekunden
    string severity;
    @wireName("scope") string scope_; // Mandant oder system
    string category;
    string actor, address, action, target; // nur audit
    bool success; // nur audit
    string message;
}

struct RestLogPage {
    RestLogEntry[] entries; // neueste zuerst
    long total; // Treffer insgesamt; weiterblättern mit before = kleinste Id der Seite
}

RestLogSettings toRest(LogSettings s) {
    return RestLogSettings(s.enabled, severityName(s.minSeverity), s.retentionDays, cast(long) s.maxEntries, s.categories);
}

RestLogInfo toRest(LogInfo i) {
    import std.array : array;

    return RestLogInfo(logKindName(i.kind), toRest(i.settings), categoriesOf(i.kind).dup,
        mandatoryCategoriesOf(i.kind).dup, i.editable);
}

RestLogEntry toRest(LogEntry e) {
    return RestLogEntry(cast(long) e.id, e.time, severityName(e.severity), e.scope_, e.category, e.actor, e.address,
        e.action, e.target, e.success, e.message);
}
