/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Inbound (driving) ports: what the application offers to adapters such as the REST API or a CLI.
module uim.databases.geodb.application.ports.inbound;

import uim.databases.geodb.application.dtos;

/// Create, read, update and delete locations.
interface ILocationUseCase {
@safe:
  /// Throws: LocationAlreadyExistsException, GeoDomainException.
  LocationData add(AddLocationCommand command);

  /// Replaces name, position and metadata. Throws: LocationNotFoundException, GeoDomainException.
  LocationData update(string id, UpdateLocationCommand command);

  /// Throws: LocationNotFoundException.
  LocationData get(string id);

  /// All locations, ordered by id.
  LocationData[] list();

  /// Throws: LocationNotFoundException.
  void remove(string id);
}

/// Spatial queries and statistics.
interface IGeoQueryUseCase {
@safe:
  /// Locations within `radiusMeters`, nearest first.
  LocationMatch[] nearby(NearbyQuery query);

  /// Locations inside the box, ordered by id. The box may cross the antimeridian (minLon > maxLon).
  LocationData[] inBounds(BoundsQuery query);

  /// The `count` nearest locations, nearest first.
  LocationMatch[] nearest(NearestQuery query);

  /// Great-circle distance between two coordinates.
  DistanceData distance(DistanceQuery query);

  GeoStatistics statistics();
}
