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
import vibe.data.serialization : optional;

/// Response formats of the REST interfaces. They decouple the public API from the domain model.

struct RestStatus {
    string status;
}

struct RestUser {
    string name;
    string role; // viewer, editor oder admin
    bool active;
    @optional string tenant; // Mandant; system für Systemadministratoren
}

struct RestTenant {
    string name, label;
    bool active;
    long users;
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
    return RestTenant(t.name, t.label, t.active, t.users);
}

RestUser toRest(UserInfo u) {
    return RestUser(u.name, roleName(u.role), u.active, u.tenant);
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
