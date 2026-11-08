/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Domain layer (innermost ring): business rules only; depends on Phobos alone, never on vibe.d or outer layers.
module uim.databases.relational.domain;

public {
  import uim.databases.relational.domain.exceptions;
  import uim.databases.relational.domain.enumerations;
  import uim.databases.relational.domain.types;
  import uim.databases.relational.domain.entities;
  import uim.databases.relational.domain.services;
}
