/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Relational in-memory database with a hexagonal / Clean Architecture.
///
/// Dependencies point inwards only:
///   presentation (vibe.d REST/HTTP) ──> ports.usecases / ports.services ──> application ──> domain
///   persistence (repositories)      ──> ports.repositories
///   infrastructure (configuration, logging): used by the composition root only
/// The domain and application layers depend on Phobos alone. Wiring happens in source/app.d.
module uim.databases.relational;

public {
  import uim.databases.relational.domain;
  import uim.databases.relational.application;
  import uim.databases.relational.ports;
  import uim.databases.relational.persistence;
  import uim.databases.relational.infrastructure;
  import uim.databases.relational.presentation;
}
