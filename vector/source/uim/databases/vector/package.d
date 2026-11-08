/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Vector database (exact k-nearest-neighbour search) with a hexagonal / Clean Architecture.
///
/// Dependencies point inwards only:
///   presentation (vibe.d REST/HTTP) ──> ports.usecases / ports.services ──> application ──> domain
///   persistence (repositories)      ──> ports.repositories
///   infrastructure (configuration, logging): used by the composition root only
/// The domain and application layers depend on Phobos alone. Wiring happens in source/app.d.
module uim.databases.vector;

public {
  import uim.databases.vector.domain;
  import uim.databases.vector.application;
  import uim.databases.vector.ports;
  import uim.databases.vector.persistence;
  import uim.databases.vector.infrastructure;
  import uim.databases.vector.presentation;
}
