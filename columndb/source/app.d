/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module app;

import uim.databases.columndb;
import vibe.d;
import std.stdio;

@safe:

shared static this() {
  // Create column database
  auto db = new CdbDatabase("analytics");

  // Create REST API handler
  auto api = new CdbDatabaseAPI(db);

  // Setup router
  auto router = new URLRouter;
  router.registerRestInterface(api);

  // Add root endpoint
  router.get("/", (HTTPServerRequest req, HTTPServerResponse res) {
    res.writeJsonBody([
      "name": Json("Column Database API"),
      "version": Json("1.0.0"),
      "description": Json("High-performance column-based analytical database"),
      "endpoints": Json([
        "POST /cdb/table - Create table",
        "GET /cdb/table/:name - Get table info",
        "GET /cdb/tables - List all tables",
        "DELETE /cdb/table/:name - Drop table",
        "POST /cdb/row - Insert row",
        "POST /cdb/rows - Insert multiple rows",
        "GET /cdb/row/:table/:index - Get row by index",
        "POST /cdb/query - Query column for value",
        "GET /cdb/column/:table/:name/stats - Get column statistics",
        "GET /cdb/stats - Database statistics"
      ])
    ]);
  });

  router.any("*", (HTTPServerRequest req, HTTPServerResponse res) {
    res.statusCode = 404;
    res.writeJsonBody([
      "error": Json("Not found"),
      "path": Json(req.path)
    ]);
  });

  // Setup and start server
  auto settings = new HTTPServerSettings;
  settings.port = 8081;
  settings.bindAddresses = ["127.0.0.1"];

  listenHTTP(settings, router);
  writeln("Column Database API server running on http://127.0.0.1:8081");
  runEventLoop();
}
