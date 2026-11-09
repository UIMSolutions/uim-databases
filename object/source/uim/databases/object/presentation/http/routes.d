/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.presentation.http.routes;

import uim.databases.object.presentation.rest.interfaces : IObjectRestApi;
import vibe.core.log : logError;
import vibe.data.json : Json;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.status : HTTPStatus;
import vibe.web.rest : registerRestInterface, RestErrorInformation, RestInterfaceSettings;

@safe:

/// Mounts the REST API, a text index at `/` and a JSON 404 for everything else.
void registerRoutes(URLRouter router, IObjectRestApi api) {
  auto settings = new RestInterfaceSettings;
  settings.errorHandler = (req, res, error) => writeError(req, res, error);
  router.registerRestInterface(api, settings);
  router.get("/", &index);
  router.any("*", &notFound);
}

/// Same error body in debug and release builds: `{"statusMessage": ...}`. Client errors (including malformed
/// request bodies) keep their message; server errors are logged and never expose internals.
private void writeError(HTTPServerRequest req, HTTPServerResponse res, RestErrorInformation error) {
  string message = error.exception !is null ? error.exception.msg : "";
  if (error.statusCode >= 500) {
    logError("%s %s failed: %s", req.method, req.requestPath, message);
    message = "Internal server error";
  }
  res.writeJsonBody(["statusMessage": Json(message)], error.statusCode);
}

private void index(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeBody("Object Database API - Use /health for status", "text/plain");
}

private void notFound(HTTPServerRequest req, HTTPServerResponse res) {
  res.writeJsonBody(["error": Json("Not found"), "path": Json(req.requestPath.toString())], HTTPStatus.notFound);
}
