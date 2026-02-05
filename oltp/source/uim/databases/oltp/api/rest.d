module uim.databases.oltp.api.rest;

import vibe.vibe;
import uim.databases.oltp.database;

/// REST API for OLTP Database
class OLTPRestAPI {
    private {
        OLTPDatabase _db;
        HTTPServerSettings _settings;
    }
    
    this(OLTPDatabase db, ushort port = 8080, string bindAddress = "127.0.0.1") {
        _db = db;
        _settings = new HTTPServerSettings();
        _settings.port = port;
        _settings.bindAddresses = [bindAddress];
    }
    
    /// Start the REST API server
    void start() {
        auto router = new URLRouter();
        
        // Database info
        router.get("/", &getInfo);
        router.get("/stats", &getStats);
        
        // Table management
        router.post("/tables/:tableName", &createTable);
        router.delete_("/tables/:tableName", &dropTable);
        router.get("/tables", &listTables);
        
        // Data operations
        router.post("/tables/:tableName/rows", &insertRow);
        router.get("/tables/:tableName/rows", &queryRows);
        router.get("/tables/:tableName/rows/:rowId", &getRow);
        router.put("/tables/:tableName/rows/:rowId", &updateRow);
        router.delete_("/tables/:tableName/rows/:rowId", &deleteRow);
        
        // Transaction endpoints
        router.post("/transactions/begin", &beginTransaction);
        router.post("/transactions/:txId/commit", &commitTransaction);
        router.post("/transactions/:txId/rollback", &rollbackTransaction);
        router.post("/transactions/:txId/execute", &executeInTransaction);
        
        // Database operations
        router.post("/checkpoint", &performCheckpoint);
        
        listenHTTP(_settings, router);
        
        logInfo("OLTP REST API started on %s:%d", _settings.bindAddresses[0], _settings.port);
    }
    
    // Handler methods
    
    void getInfo(HTTPServerRequest req, HTTPServerResponse res) {
        auto info = Json.emptyObject;
        info["name"] = _db.name;
        info["version"] = "1.0.0";
        info["type"] = "OLTP Database";
        info["running"] = _db.isRunning;
        res.writeJsonBody(info);
    }
    
    void getStats(HTTPServerRequest req, HTTPServerResponse res) {
        res.writeJsonBody(_db.getStatistics());
    }
    
    void createTable(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        auto body = req.json;
        
        string[] columns;
        if ("columns" in body) {
            foreach (col; body["columns"]) {
                columns ~= col.get!string;
            }
        }
        
        try {
            _db.createTable(tableName, columns);
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Table created")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void dropTable(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        
        try {
            _db.dropTable(tableName);
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Table dropped")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void listTables(HTTPServerRequest req, HTTPServerResponse res) {
        auto tables = _db._storage.getTableNames();
        res.writeJsonBody(Json(["tables": serializeToJson(tables)]));
    }
    
    void insertRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        auto data = req.json;
        
        try {
            auto txn = _db.beginTransaction();
            auto rowId = txn.insert(tableName, data);
            txn.commit();
            
            res.writeJsonBody(Json([
                "success": Json(true),
                "rowId": Json(rowId),
                "message": Json("Row inserted")
            ]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void queryRows(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        
        string columnName = req.query.get("column", "");
        string value = req.query.get("value", "");
        
        try {
            auto txn = _db.beginTransaction();
            auto rows = txn.query(tableName, columnName, value);
            txn.commit();
            
            res.writeJsonBody(Json([
                "success": Json(true),
                "rows": Json(rows),
                "count": Json(rows.length)
            ]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void getRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        auto rowId = req.params["rowId"];
        
        try {
            auto row = _db._storage.getRow(tableName, rowId);
            if (row is null) {
                res.statusCode = HTTPStatus.notFound;
                res.writeJsonBody(Json(["success": Json(false), "error": Json("Row not found")]));
            } else {
                res.writeJsonBody(Json([
                    "success": Json(true),
                    "row": row.toJson()
                ]));
            }
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void updateRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        auto rowId = req.params["rowId"];
        auto data = req.json;
        
        try {
            auto txn = _db.beginTransaction();
            auto success = txn.update(tableName, rowId, data);
            txn.commit();
            
            if (success) {
                res.writeJsonBody(Json(["success": Json(true), "message": Json("Row updated")]));
            } else {
                res.statusCode = HTTPStatus.notFound;
                res.writeJsonBody(Json(["success": Json(false), "error": Json("Row not found")]));
            }
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void deleteRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto tableName = req.params["tableName"];
        auto rowId = req.params["rowId"];
        
        try {
            auto txn = _db.beginTransaction();
            auto success = txn.deleteRow(tableName, rowId);
            txn.commit();
            
            if (success) {
                res.writeJsonBody(Json(["success": Json(true), "message": Json("Row deleted")]));
            } else {
                res.statusCode = HTTPStatus.notFound;
                res.writeJsonBody(Json(["success": Json(false), "error": Json("Row not found")]));
            }
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void beginTransaction(HTTPServerRequest req, HTTPServerResponse res) {
        try {
            auto txn = _db.beginTransaction();
            res.writeJsonBody(Json([
                "success": Json(true),
                "transactionId": Json(txn.id),
                "message": Json("Transaction started")
            ]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void commitTransaction(HTTPServerRequest req, HTTPServerResponse res) {
        auto txId = req.params["txId"];
        
        try {
            _db.commit(txId);
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Transaction committed")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void rollbackTransaction(HTTPServerRequest req, HTTPServerResponse res) {
        auto txId = req.params["txId"];
        
        try {
            _db.rollback(txId);
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Transaction rolled back")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void executeInTransaction(HTTPServerRequest req, HTTPServerResponse res) {
        auto txId = req.params["txId"];
        auto body = req.json;
        
        // TODO: Implement transaction-based operations
        res.writeJsonBody(Json(["success": Json(false), "error": Json("Not implemented")]));
    }
    
    void performCheckpoint(HTTPServerRequest req, HTTPServerResponse res) {
        try {
            _db.checkpoint();
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Checkpoint completed")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.internalServerError;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
}
