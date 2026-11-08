/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.domain.types.embedding;

import uim.databases.vector.domain.exceptions;
import std.algorithm : all;
import std.math : isFinite;

@safe:

/// Largest dimension a collection accepts.
enum size_t maxDimension = 65_536;

/// Value object: a non-empty list of finite numbers. The values are immutable, so copies share them safely.
struct Embedding {
  private immutable(double)[] _values;

  /// Throws: ValidationException for an empty or too long list, NaN or infinity.
  this(const double[] values) {
    if (values.length == 0) {
      throw new ValidationException("A vector needs at least one value");
    }
    if (values.length > maxDimension) {
      throw new ValidationException("A vector may have at most 65536 values");
    }
    if (!values.all!(v => isFinite(v))) {
      throw new ValidationException("Vector values must be finite numbers");
    }
    _values = values.idup;
  }

  immutable(double)[] values() const pure nothrow @nogc {
    return _values;
  }

  size_t dimension() const pure nothrow @nogc {
    return _values.length;
  }
}

/// Metadata of a vector: free-form text attributes, used for filtering.
alias Metadata = string[string];

/// True when `metadata` holds every key of `criteria` with the same value (empty criteria match everything).
bool matchesMetadata(const Metadata metadata, const Metadata criteria) pure nothrow @nogc {
  foreach (key, value; criteria) {
    auto found = key in metadata;
    if (found is null || *found != value) {
      return false;
    }
  }
  return true;
}

/// A copy, so callers never share an associative array with stored data.
Metadata copyMetadata(const Metadata metadata) pure nothrow {
  Metadata copy;
  foreach (key, value; metadata) {
    copy[key] = value;
  }
  return copy;
}

unittest {
  import std.exception : assertThrown;

  auto e = Embedding([1.0, 2.0]);
  assert(e.dimension == 2 && e.values == [1.0, 2.0]);
  assertThrown!ValidationException(Embedding([]));
  assertThrown!ValidationException(Embedding([1.0, double.nan]));
  assertThrown!ValidationException(Embedding([double.infinity]));

  Metadata m = ["lang": "de", "kind": "doc"];
  assert(matchesMetadata(m, ["lang": "de"]) && matchesMetadata(m, null));
  assert(!matchesMetadata(m, ["lang": "en"]) && !matchesMetadata(m, ["x": "y"]));
}
