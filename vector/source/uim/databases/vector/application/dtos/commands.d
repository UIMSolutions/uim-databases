/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Requests entering the driving ports, as raw data; the interactors build validated domain values.
module uim.databases.vector.application.dtos.commands;

import std.typecons : Nullable;

@safe:

struct CreateCollectionCommand {
  string name;
  size_t dimension;
  /// EUCLIDEAN (default when empty), COSINE, MANHATTAN or DOT_PRODUCT.
  string metric;
}

struct AddVectorCommand {
  string id;
  double[] values;
  string[string] metadata;
}

/// A null field keeps the current value.
struct UpdateVectorCommand {
  Nullable!(double[]) values;
  Nullable!(string[string]) metadata;
}

struct SearchQuery {
  double[] vector;
  size_t k = 10;
  /// Only vectors whose metadata contains all these pairs.
  string[string] filter;
}

struct SimilarQuery {
  string id;
  size_t k = 10;
  string[string] filter;
}
