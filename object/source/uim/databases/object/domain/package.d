/// Domain layer (innermost ring): business rules only; depends on Phobos alone, never on vibe.d or outer layers.
module uim.databases.object.domain;

public {
  import uim.databases.object.domain.exceptions;
  import uim.databases.object.domain.enumerations;
  import uim.databases.object.domain.types;
  import uim.databases.object.domain.services;
  import uim.databases.object.domain.entities;
}
