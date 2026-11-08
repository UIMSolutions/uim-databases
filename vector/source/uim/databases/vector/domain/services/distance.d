/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Pure vector math. Callers guarantee equal lengths (checked by contracts in debug builds).
module uim.databases.vector.domain.services.distance;

import uim.databases.vector.domain.enumerations;
import std.math : abs, sqrt;

@safe:

double euclideanDistance(const double[] a, const double[] b) pure nothrow @nogc
in (a.length == b.length) {
  double sum = 0.0;
  foreach (i; 0 .. a.length) {
    immutable d = a[i] - b[i];
    sum += d * d;
  }
  return sqrt(sum);
}

double manhattanDistance(const double[] a, const double[] b) pure nothrow @nogc
in (a.length == b.length) {
  double sum = 0.0;
  foreach (i; 0 .. a.length) {
    sum += abs(a[i] - b[i]);
  }
  return sum;
}

double dotProduct(const double[] a, const double[] b) pure nothrow @nogc
in (a.length == b.length) {
  double sum = 0.0;
  foreach (i; 0 .. a.length) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// Cosine similarity in [-1, 1]; 0 when either vector is all zeros.
double cosineSimilarity(const double[] a, const double[] b) pure nothrow @nogc
in (a.length == b.length) {
  double dot = 0.0, normA = 0.0, normB = 0.0;
  foreach (i; 0 .. a.length) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0.0 || normB == 0.0) {
    return 0.0;
  }
  return dot / (sqrt(normA) * sqrt(normB));
}

/// The vector scaled to length 1; an all-zero vector is returned unchanged.
double[] normalize(const double[] v) pure nothrow {
  double norm = 0.0;
  foreach (x; v) {
    norm += x * x;
  }
  norm = sqrt(norm);
  auto result = v.dup;
  if (norm != 0.0) {
    result[] /= norm;
  }
  return result;
}

/// Distance under `metric`; smaller means more similar for every metric.
double distance(const double[] a, const double[] b, DistanceMetric metric) pure nothrow @nogc
in (a.length == b.length) {
  final switch (metric) {
    case DistanceMetric.EUCLIDEAN:
      return euclideanDistance(a, b);
    case DistanceMetric.COSINE:
      return 1.0 - cosineSimilarity(a, b);
    case DistanceMetric.MANHATTAN:
      return manhattanDistance(a, b);
    case DistanceMetric.DOT_PRODUCT:
      return -dotProduct(a, b);
  }
}

unittest {
  import std.math : isClose;

  assert(euclideanDistance([0, 0], [3, 4]) == 5);
  assert(manhattanDistance([0, 0], [3, -4]) == 7);
  assert(dotProduct([1, 2], [3, 4]) == 11);
  assert(isClose(cosineSimilarity([1, 0], [0, 1]), 0.0));
  assert(cosineSimilarity([0, 0], [1, 1]) == 0);
  assert(isClose(distance([1, 1], [2, 2], DistanceMetric.COSINE), 0.0, 0, 1e-12));
  assert(distance([1, 2], [3, 4], DistanceMetric.DOT_PRODUCT) == -11);
  assert(normalize([3, 4]) == [0.6, 0.8] && normalize([0, 0]) == [0, 0]);
}
