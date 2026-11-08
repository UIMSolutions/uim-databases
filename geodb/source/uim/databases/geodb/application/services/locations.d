/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.application.services.locations;

import uim.databases.geodb.application.dtos;
import uim.databases.geodb.application.exceptions;
import uim.databases.geodb.application.ports;
import uim.databases.geodb.domain;
import std.algorithm : map, sort;
import std.array : array;

@safe:

/// Implements the location CRUD use cases on top of any ILocationRepository.
final class LocationService : ILocationUseCase {
  private ILocationRepository _repository;

  this(ILocationRepository repository) {
    assert(repository !is null, "LocationService needs a repository");
    _repository = repository;
  }

  LocationData add(AddLocationCommand command) {
    auto location = GeoLocation(command.id, command.name, GeoPoint(command.latitude, command.longitude),
      command.metadata);
    if (_repository.contains(location.id)) {
      throw new LocationAlreadyExistsException(location.id);
    }
    _repository.save(location);
    return LocationData.from(location);
  }

  LocationData update(string id, UpdateLocationCommand command) {
    // Validate everything before touching stored state.
    auto point = GeoPoint(command.latitude, command.longitude);
    auto location = require(id);
    location.rename(command.name);
    location.moveTo(point);
    location.setMetadata(command.metadata);
    _repository.save(location);
    return LocationData.from(location);
  }

  LocationData get(string id) {
    return LocationData.from(require(id));
  }

  LocationData[] list() {
    auto all = _repository.findAll();
    all.sort!((a, b) => a.id < b.id);
    return all.map!(l => LocationData.from(l)).array;
  }

  void remove(string id) {
    if (!_repository.remove(id)) {
      throw new LocationNotFoundException(id);
    }
  }

  private GeoLocation require(string id) {
    auto found = _repository.findById(id);
    if (found.isNull) {
      throw new LocationNotFoundException(id);
    }
    return found.get;
  }
}

unittest {
  import uim.databases.geodb.application.testing : FakeLocationRepository;
  import std.exception : assertThrown;
  import std.json : JSONValue;

  auto repository = new FakeLocationRepository;
  auto service = new LocationService(repository);

  auto paris = service.add(AddLocationCommand("paris", "Paris", 48.8566, 2.3522, JSONValue(["country": "France"])));
  assert(paris.id == "paris" && paris.metadata["country"].str == "France");
  service.add(AddLocationCommand("berlin", "Berlin", 52.52, 13.405));
  assert(service.list().map!(l => l.id).array == ["berlin", "paris"]);

  assertThrown!LocationAlreadyExistsException(service.add(AddLocationCommand("paris", "x", 0, 0)));
  assertThrown!InvalidCoordinatesException(service.add(AddLocationCommand("bad", "x", 100, 0)));
  // Missing numbers arrive as NaN and are rejected by the domain.
  assertThrown!InvalidCoordinatesException(service.add(AddLocationCommand("nan", "x")));

  auto moved = service.update("paris", UpdateLocationCommand("Paris (moved)", 48.0, 2.0));
  assert(moved.name == "Paris (moved)" && moved.latitude == 48.0);
  assert(service.get("paris").metadata == JSONValue.emptyObject);

  // A failed update leaves the stored location unchanged.
  assertThrown!InvalidCoordinatesException(service.update("paris", UpdateLocationCommand("y", 0, 999)));
  assert(service.get("paris").name == "Paris (moved)");
  assertThrown!LocationNotFoundException(service.update("rome", UpdateLocationCommand("Rome", 41.9, 12.5)));

  service.remove("paris");
  assertThrown!LocationNotFoundException(service.get("paris"));
  assertThrown!LocationNotFoundException(service.remove("paris"));
}
