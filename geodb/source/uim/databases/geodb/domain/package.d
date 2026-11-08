/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Domain layer (innermost ring): business rules only; depends on Phobos alone, never on vibe.d or outer layers.
module uim.databases.geodb.domain;

public {
  import uim.databases.geodb.domain.exceptions;
  import uim.databases.geodb.domain.values;
  import uim.databases.geodb.domain.entities;
  import uim.databases.geodb.domain.services;
}
