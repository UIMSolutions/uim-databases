/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// vibe.d REST contract, usable for registerRestInterface (server) and RestInterfaceClient (client).
/// Errors: 400 invalid input, 404 unknown collection, document or index, 409 duplicate name, id or index;
/// body {"statusMessage"}.
module uim.databases.object.presentation.rest.interfaces;

import uim.databases.object.presentation.rest.models;
import vibe.data.json : Json;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;

@path("/")
interface IObjectRestApi {
@safe:
  @method(HTTPMethod.GET) @path("/health")
  RestHealth getHealth();

  @method(HTTPMethod.GET) @path("/stats")
  RestStats getStats();

  // --- Collections ---

  @method(HTTPMethod.GET) @path("/collections")
  RestCollectionList getCollections();

  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name")
  RestCollection createCollection(string _name, @viaStatus out int status);

  @method(HTTPMethod.GET) @path("/collections/:name")
  RestCollection getCollection(string _name);

  /// Same as GET /collections/:name.
  @method(HTTPMethod.GET) @path("/collections/:name/stats")
  RestCollection getCollectionStats(string _name);

  /// Deletes the collection with its documents and indexes. The default collection is protected (400).
  @method(HTTPMethod.DELETE) @path("/collections/:name")
  RestMessage dropCollection(string _name);

  /// Removes every document; indexes stay defined.
  @method(HTTPMethod.DELETE) @path("/collections/:name/clear")
  RestMessage clearCollection(string _name);

  // --- Documents ---

  /// Body: any JSON object; a string `_id` sets the id. Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name/documents") @bodyParam("document")
  RestDocument insertDocument(string _name, Json document, @viaStatus out int status);

  /// All-or-nothing. Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name/bulk") @bodyParam("request")
  RestBulkResult insertDocuments(string _name, RestBulkInsert request, @viaStatus out int status);

  /// In insertion order.
  @method(HTTPMethod.GET) @path("/collections/:name/documents")
  RestDocumentList getDocuments(string _name);

  /// Same as GET /collections/:name/documents.
  @method(HTTPMethod.GET) @path("/collections/:name/all")
  RestDocumentList getAllDocuments(string _name);

  @method(HTTPMethod.GET) @path("/collections/:name/documents/:id")
  RestDocument getDocument(string _name, string _id);

  /// Replaces the data; `_id` in the body is optional but must match.
  @method(HTTPMethod.PUT) @path("/collections/:name/documents/:id") @bodyParam("document")
  RestDocument replaceDocument(string _name, string _id, Json document);

  @method(HTTPMethod.DELETE) @path("/collections/:name/documents/:id")
  RestMessage removeDocument(string _name, string _id);

  // --- Queries ---

  /// Documents matching every condition, optionally sorted, then skip/limit.
  @method(HTTPMethod.POST) @path("/collections/:name/find") @bodyParam("request")
  RestDocumentList find(string _name, RestFindRequest request);

  @method(HTTPMethod.POST) @path("/collections/:name/count") @bodyParam("request")
  RestCount count(string _name, RestCountRequest request);

  // --- Indexes ---

  @method(HTTPMethod.GET) @path("/collections/:name/indexes")
  RestIndexList getIndexes(string _name);

  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name/indexes") @bodyParam("request")
  RestIndex createIndex(string _name, RestCreateIndex request, @viaStatus out int status);

  @method(HTTPMethod.DELETE) @path("/collections/:name/indexes/:field")
  RestMessage dropIndex(string _name, string _field);
}
