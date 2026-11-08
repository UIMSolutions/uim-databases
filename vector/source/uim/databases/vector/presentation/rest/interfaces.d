/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// vibe.d REST contract, usable for registerRestInterface (server) and RestInterfaceClient (client).
/// Errors: 400 invalid input, 404 unknown collection or vector, 409 duplicate name or id; body {"statusMessage"}.
module uim.databases.vector.presentation.rest.interfaces;

import uim.databases.vector.presentation.rest.models;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;

@path("/")
interface IVectorRestApi {
@safe:
  @method(HTTPMethod.GET) @path("/health")
  RestHealth getHealth();

  @method(HTTPMethod.GET) @path("/stats")
  RestStats getStats();

  // --- Collections ---

  @method(HTTPMethod.GET) @path("/collections")
  RestCollectionList getCollections();

  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections") @bodyParam("request")
  RestCollection createCollection(RestCreateCollection request, @viaStatus out int status);

  @method(HTTPMethod.GET) @path("/collections/:name")
  RestCollection getCollection(string _name);

  /// Deletes the collection and all its vectors.
  @method(HTTPMethod.DELETE) @path("/collections/:name")
  RestMessage dropCollection(string _name);

  // --- Vectors ---

  @method(HTTPMethod.GET) @path("/collections/:name/vectors")
  RestIdList getVectorIds(string _name);

  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name/vectors") @bodyParam("request")
  RestVector addVector(string _name, RestVectorInput request, @viaStatus out int status);

  /// All-or-nothing. Responds 201 Created.
  @method(HTTPMethod.POST) @path("/collections/:name/vectors/batch") @bodyParam("request")
  RestVectorList addVectors(string _name, RestVectorBatch request, @viaStatus out int status);

  @method(HTTPMethod.GET) @path("/collections/:name/vectors/:id")
  RestVector getVector(string _name, string _id);

  @method(HTTPMethod.PUT) @path("/collections/:name/vectors/:id") @bodyParam("request")
  RestVector updateVector(string _name, string _id, RestVectorUpdate request);

  @method(HTTPMethod.DELETE) @path("/collections/:name/vectors/:id")
  RestMessage removeVector(string _name, string _id);

  /// Vectors whose metadata contains every given pair.
  @method(HTTPMethod.POST) @path("/collections/:name/filter") @bodyParam("request")
  RestVectorList filterVectors(string _name, RestFilterRequest request);

  // --- Search ---

  /// The k nearest vectors to `vector`, nearest first.
  @method(HTTPMethod.POST) @path("/collections/:name/search") @bodyParam("request")
  RestSearchResponse search(string _name, RestSearchRequest request);

  /// The k nearest vectors to a stored vector, excluding that vector.
  @method(HTTPMethod.POST) @path("/collections/:name/vectors/:id/similar") @bodyParam("request")
  RestSearchResponse searchSimilar(string _name, string _id, RestSimilarRequest request);
}
