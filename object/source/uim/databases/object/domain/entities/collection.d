module uim.databases.object.domain.entities.collection;

import uim.databases.object.domain.entities.document;
import uim.databases.object.domain.entities.index;
import uim.databases.object.domain.enumerations;
import uim.databases.object.domain.exceptions;
import uim.databases.object.domain.services.jsonvalues : compareValues;
import uim.databases.object.domain.types;
import std.algorithm : filter, map, min, sort;
import std.array : array;
import std.datetime.systime : SysTime;
import std.json : JSONValue;

@safe:

/// Entity and aggregate root: a named set of JSON documents with optional equality indexes.
///
/// Queries scan every document unless an `==` condition hits an index, in which case only the indexed
/// candidates are tested. Indexes are kept in step with every change. Batch inserts are all-or-nothing.
final class DocumentCollection {
  private {
    string _name;
    Document[string] _documents;
    FieldIndex[string] _indexes;
    ulong _nextSequence;
  }

  /// Throws: ValidationException for an invalid name.
  this(string name) {
    requireCollectionName(name);
    _name = name;
  }

  string name() const pure nothrow @nogc {
    return _name;
  }

  size_t count() const pure nothrow @nogc {
    return _documents.length;
  }

  bool contains(string id) const pure nothrow @nogc {
    return (id in _documents) !is null;
  }

  // --- Documents ---

  /// Throws: DocumentAlreadyExistsException.
  void insert(Document document) {
    insertAll([document]);
  }

  /// Inserts all documents or none. Throws: DocumentAlreadyExistsException.
  void insertAll(Document[] documents) {
    bool[string] batch;
    foreach (document; documents) {
      if (document.id in _documents || document.id in batch) {
        throw new DocumentAlreadyExistsException(_name, document.id);
      }
      batch[document.id] = true;
    }
    foreach (document; documents) {
      document.assignSequence(_nextSequence++);
      _documents[document.id] = document;
      foreach (index; _indexes.byValue) {
        index.add(document.id, document.raw);
      }
    }
  }

  /// Throws: DocumentNotFoundException.
  Document get(string id) {
    return *require(id);
  }

  /// Replaces the data of a document, keeping its id and creation time.
  /// Throws: DocumentNotFoundException, ValidationException.
  Document replace(string id, JSONValue data, SysTime updatedAt) {
    auto document = require(id);
    requireObject(data); // before any change
    foreach (index; _indexes.byValue) {
      index.remove(id, document.raw);
    }
    document.replaceData(data, updatedAt);
    foreach (index; _indexes.byValue) {
      index.add(id, document.raw);
    }
    return *document;
  }

  /// Throws: DocumentNotFoundException.
  void remove(string id) {
    auto document = require(id);
    foreach (index; _indexes.byValue) {
      index.remove(id, document.raw);
    }
    _documents.remove(id);
  }

  /// Removes every document; index definitions stay.
  void clear() {
    _documents = null;
    foreach (index; _indexes.byValue) {
      index.clear();
    }
  }

  /// All documents in insertion order.
  Document[] all() {
    return inInsertionOrder(_documents.values);
  }

  // --- Queries ---

  /// Matching documents, sorted (missing sort fields last; ties in insertion order), then paged.
  Document[] find(const DocumentQuery query) {
    auto matches = candidates(query).filter!(d => query.matches(d.raw)).array;
    if (query.sort.isNull) {
      matches = inInsertionOrder(matches);
    } else {
      matches = sorted(matches, query.sort.get);
    }
    immutable start = min(query.skip, matches.length);
    immutable end = query.limit == 0 ? matches.length : min(start + query.limit, matches.length);
    return matches[start .. end];
  }

  /// Number of matching documents; sort and paging are ignored.
  size_t count(const DocumentQuery query) {
    size_t n;
    foreach (document; candidates(query)) {
      if (query.matches(document.raw)) {
        n++;
      }
    }
    return n;
  }

  // --- Indexes ---

  /// Field paths of all indexes, ordered.
  string[] indexedFields() const {
    return _indexes.keys.sort.release;
  }

  bool hasIndex(FieldPath field) const pure {
    return (field.toString in _indexes) !is null;
  }

  /// Builds the index from the current documents. Throws: IndexAlreadyExistsException.
  void createIndex(FieldPath field) {
    immutable key = field.toString;
    if (key in _indexes) {
      throw new IndexAlreadyExistsException(_name, key);
    }
    auto index = new FieldIndex(field);
    foreach (id, ref document; _documents) {
      index.add(id, document.raw);
    }
    _indexes[key] = index;
  }

  /// Throws: IndexNotFoundException.
  void dropIndex(FieldPath field) {
    if (!_indexes.remove(field.toString)) {
      throw new IndexNotFoundException(_name, field.toString);
    }
  }

  // --- Internals ---

  private Document* require(string id) {
    auto found = id in _documents;
    if (found is null) {
      throw new DocumentNotFoundException(_name, id);
    }
    return found;
  }

