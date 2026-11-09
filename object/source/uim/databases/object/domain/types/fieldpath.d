module uim.databases.object.domain.types.fieldpath;

import uim.databases.object.domain.exceptions;
import std.algorithm : any;
import std.array : join, split;
import std.json : JSONType, JSONValue;
import std.uni : isControl;

@safe:

/// Value object: a dot-separated path into a document, e.g. `address.city`.
struct FieldPath {
  private immutable(string)[] _segments;

  /// Throws: ValidationException for an empty path, an empty segment, control characters or more than 256 characters.
  this(string path) {
    if (path.length == 0 || path.length > 256 || path.any!(c => isControl(c))) {
      throw new ValidationException("Invalid field path '" ~ path
          ~ "': use 1 to 256 characters without control characters");
    }
    auto segments = path.split(".");
    if (segments.any!(s => s.length == 0)) {
      throw new ValidationException("Invalid field path '" ~ path ~ "': empty segment");
    }
    _segments = segments.idup;
  }

  string toString() const pure {
    return _segments.join(".");
  }

  /// The value at this path, if every segment names a member of an object.
  bool resolve(JSONValue document, out JSONValue value) const {
    auto current = document;
    foreach (segment; _segments) {
      if (current.type != JSONType.object) {
        return false;
      }
      auto members = current.objectNoRef;
      auto found = segment in members;
      if (found is null) {
        return false;
      }
      current = *found;
    }
    value = current;
    return true;
  }
}

unittest {
  import std.exception : assertThrown;
  import std.json : parseJSON;

  auto doc = parseJSON(`{"name":"Ada","address":{"city":"Berlin"},"tags":["a"]}`);
  JSONValue value;
  assert(FieldPath("address.city").resolve(doc, value) && value.str == "Berlin");
  assert(FieldPath("name").resolve(doc, value) && value.str == "Ada");
  assert(!FieldPath("address.zip").resolve(doc, value));
  assert(!FieldPath("name.first").resolve(doc, value));
  assert(!FieldPath("tags.0").resolve(doc, value)); // no array indexing
  assert(FieldPath("address.city").toString == "address.city");

  assertThrown!ValidationException(FieldPath(""));
  assertThrown!ValidationException(FieldPath("a..b"));
  assertThrown!ValidationException(FieldPath(".a"));
}
