/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.presentation.http.routes;

import uim.databases.geodb.presentation.rest.interfaces : IGeoRestApi;
import vibe.core.log : logError;
import vibe.data.json : Json;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.web.rest : registerRestInterface, RestErrorInformation, RestInterfaceSettings;

@safe:

enum string apiVersion = "2.0.0";

/// Mounts the REST API, a self-description at `/` and a JSON 404 for everything else.
void registerGeoRoutes(URLRouter router, IGeoRestApi api) {
  auto settings = new RestInterfaceSettings;
  settings.errorHandler = (req, res, error) => writeError(req, res, error);
  router.registerRestInterface(api, settings);
  router.get("/", &describeApi);
  router.any("*", &notFound);
}

/// Same error body in debug and release builds: `{"statusMessage": ...}`. Client errors (e.g. a
/// malformed request body) keep their message; server errors are logged and never expose internals.
private void writeError(HTTPServerRequest req, HTTPServerResponse res, RestErrorInformation error) {
  string message = error.exception !is null ? error.exception.msg : "";
  if (error.statusCode >= 500) {
    logError("%s %s failed: %s", req.method, req.requestPath, message);
    message = "Internal server error";
  }
  res.writeJsonBody(["statusMessage": Json(message)], error.statusCode);
}

private void describeApi(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeJsonBody([
    "name": Json("Geographic Database API"),
    "version": Json(apiVersion),
    "description": Json("High-performance geospatial database"),
    "endpoints": Json([
      Json("POST /geo/location - Add location (201)"),
      Json("GET /geo/location - List all locations"),
      Json("GET /geo/location/:id - Get location by id"),
      Json("PUT /geo/location/:id - Replace name, position and metadata"),
      Json("DELETE /geo/location/:id - Remove location"),
      Json("POST /geo/nearby - Locations within a radius, nearest first"),
      Json("POST /geo/bounds - Locations in a bounding box (minLon > maxLon crosses ±180)"),
      Json("POST /geo/nearest - N nearest locations"),
      Json("POST /geo/distance - Distance between two points"),
      Json("GET /geo/stats - Database statistics"),
      Json("GET /geo/health - Liveness check")
    ])
  ]);
}

private void notFound(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeJsonBody(["error": Json("Not found"), "path": Json(req.requestPath.toString())], HTTPStatus.notFound);
}
