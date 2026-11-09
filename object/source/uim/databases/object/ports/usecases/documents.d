/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: document CRUD.
module uim.databases.object.ports.usecases.documents;

import uim.databases.object.application.dtos;

interface IDocumentUseCase {
@safe:
  /// Throws: CollectionNotFoundException, ValidationException, DocumentAlreadyExistsException.
  DocumentData insertDocument(string collection, InsertDocumentCommand command);

  /// All-or-nothing. Throws: as insertDocument.
  DocumentData[] insertDocuments(string collection, InsertDocumentCommand[] commands);

  /// Throws: CollectionNotFoundException, DocumentNotFoundException.
  DocumentData getDocument(string collection, string id);

  /// Throws: CollectionNotFoundException, DocumentNotFoundException, ValidationException.
  DocumentData replaceDocument(string collection, string id, ReplaceDocumentCommand command);

  /// Throws: CollectionNotFoundException, DocumentNotFoundException.
  void removeDocument(string collection, string id);

  /// In insertion order. Throws: CollectionNotFoundException.
  DocumentData[] listDocuments(string collection);
}
