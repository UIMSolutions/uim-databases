/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module app;

import uim.databases.tsdb;
import vibe.d;
import std.stdio;

@safe:

shared static this() {
  auto db = new TimeSeriesDatabase("timeseries");
  auto api = new TimeSeriesAPI(db);

  auto router = new URLRouter;
  router.registerRestInterface(api);

  router.get("/", (HTTPServerRequest req, HTTPServerResponse res) {
    res.writeJsonBody([
      "name": Json("Time Series Database API"),
      "version": Json("1.0.0"),
      "endpoints": Json([
        "POST /tsdb/series - Create series",
        "DELETE /tsdb/series - Delete series",
        "GET /tsdb/series - List series",
        "POST /tsdb/write - Write a point",
        "POST /tsdb/write-batch - Write multiple points",
        "POST /tsdb/query - Query range",
        "POST /tsdb/aggregate - Aggregate range",
        "POST /tsdb/downsample - Downsample range",
        "GET /tsdb/stats - Database stats"
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

  auto settings = new HTTPServerSettings;
  settings.port = 8083;
  settings.bindAddresses = ["127.0.0.1"];
  settings.errorPageHandler = (req, res, error) {
    res.writeJsonBody([
      "error": Json(to!string(error.statusCode)),
      "message": Json(httpStatusText(error.statusCode))
    ]);
  };

  listenHTTP(settings, router);
  writeln("Time Series Database API server running on http://127.0.0.1:8083");
  runEventLoop();
}
