module uim.hdb.adapters.inbound.rest_api;

import uim.hdb.application.ports;
import uim.hdb.domain.value;
import std.algorithm : map;
import std.array : array;
import vibe.d;

/// Eingehender Adapter: HTTP/JSON -> ISqlUseCase.
final class SqlRestApi
{
    private ISqlUseCase sql;

    this(ISqlUseCase sql)
    {
        this.sql = sql;
    }

    void register(URLRouter router)
    {
        router.get("/health", &health);
        router.get("/tables", &tables);
        router.post("/sql", &execute);
        router.post("/checkpoint", &checkpoint);
        router.post("/merge", &merge);
        router.get("/merge", &mergeStatus);
        router.get("/stats", &stats);
    }

    private void health(HTTPServerRequest req, HTTPServerResponse res)
    {
        res.writeJsonBody(["status": "UP"]);
    }

    private void tables(HTTPServerRequest req, HTTPServerResponse res)
    {
        res.writeJsonBody(sql.listTables());
    }

    private void checkpoint(HTTPServerRequest req, HTTPServerResponse res)
    {
        sql.checkpoint();
        res.writeJsonBody(["status": "CHECKPOINTED"]);
    }

    /// Startet den Delta-Merge im Hintergrund (202); die Datenbank bleibt währenddessen benutzbar.
    private void merge(HTTPServerRequest req, HTTPServerResponse res)
    {
        try
        {
            auto started = sql.mergeDeltaAsync();
            res.statusCode = 202;
            res.writeJsonBody(["status": started ? "STARTED" : "RUNNING"]);
        }
        catch (Exception e)
        {
            res.statusCode = 400;
            res.writeJsonBody(["error": e.msg]);
        }
    }

    private void mergeStatus(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto st = sql.mergeStatus();
        Json j = Json.emptyObject;
        j["running"] = st.running;
        j["completed"] = cast(long) st.completed;
        j["lastError"] = st.lastError;
        res.writeJsonBody(j);
    }

    private void stats(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto all = sql.stats();
        auto j = serializeToJson(all);
        foreach (ti, t; all)
            foreach (ci, c; t.columns)
                j[ti]["columns"][ci]["type"] = typeName(c.type);
        res.writeJsonBody(j);
    }

    private void execute(HTTPServerRequest req, HTTPServerResponse res)
    {
        try
        {
            auto stmt = req.json["statement"].get!string;
            string txId = req.headers.get("X-Transaction-Id", "");
            auto bodyTx = req.json["transaction"];
            if (bodyTx.type == Json.Type.string)
                txId = bodyTx.get!string;
            auto r = sql.executeIn(txId, stmt);
            Json j = Json.emptyObject;
            j["columns"] = serializeToJson(r.columns);
            j["rows"] = Json(r.rows.map!(row => Json(row.map!(v => toJson(v)).array)).array);
            j["affected"] = r.affected;
            j["message"] = r.message;
            if (r.transaction.length)
                j["transaction"] = r.transaction;
            res.writeJsonBody(j);
        }
        catch (Exception e)
        {
            res.statusCode = 400;
            res.writeJsonBody(["error": e.msg]);
        }
    }
}

private Json toJson(Value v)
{
    if (auto l = v.peek!long)
        return Json(*l);
    if (auto d = v.peek!double)
        return Json(*d);
    if (auto s = v.peek!string)
        return Json(*s);
    return Json(null);
}
