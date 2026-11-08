module uim.hdb.adapters.inbound.rest_api;

import uim.hdb;
import std.algorithm : map;
import std.array : array;
import vibe.d;

@safe:

/// Eingehender Adapter: HTTP/JSON -> ISqlUseCase.
final class SqlRestApi {
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    void register(URLRouter router) {
        router.get("/health", &health);
        router.get("/tables", secured(&tables));
        router.post("/sql", secured(&execute));
        router.post("/checkpoint", secured(&checkpoint));
        router.post("/merge", secured(&merge));
        router.get("/merge", secured(&mergeStatus));
        router.get("/stats", secured(&stats));
    }

    /// Antwortet auf fehlende Rechte mit 401 oder 403 statt mit einem allgemeinen Fehler.
    private auto secured(void delegate(HTTPServerRequest, HTTPServerResponse) @safe handler) {
        return (HTTPServerRequest req, HTTPServerResponse res) {
            try
                handler(req, res);
            catch (AuthenticationRequired e) {
                res.statusCode = 401;
                res.writeJsonBody(["error": e.msg]);
            } catch (AccessDenied e) {
                res.statusCode = 403;
                res.writeJsonBody(["error": e.msg]);
            }
        };
    }

    private void health(HTTPServerRequest req, HTTPServerResponse res) {
        res.writeJsonBody(["status": "UP"]);
    }

    private void tables(HTTPServerRequest req, HTTPServerResponse res) {
        res.writeJsonBody(sql.listTables());
    }

    private void checkpoint(HTTPServerRequest req, HTTPServerResponse res) {
        sql.checkpoint();
        res.writeJsonBody(["status": "CHECKPOINTED"]);
    }

    /// Startet den Delta-Merge im Hintergrund (202); die Datenbank bleibt währenddessen benutzbar.
    private void merge(HTTPServerRequest req, HTTPServerResponse res) {
        try {
            auto started = sql.mergeDeltaAsync();
            res.statusCode = 202;
            res.writeJsonBody(["status": started ? "STARTED": "RUNNING"]);
        } catch (AuthenticationRequired e)
            throw e;
        catch (AccessDenied e)
            throw e;
        catch (Exception e) {
            res.statusCode = 400;
            res.writeJsonBody(["error": e.msg]);
        }
    }

    private void mergeStatus(HTTPServerRequest req, HTTPServerResponse res) {
        auto st = sql.mergeStatus();
        Json j = Json.emptyObject;
        j["running"] = st.running;
        j["completed"] = cast(long)st.completed;
        j["lastError"] = st.lastError;
        res.writeJsonBody(j);
    }

    private void stats(HTTPServerRequest req, HTTPServerResponse res) {
        auto all = sql.stats();
        auto j = serializeToJson(all);
        foreach (ti, t; all)
        {
            j[ti]["storage"] = storageName(t.storage);
            foreach (ci, c; t.columns)
                j[ti]["columns"][ci]["type"] = typeName(c.type);
        }
        res.writeJsonBody(j);
    }

    private void execute(HTTPServerRequest req, HTTPServerResponse res) {
        try {
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
        } catch (AuthenticationRequired e)
            throw e;
        catch (AccessDenied e)
            throw e;
        catch (Exception e) {
            res.statusCode = 400;
            res.writeJsonBody(["error": e.msg]);
        }
    }
}

private Json toJson(Value v) {
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
