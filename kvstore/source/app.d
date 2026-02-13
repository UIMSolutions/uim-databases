/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module app;

import uim.databases.kvstore;
import vibe.d;
import std.stdio;

@safe:

shared static this() {
  // Create an in-memory KV store
  auto memoryStore = new KVStore("main");

  // Create a persistent KV store
  // auto persistentStore = new PersistentKVStore("./data/kvstore.json");

  // Create the REST API handler
  auto api = new KVStoreAPI(memoryStore);

  // Setup router
  auto router = new URLRouter;
  router.registerRestInterface(api);

  // Add example route
  router.get("/", (HTTPServerRequest req, HTTPServerResponse res) {
    res.writeJsonBody([
      "name": Json("Key-Value Store API"),
      "version": Json("1.0.0"),
      "endpoints": Json([
        "GET /kvstore/:key - Get a value",
        "POST /kvstore - Set a value (JSON: {\"key\": \"...\", \"value\": \"...\"})",
        "DELETE /kvstore/:key - Delete a value",
        "GET /kvstore/check/:key - Check if key exists",
        "GET /kvstore/keys - Get all keys",
        "GET /kvstore/stats - Get store statistics",
        "POST /kvstore/multi - Set multiple values",
        "POST /kvstore/multi-get - Get multiple values",
        "DELETE /kvstore - Clear all data"
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
  settings.port = 8080;
  settings.bindAddresses = ["127.0.0.1"];
  settings.errorPageHandler = (req, res, error) {
    res.writeJsonBody([
      "error": Json(to!string(error.statusCode)),
      "message": Json(httpStatusText(error.statusCode))
    ]);
  };

  listenHTTP(settings, router);
  writeln("KV Store API server running on http://127.0.0.1:8080");
  runEventLoop();
}
