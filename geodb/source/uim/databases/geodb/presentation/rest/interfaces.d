/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// REST contract, usable both for registerRestInterface (server) and RestInterfaceClient (client).
/// Errors use HTTP status codes: 400 invalid input, 404 unknown id, 409 duplicate id.
module uim.databases.geodb.presentation.rest.interfaces;

import uim.databases.geodb.presentation.rest.models;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;

@path("/geo")
interface IGeoRestApi {
@safe:
  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/location") @bodyParam("request")
  RestLocation addLocation(RestLocationRequest request, @viaStatus out int status);

  @method(HTTPMethod.GET) @path("/location")
  RestLocationList getLocations();

  @method(HTTPMethod.GET) @path("/location/:id")
  RestLocation getLocation(string _id);

  @method(HTTPMethod.PUT) @path("/location/:id") @bodyParam("request")
  RestLocation updateLocation(string _id, RestLocationUpdateRequest request);

  @method(HTTPMethod.DELETE) @path("/location/:id")
  RestRemoved removeLocation(string _id);

  @method(HTTPMethod.POST) @path("/nearby") @bodyParam("request")
  RestNearbyResponse findNearby(RestNearbyRequest request);

  /// minLon > maxLon selects a box crossing the antimeridian.
  @method(HTTPMethod.POST) @path("/bounds") @bodyParam("request")
  RestBoundsResponse findInBounds(RestBoundsRequest request);

  @method(HTTPMethod.POST) @path("/nearest") @bodyParam("request")
  RestNearestResponse findNearest(RestNearestRequest request);

  @method(HTTPMethod.POST) @path("/distance") @bodyParam("request")
  RestDistanceResponse calculateDistance(RestDistanceRequest request);

  @method(HTTPMethod.GET) @path("/stats")
  RestStatsResponse getStats();

  @method(HTTPMethod.GET) @path("/health")
  RestStatus getHealth();
}
