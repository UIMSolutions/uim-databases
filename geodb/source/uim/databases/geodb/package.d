/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Geospatial database with a clean/hexagonal architecture.
///
/// Dependencies point inwards only:
///   presentation (inbound adapters, vibe.d) ─┐
///                                            ├─> application (use cases + ports) ─> domain
///   infrastructure (outbound adapters)  ─────┘
/// The domain and application layers depend on Phobos alone; vibe.d is confined to the adapters.
/// Wiring happens in the composition root (source/app.d).
module uim.databases.geodb;

public {
  import uim.databases.geodb.domain;
  import uim.databases.geodb.application;
  import uim.databases.geodb.infrastructure;
  import uim.databases.geodb.presentation;
}
