/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.geodb.domain.values.distance;

@safe:

enum double metersPerKilometer = 1000.0;
enum double metersPerMile = 1609.344;

/// Value object: a great-circle distance.
struct Distance {
  double meters = 0.0;

  double kilometers() const pure nothrow @nogc {
    return meters / metersPerKilometer;
  }

  double miles() const pure nothrow @nogc {
    return meters / metersPerMile;
  }

  int opCmp(const Distance other) const pure nothrow @nogc {
    return meters < other.meters ? -1 : (meters > other.meters ? 1 : 0);
  }
}

unittest {
  auto d = Distance(1609.344);
  assert(d.miles == 1.0);
  assert(d.kilometers == 1.609344);
  assert(Distance(1) < Distance(2));
}
