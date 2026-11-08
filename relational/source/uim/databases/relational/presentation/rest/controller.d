/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.presentation.rest.controller;

import uim.databases.relational.application.dtos;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types : QueryResult, RowData, Value;
import uim.databases.relational.ports;
import uim.databases.relational.presentation.rest.conversions;
import uim.databases.relational.presentation.rest.interfaces;
import uim.databases.relational.presentation.rest.models;
import std.algorithm : map;
import std.array : array;
import std.typecons : Nullable, nullable;
import vibe.data.json : Json;
import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;

@safe:

/// Inbound adapter: maps HTTP/JSON onto the driving ports and business errors onto status codes.
/// It holds no business logic.
final class RelationalRestController : IRelationalRestApi {
  private {
    ITableCatalogUseCase _catalog;
    IRowUseCase _rows;
    IJoinUseCase _joins;
    IDatabaseInfoService _info;
  }

  this(ITableCatalogUseCase catalog, IRowUseCase rows, IJoinUseCase joins, IDatabaseInfoService info) {
    assert(catalog !is null && rows !is null && joins !is null && info !is null);
    _catalog = catalog;
    _rows = rows;
    _joins = joins;
    _info = info;
  }

  RestHealth getHealth() {
    auto health = translate(() => _info.health());
    return RestHealth(health.status, health.type, health.tableCount);
  }

  RestStats getStats() {
    auto stats = translate(() => _info.statistics());
    return RestStats(stats.name, stats.tableCount,
      stats.tables.map!(t => RestTableStats(t.name, t.rowCount, t.columnCount)).array);
  }

  RestTableList getTables() {
    auto names = translate(() => _catalog.listTables());
    return RestTableList(names, names.length);
  }

  RestTableCreated createTable(RestCreateTableRequest request, out int status) {
    auto command = CreateTableCommand(request.name,
      request.columns.map!(c => ColumnSpec(c.name, c.type, c.nullable, c.primaryKey, c.unique, toDefault(c.defaultValue))).array,
      request.foreignKeys.map!(f => ForeignKeySpec(f.column, f.refTable, f.refColumn)).array);
    auto created = translate(() => _catalog.createTable(command));
    status = HTTPStatus.created;
    return RestTableCreated(created.tableName, "Table created successfully");
  }

  RestMessage dropTable(string _name) {
    translate(() => _catalog.dropTable(_name));
    return RestMessage("Table dropped successfully");
  }

  RestSchema getSchema(string _name) {
    auto schema = translate(() => _catalog.describeTable(_name));
    return RestSchema(schema.tableName, schema.primaryKey,
      schema.columns.map!(c => RestColumnInfo(c.name, c.type, c.nullable, c.primaryKey, c.unique,
        c.defaultValue.isNull ? Json(null) : toJson(c.defaultValue.get))).array,
      schema.foreignKeys.map!(f => RestForeignKey(f.column, f.refTable, f.refColumn)).array);
  }

  RestCount getCount(string _name) {
    return RestCount(translate(() => _rows.count(_name)));
  }

  RestInserted insertRows(string _name, Json body, out int status) {
    RowData[] rows;
    // `in`, not opIndex: indexing a mutable Json object adds the missing key.
    auto bulk = body.type == Json.Type.object ? "rows" in body : null;
    if (bulk !is null && bulk.type == Json.Type.array) {
      foreach (row; bulk.byValue) {
        rows ~= toRow(row);
      }
    } else {
      rows = [toRow(body)];
    }
    auto ids = translate(() => _rows.insert(_name, rows));
    status = HTTPStatus.created;
    return RestInserted(ids.length, ids, ids.length == 1 ? "Row inserted successfully" : "Bulk insert completed");
  }

  RestRows selectRows(string _name, RestSelectRequest request) {
    auto select = SelectRequest(request.columns, toSpecs(request.where), request.orderBy, request.ascending,
      cast(size_t) request.limit, cast(size_t) request.offset);
    return toRest(translate(() => _rows.select(_name, select)));
  }

  RestUpdated updateRows(string _name, RestUpdateRequest request) {
    auto command = UpdateCommand(toRow(request.set), toSpecs(request.where));
    return RestUpdated(translate(() => _rows.update(_name, command)), "Rows updated successfully");
  }

  RestDeleted deleteRows(string _name, RestDeleteRequest request) {
    auto command = DeleteCommand(toSpecs(request.where));
    return RestDeleted(translate(() => _rows.remove(_name, command)), "Rows deleted successfully");
  }

  RestRow getRow(string _name, string _pk) {
    auto row = translate(() => _rows.findByPrimaryKey(_name, _pk));
    return RestRow(toJson(row, row.keys));
  }

