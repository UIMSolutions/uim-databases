/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.application.usecases.documents;

import uim.databases.object.application.dtos;
import uim.databases.object.application.usecases.support;
import uim.databases.object.domain;
import uim.databases.object.ports;
import std.algorithm : map;
import std.array : array;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.json : JSONType, JSONValue;
import std.uuid : randomUUID;

@safe:

alias TimeSource = SysTime delegate() @safe;
alias IdSource = string delegate() @safe;

/// Interactor for document CRUD.
final class DocumentInteractor : IDocumentUseCase {
  private {
    ICollectionRepository _repository;
    TimeSource _now;
    IdSource _newId;
  }

  /// `now` and `newId` default to the system clock (UTC) and random UUIDs; tests pass fixed ones.
  this(ICollectionRepository repository, TimeSource now = null, IdSource newId = null) {
    assert(repository !is null, "DocumentInteractor needs a repository");
    _repository = repository;
    _now = now !is null ? now : () @safe => Clock.currTime(UTC());
    _newId = newId !is null ? newId : () @safe => randomUUID().toString();
  }

  DocumentData insertDocument(string collection, InsertDocumentCommand command) {
    return insertDocuments(collection, [command])[0];
  }

  DocumentData[] insertDocuments(string collection, InsertDocumentCommand[] commands) {
    auto target = requireCollection(_repository, collection);
    immutable now = _now();
    auto documents = commands.map!(c => newDocument(c.document, now)).array;
    target.insertAll(documents);
    _repository.save(target);
    return documents.map!(d => DocumentData.from(target.get(d.id))).array;
  }

  DocumentData getDocument(string collection, string id) {
    return DocumentData.from(requireCollection(_repository, collection).get(id));
  }

  DocumentData replaceDocument(string collection, string id, ReplaceDocumentCommand command) {
    auto target = requireCollection(_repository, collection);
    auto data = command.document;
    requireObject(data);
    auto suppliedId = takeId(data);
    if (suppliedId.length > 0 && suppliedId != id) {
      throw new ValidationException("'_id' in the body ('" ~ suppliedId ~ "') differs from the document id '" ~ id ~ "'");
    }
    auto replaced = target.replace(id, data, _now());
    _repository.save(target);
    return DocumentData.from(replaced);
  }

  void removeDocument(string collection, string id) {
    auto target = requireCollection(_repository, collection);
    target.remove(id);
    _repository.save(target);
  }

  DocumentData[] listDocuments(string collection) {
    return requireCollection(_repository, collection).all().map!(d => DocumentData.from(d)).array;
  }

  private Document newDocument(JSONValue input, SysTime now) {
    requireObject(input);
    auto data = deepCopy(input); // the caller's value stays untouched
    auto id = takeId(data);
    return Document(id.length > 0 ? id : _newId(), data, now);
  }
}

/// Removes `_id` from a document and returns it ("" when absent). Throws: ValidationException.
private string takeId(ref JSONValue data) {
  auto members = data.objectNoRef;
  auto found = "_id" in members;
  if (found is null) {
    return "";
  }
  if (found.type != JSONType.string) {
    throw new ValidationException("'_id' must be a string");
  }
  auto id = found.str;
  members.remove("_id");
  data = JSONValue(members);
  return id;
}

unittest {
  import uim.databases.object.ports.repositories.fakes : FakeCollectionRepository;
  import std.conv : to;
  import std.exception : assertThrown;
  import std.json : parseJSON;

  auto repository = new FakeCollectionRepository;
  repository.save(new DocumentCollection("users"));
  long tick;
  size_t ids;
  auto documents = new DocumentInteractor(repository, () @safe => SysTime(++tick, UTC()),
    () @safe => "gen-" ~ (++ids).to!string);
  auto insert = (string json) => InsertDocumentCommand(parseJSON(json));

  auto ada = documents.insertDocument("users", insert(`{"_id":"ada","name":"Ada"}`));
  assert(ada.id == "ada" && ada.data == parseJSON(`{"name":"Ada"}`));
  assert(ada.createdAt == SysTime(1, UTC()).toISOExtString && ada.createdAt == ada.updatedAt);
  assert(documents.insertDocument("users", insert(`{"name":"Bob"}`)).id == "gen-1");

  auto batch = documents.insertDocuments("users", [insert(`{"n":1}`), insert(`{"_id":"x","n":2}`)]);
  assert(batch.map!(d => d.id).array == ["gen-2", "x"]);
  assertThrown!DocumentAlreadyExistsException(documents.insertDocuments("users", [insert(`{"_id":"y"}`), insert(`{"_id":"ada"}`)]));
  assertThrown!CollectionNotFoundException(documents.getDocument("nope", "y"));
  assertThrown!DocumentNotFoundException(documents.getDocument("users", "y")); // batch left nothing behind
  assertThrown!ValidationException(documents.insertDocument("users", insert(`[1]`)));
  assertThrown!ValidationException(documents.insertDocument("users", insert(`{"_id":7}`)));

  auto replaced = documents.replaceDocument("users", "ada", ReplaceDocumentCommand(parseJSON(`{"_id":"ada","name":"Ada L."}`)));
  assert(replaced.data == parseJSON(`{"name":"Ada L."}`) && replaced.createdAt == ada.createdAt && replaced.updatedAt != ada.updatedAt);
  assertThrown!ValidationException(documents.replaceDocument("users", "ada", ReplaceDocumentCommand(parseJSON(`{"_id":"bob"}`))));

  assert(documents.listDocuments("users").map!(d => d.id).array == ["ada", "gen-1", "gen-2", "x"]);
  documents.removeDocument("users", "x");
  assertThrown!DocumentNotFoundException(documents.removeDocument("users", "x"));
  assertThrown!CollectionNotFoundException(documents.listDocuments("nope"));
}
