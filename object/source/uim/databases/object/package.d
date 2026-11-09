/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Object / document database (JSON documents in named collections, queries and equality indexes)
/// with a hexagonal / Clean Architecture.
///
/// Dependencies point inwards only:
///   presentation (vibe.d REST/HTTP) ──> ports.usecases / ports.services ──> application ──> domain
///   persistence (repositories)      ──> ports.repositories
///   infrastructure (configuration, logging): used by the composition root only
/// The domain and application layers depend on Phobos alone. Wiring happens in source/app.d.
module uim.databases.object;

public {
  import uim.databases.object.domain;
  import uim.databases.object.application;
  import uim.databases.object.ports;
  import uim.databases.object.persistence;
  import uim.databases.object.infrastructure;
  import uim.databases.object.presentation;
}
