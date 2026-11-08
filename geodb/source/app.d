/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Composition root: the only place where adapters and the application core are wired together.
///
/// Environment:
///   GEODB_NAME          database name reported by /geo/stats (default "locations")
///   GEODB_HOST          bind address (default "127.0.0.1")
///   GEODB_PORT          HTTP port (default 8082)
///   GEODB_GRID_DEGREES  spatial index cell size in degrees (default 1.0)
module app;

import uim.databases.geodb;
import std.conv : to;
import std.process : environment;
import vibe.core.core : runApplication;
import vibe.core.log : logInfo;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerSettings, listenHTTP;

@safe:

int main() {
  immutable name = environment.get("GEODB_NAME", "locations");
  immutable host = environment.get("GEODB_HOST", "127.0.0.1");
  immutable port = environment.get("GEODB_PORT", "8082").to!ushort;
  immutable gridDegrees = environment.get("GEODB_GRID_DEGREES", "1.0").to!double;

  // Outbound adapter
  ILocationRepository repository = new InMemoryLocationRepository(gridDegrees);

  // Application core
  ILocationUseCase locations = new LocationService(repository);
  IGeoQueryUseCase queries = new GeoQueryService(repository, name);

  // Inbound adapter
  auto router = new URLRouter;
  registerGeoRoutes(router, new GeoRestController(locations, queries));

  auto settings = new HTTPServerSettings;
  settings.port = port;
  settings.bindAddresses = [host];
  auto listener = listenHTTP(settings, router);
  scope (exit) listener.stopListening();

  logInfo("Geographic Database API '%s' running on http://%s:%s", name, host, port);
  return runApplication();
}
