module uim.hdb.presentation.rest.models;

import uim.hdb.application.ports : MergeStatus, QueryResult, UserInfo;
import uim.hdb.domain.entities.user : roleName;
import uim.hdb.domain.types.tablestats : ColumnStats, TableStats;
import uim.hdb.domain.types.tablestorage : storageName;
import uim.hdb.domain.value;
import std.algorithm : map;
import std.array : array;
import vibe.data.json : Json;

/// Antwortformate der REST-Schnittstellen. Sie entkoppeln die öffentliche API vom Domänenmodell.

struct RestStatus {
    string status;
}

struct RestUser {
    string name;
    string role; // viewer, editor oder admin
    bool active;
}

struct RestLogin {
    string token;
    long expiresIn; // Sekunden
    RestUser user;
}

struct RestMergeStatus {
    bool running;
    long completed;
    string lastError;
}

struct RestColumnDef {
    string name;
    string type; // INTEGER, DECIMAL oder VARCHAR
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

RestUser toRest(UserInfo u) {
    return RestUser(u.name, roleName(u.role), u.active);
}

Json toRestJson(Value v) {
    if (auto l = v.peek!long)
        return Json(*l);
    if (auto d = v.peek!double)
        return Json(*d);
    if (auto s = v.peek!string)
        return Json(*s);
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
