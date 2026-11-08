/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Mapping between vibe.d JSON and the framework-free domain values.
module uim.databases.relational.presentation.rest.conversions;

import uim.databases.relational.application.dtos : ConditionSpec;
import uim.databases.relational.domain.types : RowData, Value, ValueKind;
import uim.databases.relational.presentation.rest.models : RestCondition;
import std.algorithm : map;
import std.array : array;
import std.string : strip, toUpper;
import vibe.data.json : Json, parseJsonString;
import vibe.http.common : HTTPStatusException;
import vibe.http.status : HTTPStatus;

@safe:

/// A missing value (`undefined`) becomes NULL; arrays and objects become JSON documents.
Value toValue(Json json) {
  final switch (json.type) {
    case Json.Type.undefined, Json.Type.null_:
      return Value.null_;
    case Json.Type.bool_:
      return Value.boolean(json.get!bool);
    case Json.Type.int_:
      return Value.integer(json.get!long);
    case Json.Type.bigInt:
      throw new HTTPStatusException(HTTPStatus.badRequest, "Integer out of 64-bit range: " ~ json.toString());
    case Json.Type.float_:
      return Value.floating(json.get!double);
    case Json.Type.string:
      return Value.text(json.get!string);
    case Json.Type.array, Json.Type.object:
      return Value.json(json.toString());
  }
}

Json toJson(const Value value) {
  final switch (value.kind) {
    case ValueKind.null_:
      return Json(null);
    case ValueKind.boolean:
      return Json(value.asBoolean);
    case ValueKind.integer:
      return Json(value.asInteger);
    case ValueKind.floating:
      return Json(value.asFloating);
    case ValueKind.text:
      return Json(value.asText);
    case ValueKind.json:
      return parseJsonString(value.asText);
  }
}

/// Throws: HTTPStatusException(400) unless `json` is an object.
RowData toRow(Json json) {
  if (json.type != Json.Type.object) {
    throw new HTTPStatusException(HTTPStatus.badRequest, "A row must be a JSON object");
  }
  RowData row;
  foreach (column, value; json.byKeyValue) {
    row[column] = toValue(value);
  }
  return row;
}

/// The row as a JSON object with the given columns.
Json toJson(const RowData row, const string[] columns) {
  auto json = Json.emptyObject;
  foreach (column; columns) {
    if (auto value = column in row) {
      json[column] = toJson(*value);
    }
  }
  return json;
}

/// For IN, the JSON array in `value` becomes the candidate list.
ConditionSpec toSpec(RestCondition condition) {
  if (condition.op.strip.toUpper == "IN") {
    if (condition.value.type != Json.Type.array) {
      throw new HTTPStatusException(HTTPStatus.badRequest, "IN on '" ~ condition.column ~ "' needs a JSON array");
    }
    Value[] candidates;
    foreach (item; condition.value.byValue) {
      candidates ~= toValue(item);
    }
    return ConditionSpec(condition.column, condition.op, Value.null_, candidates);
  }
  return ConditionSpec(condition.column, condition.op, toValue(condition.value));
}

ConditionSpec[] toSpecs(RestCondition[] conditions) {
  return conditions.map!(c => toSpec(c)).array;
}

unittest {
  import std.exception : assertThrown;

  assert(toValue(Json(42)) == Value.integer(42));
  assert(toValue(Json.undefined).isNull);
  assert(toValue(Json([Json(1)])) == Value.json("[1]"));
  assert(toJson(Value.json(`{"a":1}`))["a"].get!long == 1);
  assert(toJson(toValue(Json(1.5))) == Json(1.5));

  auto row = toRow(Json(["id": Json(1), "tags": Json([Json("x")])]));
  assert(row["id"] == Value.integer(1) && row["tags"].kind == ValueKind.json);
  assert(toJson(row, ["id"]) == Json(["id": Json(1)]));
  assertThrown!HTTPStatusException(toRow(Json(1)));

  auto spec = toSpec(RestCondition("id", "in", Json([Json(1), Json(2)])));
  assert(spec.values == [Value.integer(1), Value.integer(2)]);
  assertThrown!HTTPStatusException(toSpec(RestCondition("id", "IN", Json(1))));
}
