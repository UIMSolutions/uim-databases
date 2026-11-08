/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// vibe.d REST contract, usable for registerRestInterface (server) and RestInterfaceClient (client).
/// Errors: 400 invalid input, 404 unknown table or row, 409 constraint or name conflict; body {"statusMessage"}.
module uim.databases.relational.presentation.rest.interfaces;

import uim.databases.relational.presentation.rest.models;
import vibe.data.json : Json;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;

@path("/")
interface IRelationalRestApi {
@safe:
  @method(HTTPMethod.GET) @path("/health")
  RestHealth getHealth();

  @method(HTTPMethod.GET) @path("/stats")
  RestStats getStats();

  // --- Tables ---

  @method(HTTPMethod.GET) @path("/tables")
  RestTableList getTables();

  /// Responds 201 Created.
  @method(HTTPMethod.POST) @path("/tables") @bodyParam("request")
  RestTableCreated createTable(RestCreateTableRequest request, @viaStatus out int status);

  @method(HTTPMethod.DELETE) @path("/tables/:name")
  RestMessage dropTable(string _name);

  @method(HTTPMethod.GET) @path("/tables/:name/schema")
  RestSchema getSchema(string _name);

  @method(HTTPMethod.GET) @path("/tables/:name/count")
  RestCount getCount(string _name);

  // --- Rows ---

  /// Body: one row object, or {"rows": [ ... ]} for an all-or-nothing bulk insert. Responds 201 Created.
  @method(HTTPMethod.POST) @path("/tables/:name/insert") @bodyParam("body")
  RestInserted insertRows(string _name, Json body, @viaStatus out int status);

  @method(HTTPMethod.POST) @path("/tables/:name/select") @bodyParam("request")
  RestRows selectRows(string _name, RestSelectRequest request);

  @method(HTTPMethod.POST) @path("/tables/:name/update") @bodyParam("request")
  RestUpdated updateRows(string _name, RestUpdateRequest request);

  /// `where` is required.
  @method(HTTPMethod.POST) @path("/tables/:name/delete") @bodyParam("request")
  RestDeleted deleteRows(string _name, RestDeleteRequest request);

  /// The key is parsed by the type of the primary key column.
  @method(HTTPMethod.GET) @path("/tables/:name/rows/:pk")
  RestRow getRow(string _name, string _pk);

  // --- Joins ---

  @method(HTTPMethod.POST) @path("/join") @bodyParam("request")
  RestRows join(RestJoinRequest request);
}
