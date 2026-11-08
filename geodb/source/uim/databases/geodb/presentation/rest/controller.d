/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.presentation.rest.controller;

import uim.databases.geodb.application;
import uim.databases.geodb.domain.exceptions : GeoDomainException;
import uim.databases.geodb.presentation.rest.interfaces;
import uim.databases.geodb.presentation.rest.models;
import std.algorithm : map;
import std.array : array;
import std.json : JSONValue;
import vibe.data.json : Json;
import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;

@safe:

/// Inbound adapter: translates HTTP/JSON into use-case calls and use-case failures into HTTP status codes.
/// It holds no business logic.
final class GeoRestController : IGeoRestApi {
  private {
    ILocationUseCase _locations;
    IGeoQueryUseCase _queries;
  }

  this(ILocationUseCase locations, IGeoQueryUseCase queries) {
    assert(locations !is null && queries !is null, "GeoRestController needs both use cases");
    _locations = locations;
    _queries = queries;
  }

  RestLocation addLocation(RestLocationRequest request, out int status) {
    auto added = translate(() => _locations.add(AddLocationCommand(request.id, request.name,
        request.latitude, request.longitude, toStd(request.metadata))));
    status = HTTPStatus.created;
    return toRest(added);
  }

  RestLocationList getLocations() {
    auto all = translate(() => _locations.list());
    return RestLocationList(all.map!(l => toRest(l)).array, all.length);
  }

  RestLocation getLocation(string _id) {
    return toRest(translate(() => _locations.get(_id)));
  }

  RestLocation updateLocation(string _id, RestLocationUpdateRequest request) {
    return toRest(translate(() => _locations.update(_id, UpdateLocationCommand(request.name,
        request.latitude, request.longitude, toStd(request.metadata)))));
  }

  RestRemoved removeLocation(string _id) {
    translate(() => _locations.remove(_id));
    return RestRemoved(_id, "Location removed successfully");
  }

  RestNearbyResponse findNearby(RestNearbyRequest request) {
    auto matches = translate(() => _queries.nearby(NearbyQuery(request.latitude, request.longitude,
        request.radiusMeters)));
    return RestNearbyResponse(request.latitude, request.longitude, request.radiusMeters,
      matches.map!(m => toRest(m)).array, matches.length);
  }

  RestBoundsResponse findInBounds(RestBoundsRequest request) {
    auto found = translate(() => _queries.inBounds(BoundsQuery(request.minLat, request.maxLat,
        request.minLon, request.maxLon)));
    return RestBoundsResponse(request, found.map!(l => toRest(l)).array, found.length);
  }

  RestNearestResponse findNearest(RestNearestRequest request) {
    auto matches = translate(() => _queries.nearest(NearestQuery(request.latitude, request.longitude,
        cast(size_t) request.count)));
    return RestNearestResponse(request.latitude, request.longitude, request.count,
      matches.map!(m => toRest(m)).array, matches.length);
  }

  RestDistanceResponse calculateDistance(RestDistanceRequest request) {
    auto distance = translate(() => _queries.distance(DistanceQuery(request.lat1, request.lon1,
        request.lat2, request.lon2)));
    return RestDistanceResponse(distance.meters, distance.kilometers, distance.miles);
  }

  RestStatsResponse getStats() {
    auto stats = translate(() => _queries.statistics());
    return RestStatsResponse(stats.databaseName, stats.locationCount);
  }

  RestStatus getHealth() {
    return RestStatus("UP");
  }
}

/// Runs a use case and maps application/domain failures to HTTP errors. Anything else stays a 500.
private T translate(T)(scope T delegate() @safe action) {
  try {
    return action();
  } catch (LocationNotFoundException e) {
    throw new HTTPStatusException(HTTPStatus.notFound, e.msg);
  } catch (LocationAlreadyExistsException e) {
    throw new HTTPStatusException(HTTPStatus.conflict, e.msg);
  } catch (GeoDomainException e) {
    throw new HTTPStatusException(HTTPStatus.badRequest, e.msg);
  }
}

// --- Mapping between the wire format and the application DTOs ---

private JSONValue toStd(Json value) {
  // A missing field arrives as `undefined`; the domain treats null as "no metadata".
  return value.type == Json.Type.undefined ? JSONValue(null) : cast(JSONValue) value;
}

private Json toVibe(const JSONValue value) {
  return Json(value);
}

private RestLocation toRest(LocationData data) {
  return RestLocation(data.id, data.name, data.latitude, data.longitude, toVibe(data.metadata));
}

private RestLocationMatch toRest(LocationMatch match) {
  with (match.location) {
    return RestLocationMatch(id, name, latitude, longitude, toVibe(metadata), match.distanceMeters);
  }
}

unittest {
  import uim.databases.geodb.application.testing : FakeLocationRepository;
  import std.exception : collectException;

  auto repository = new FakeLocationRepository;
  auto api = new GeoRestController(new LocationService(repository), new GeoQueryService(repository, "test"));

  int status;
  auto paris = api.addLocation(RestLocationRequest("paris", "Paris", 48.8566, 2.3522,
      Json(["country": Json("France"), "population": Json(2_161_000)])), status);
  assert(status == HTTPStatus.created);
  assert(paris.metadata["population"].get!long == 2_161_000);
  api.addLocation(RestLocationRequest("london", "London", 51.5074, -0.1278), status);
  assert(api.getLocation("london").metadata == Json.emptyObject);

  HTTPStatus statusOf(void delegate() @safe call) {
    auto e = collectException!HTTPStatusException(call());
    assert(e !is null, "expected an HTTPStatusException");
    return cast(HTTPStatus) e.status;
  }

  assert(statusOf({ api.addLocation(RestLocationRequest("paris", "Again", 0, 0), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.addLocation(RestLocationRequest("x", "Bad", 95, 0), status); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.addLocation(RestLocationRequest("y", "Bad", 0, 0, Json("text")), status); })
      == HTTPStatus.badRequest);
  assert(statusOf({ api.getLocation("nowhere"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.findNearby(RestNearbyRequest(0, 0, -1)); }) == HTTPStatus.badRequest);

  auto nearby = api.findNearby(RestNearbyRequest(48.8566, 2.3522, 500_000));
  assert(nearby.count == 2 && nearby.locations[0].id == "paris");
  assert(api.findNearest(RestNearestRequest(51.5, 0, 1)).locations[0].id == "london");
  assert(api.findInBounds(RestBoundsRequest(40, 50, 0, 5)).count == 1);
  assert(api.getLocations().count == 2);
  assert(api.getStats() == RestStatsResponse("test", 2));

  auto updated = api.updateLocation("paris", RestLocationUpdateRequest("Paris", 48.86, 2.35));
  assert(updated.latitude == 48.86 && updated.metadata == Json.emptyObject);

  assert(api.removeLocation("paris").id == "paris");
  assert(statusOf({ api.removeLocation("paris"); }) == HTTPStatus.notFound);
}