  RestRows join(RestJoinRequest request) {
    auto joinRequest = JoinRequest(request.leftTable, request.rightTable, request.leftColumn, request.rightColumn,
      toSpecs(request.leftWhere), toSpecs(request.rightWhere));
    return toRest(translate(() => _joins.innerJoin(joinRequest)));
  }
}

/// Runs a port call and maps business errors to HTTP errors; anything else stays a 500.
private T translate(T)(scope T delegate() @safe action) {
  try {
    return action();
  } catch (NotFoundException e) {
    throw new HTTPStatusException(HTTPStatus.notFound, e.msg);
  } catch (ConflictException e) {
    throw new HTTPStatusException(HTTPStatus.conflict, e.msg);
  } catch (ValidationException e) {
    throw new HTTPStatusException(HTTPStatus.badRequest, e.msg);
  }
}

private Nullable!Value toDefault(Json json) {
  return json.type == Json.Type.undefined ? Nullable!Value.init : nullable(toValue(json));
}

private RestRows toRest(QueryResult result) {
  return RestRows(result.columns, result.rows.map!(r => toJson(r, result.columns)).array, result.count);
}

unittest {
  import uim.databases.relational.application.services : DatabaseInfoService;
  import uim.databases.relational.application.usecases;
  import uim.databases.relational.ports.repositories.fakes : FakeTableRepository;
  import std.exception : collectException;

  auto repository = new FakeTableRepository;
  auto api = new RelationalRestController(new TableCatalogInteractor(repository), new RowInteractor(repository),
    new JoinInteractor(repository), new DatabaseInfoService(repository, "main"));

  HTTPStatus statusOf(void delegate() @safe call) {
    auto e = collectException!HTTPStatusException(call());
    assert(e !is null, "expected an HTTPStatusException");
    return cast(HTTPStatus) e.status;
  }

  int status;
  api.createTable(RestCreateTableRequest("users", [
      RestColumn("id", "INTEGER", false, true),
      RestColumn("email", "STRING", false, false, true),
      RestColumn("active", "BOOLEAN", false, false, false, Json(true)),
    ]), status);
  assert(status == HTTPStatus.created);
  assert(api.getSchema("users").columns[2].defaultValue == Json(true));

  auto inserted = api.insertRows("users", Json(["rows": Json([
        Json(["id": Json(1), "email": Json("a@x")]),
        Json(["id": Json(2), "email": Json("b@x"), "active": Json(false)]),
      ])]), status);
  assert(inserted.inserted == 2 && status == HTTPStatus.created);
  assert(api.insertRows("users", Json(["id": Json(3), "email": Json("c@x")]), status).rowIds == [3]);

  auto active = api.selectRows("users", RestSelectRequest(null, [RestCondition("active", "=", Json(true))], "id", false));
  assert(active.count == 2 && active.rows[0]["id"] == Json(3));
  assert(api.getRow("users", "2").row["active"] == Json(false));
  assert(api.updateRows("users", RestUpdateRequest(Json(["active": Json(false)]), [RestCondition("id", ">", Json(2))])).updated == 1);

  assert(statusOf({ api.getRow("users", "9"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.getCount("nope"); }) == HTTPStatus.notFound);
  assert(statusOf({ api.insertRows("users", Json(["id": Json(1), "email": Json("z@x")]), status); }) == HTTPStatus.conflict);
  assert(statusOf({ api.insertRows("users", Json(["id": Json("x"), "email": Json("z@x")]), status); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.deleteRows("users", RestDeleteRequest()); }) == HTTPStatus.badRequest);
  assert(statusOf({ api.createTable(RestCreateTableRequest("users", [RestColumn("id", "INTEGER")]), status); }) == HTTPStatus.conflict);

  api.createTable(RestCreateTableRequest("orders", [
      RestColumn("id", "INTEGER", false, true), RestColumn("user_id", "INTEGER"), RestColumn("meta", "JSON"),
    ], [RestForeignKey("user_id", "users", "id")]), status);
  api.insertRows("orders", Json(["id": Json(10), "user_id": Json(1), "meta": Json(["gift": Json(true)])]), status);
  auto joined = api.join(RestJoinRequest("users", "orders", "id", "user_id"));
  assert(joined.count == 1 && joined.rows[0]["orders.meta"]["gift"] == Json(true));
  assert(statusOf({ api.dropTable("users"); }) == HTTPStatus.conflict);

  assert(api.deleteRows("users", RestDeleteRequest([RestCondition("id", "IN", Json([Json(2), Json(3)]))])).deleted == 2);
  assert(api.getStats().tables[1] == RestTableStats("users", 1, 3));
  assert(api.getHealth().tableCount == 2);
}
