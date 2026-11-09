module uim.databases.object.domain.entities.index;

import uim.databases.object.domain.services.jsonvalues : canonicalKey;
import uim.databases.object.domain.types.fieldpath;
import std.json : JSONValue;

@safe:

/// Entity: an equality index on one field path (identity: the path). It maps the canonical key of the
/// field value to the ids of the documents holding it; documents without the field are not indexed.
final class FieldIndex {
  private {
    FieldPath _field;
    bool[string][string] _entries;
  }

  this(FieldPath field) {
    _field = field;
  }

  FieldPath field() const pure nothrow @nogc {
    return _field;
  }

  void add(string id, JSONValue document) {
    JSONValue value;
    if (_field.resolve(document, value)) {
      _entries.require(canonicalKey(value))[id] = true;
    }
  }

  void remove(string id, JSONValue document) {
    JSONValue value;
    if (!_field.resolve(document, value)) {
      return;
    }
    string key = canonicalKey(value);
    if (auto ids = key in _entries) {
      (*ids).remove(id);
      if (ids.length == 0) {
        _entries.remove(key);
      }
    }
  }

  /// Ids of the documents whose field equals `value`, in no particular order.
  string[] lookup(JSONValue value) {
    auto ids = canonicalKey(value) in _entries;
    return ids is null ? null : ids.keys;
  }

  /// Number of distinct indexed values.
  size_t distinctValues() const pure nothrow @nogc {
    return _entries.length;
  }

  void clear() pure nothrow {
    _entries = null;
  }
}

unittest {
  import std.algorithm : sort;
  import std.json : parseJSON;

  auto index = new FieldIndex(FieldPath("a.b"));
  index.add("1", parseJSON(`{"a":{"b":1}}`));
  index.add("2", parseJSON(`{"a":{"b":1.0}}`));
  index.add("3", parseJSON(`{"a":{"b":"1"}}`));
  index.add("4", parseJSON(`{"a":{}}`));
  assert(index.lookup(parseJSON("1")).sort.release == ["1", "2"]);
  assert(index.lookup(parseJSON(`"1"`)) == ["3"] && index.distinctValues == 2);

  index.remove("1", parseJSON(`{"a":{"b":1}}`));
  index.remove("2", parseJSON(`{"a":{"b":1}}`));
  assert(index.lookup(parseJSON("1")) is null && index.distinctValues == 1);
}