  /// The smallest candidate set an index offers for an `==` condition, or every document.
  private Document[] candidates(const DocumentQuery query) {
    string[] best;
    bool indexed;
    foreach (condition; query.conditions) {
      if (condition.operator != QueryOperator.EQUALS) {
        continue;
      }
      if (auto index = condition.field.toString in _indexes) {
        auto ids = (*index).lookup(condition.value);
        if (!indexed || ids.length < best.length) {
          best = ids;
          indexed = true;
        }
      }
    }
    return indexed ? best.map!(id => _documents[id]).array : _documents.values;
  }

  private static Document[] inInsertionOrder(Document[] documents) {
    return documents.sort!((a, b) => a.sequence < b.sequence).release;
  }

  private static Document[] sorted(Document[] documents, const SortOrder order) {
    static struct Keyed {
      Document document;
      bool present;
      JSONValue key;
    }

    auto keyed = documents.map!((d) {
      Keyed k;
      k.document = d;
      k.present = order.field.resolve(d.raw, k.key);
      return k;
    }).array;
    immutable ascending = order.direction == SortDirection.ASCENDING;
    keyed.sort!((a, b) {
      if (a.present != b.present) {
        return a.present; // missing values last, in both directions
      }
      if (a.present) {
        immutable c = compareValues(a.key, b.key);
        if (c != 0) {
          return ascending ? c < 0 : c > 0;
        }
      }
      return a.document.sequence < b.document.sequence;
    });
    return keyed.map!(k => k.document).array;
  }
}

unittest {
  import std.exception : assertThrown;
  import std.json : parseJSON;
  import std.typecons : nullable;

  auto t0 = SysTime(0);
  auto doc = (string id, string json) => Document(id, parseJSON(json), t0);
  auto ids = (Document[] docs) => docs.map!(d => d.id).array;
  auto where = (string field, QueryOperator op, string value) => Condition(FieldPath(field), op, parseJSON(value));

  auto users = new DocumentCollection("users");
  users.insertAll([
    doc("c", `{"name":"Cy","age":30,"city":"Rome"}`),
    doc("a", `{"name":"Ada","age":36,"city":"London"}`),
    doc("b", `{"name":"Bob","age":25.0,"city":"Rome"}`),
    doc("d", `{"name":"Dee"}`),
  ]);
  assert(users.count == 4 && ids(users.all) == ["c", "a", "b", "d"]);

  // Batches are all-or-nothing.
  assertThrown!DocumentAlreadyExistsException(users.insertAll([doc("e", "{}"), doc("a", "{}")]));
  assertThrown!DocumentAlreadyExistsException(users.insertAll([doc("e", "{}"), doc("e", "{}")]));
  assert(users.count == 4);

  auto rome = DocumentQuery([where("city", QueryOperator.EQUALS, `"Rome"`)]);
  assert(ids(users.find(rome)) == ["c", "b"] && users.count(rome) == 2);

  DocumentQuery byAge;
  byAge.sort = nullable(SortOrder(FieldPath("age")));
  assert(ids(users.find(byAge)) == ["b", "c", "a", "d"]);
  byAge.sort = nullable(SortOrder(FieldPath("age"), SortDirection.DESCENDING));
  assert(ids(users.find(byAge)) == ["a", "c", "b", "d"]);
  byAge.skip = 1;
  byAge.limit = 2;
  assert(ids(users.find(byAge)) == ["c", "b"]);
  byAge.skip = 10;
  assert(users.find(byAge).length == 0);

  // Indexes give the same answers and follow every change.
  users.createIndex(FieldPath("city"));
  assertThrown!IndexAlreadyExistsException(users.createIndex(FieldPath("city")));
  assert(ids(users.find(rome)) == ["c", "b"]);
  users.replace("c", parseJSON(`{"name":"Cy","city":"Oslo"}`), SysTime(1));
  assert(ids(users.find(rome)) == ["b"] && users.get("c").updatedAt == SysTime(1));
  assertThrown!ValidationException(users.replace("c", parseJSON("1"), t0));
  assert(users.get("c").data["city"].str == "Oslo"); // failed replace changed nothing
  users.remove("b");
  assert(users.find(rome).length == 0);
  users.insert(doc("b", `{"city":"Rome"}`));
  assert(ids(users.find(rome)) == ["b"]);

  users.clear();
  assert(users.count == 0 && users.indexedFields == ["city"] && users.find(rome).length == 0);
  users.insert(doc("x", `{"city":"Rome"}`));
  assert(ids(users.find(rome)) == ["x"]);

  users.dropIndex(FieldPath("city"));
  assertThrown!IndexNotFoundException(users.dropIndex(FieldPath("city")));
  assertThrown!DocumentNotFoundException(users.get("nope"));
  assertThrown!DocumentNotFoundException(users.remove("nope"));
  assertThrown!ValidationException(new DocumentCollection("bad name"));
}
