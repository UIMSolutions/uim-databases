/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module app;

import uim.databases.geodb;
import vibe.d;
import std.stdio;

@safe:

shared static this() {
  // Create geographic database
  auto db = new GeoDatabase("locations");

  // Create REST API handler
  auto api = new GeoDatabaseAPI(db);

  // Setup router
  auto router = new URLRouter;
  router.registerRestInterface(api);

  // Add root endpoint
  router.get("/", (HTTPServerRequest req, HTTPServerResponse res) {
    res.writeJsonBody([
      "name": Json("Geographic Database API"),
      "version": Json("1.0.0"),
      "description": Json("High-performance geospatial database"),
      "endpoints": Json([
        "POST /geo/location - Add location",
        "GET /geo/location - Get all locations",
        "GET /geo/location/:id - Get location by ID",
        "DELETE /geo/location/:id - Remove location",
        "POST /geo/nearby - Find nearby locations (radius)",
        "POST /geo/bounds - Find locations in bounding box",
        "POST /geo/nearest - Find N nearest locations",
        "POST /geo/distance - Calculate distance between two points",
        "GET /geo/stats - Database statistics"
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
  settings.port = 8082;
  settings.bindAddresses = ["127.0.0.1"];

  listenHTTP(settings, router);
  writeln("Geographic Database API server running on http://127.0.0.1:8082");
  runEventLoop();
}
