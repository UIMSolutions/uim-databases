/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.domain.enumerations.distancemetric;

import uim.databases.vector.domain.exceptions;
import std.string : strip, toUpper;
import std.array : replace;

@safe:

/// How "close" two vectors are. Every metric is a distance: smaller means more similar.
enum DistanceMetric {
  EUCLIDEAN, /// L2 distance
  COSINE, /// 1 - cosine similarity (0 for identical directions, 2 for opposite ones)
  MANHATTAN, /// L1 distance
  DOT_PRODUCT /// negative dot product, so a larger dot product ranks first
}

/// Accepts the enum names case-insensitively, with `-` or `_` (e.g. "dot-product", "cosine").
/// Throws: ValidationException.
DistanceMetric parseDistanceMetric(string name) {
  switch (name.strip.toUpper.replace("-", "_")) {
    case "EUCLIDEAN", "L2":
      return DistanceMetric.EUCLIDEAN;
    case "COSINE":
      return DistanceMetric.COSINE;
    case "MANHATTAN", "L1":
      return DistanceMetric.MANHATTAN;
    case "DOT_PRODUCT", "DOT":
      return DistanceMetric.DOT_PRODUCT;
    default:
      throw new ValidationException("Unknown distance metric '" ~ name
          ~ "'; use EUCLIDEAN, COSINE, MANHATTAN or DOT_PRODUCT");
  }
}

unittest {
  import std.exception : assertThrown;

  assert(parseDistanceMetric("dot-product") == DistanceMetric.DOT_PRODUCT);
  assert(parseDistanceMetric(" Cosine ") == DistanceMetric.COSINE);
  assertThrown!ValidationException(parseDistanceMetric("hamming"));
}
