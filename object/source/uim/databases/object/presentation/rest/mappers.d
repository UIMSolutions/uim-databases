/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Conversion between vibe.d's Json (wire) and std.json's JSONValue (domain and application).
module uim.databases.object.presentation.rest.mappers;

import uim.databases.object.domain.exceptions : ValidationException;
import std.bigint : BigInt;
import std.conv : to;
import std.json : JSONType, JSONValue;
import vibe.data.json : Json;

@safe:

/// `undefined` becomes null. Throws: ValidationException for integers outside the 64-bit range.
JSONValue toJSONValue(Json value) {
  final switch (value.type) {
    case Json.Type.undefined, Json.Type.null_:
      return JSONValue(null);
    case Json.Type.bool_:
      return JSONValue(value.get!bool);
    case Json.Type.int_:
      return JSONValue(value.get!long);
    case Json.Type.bigInt:
      auto big = value.get!BigInt;
      if (big < 0 || big > BigInt(ulong.max)) {
        throw new ValidationException("Integer out of range: " ~ value.toString());
      }
      return JSONValue(value.toString().to!ulong);
    case Json.Type.float_:
      return JSONValue(value.get!double);
    case Json.Type.string:
      return JSONValue(value.get!string);
    case Json.Type.array:
      JSONValue[] items;
      foreach (item; value.byValue) {
        items ~= toJSONValue(item);
      }
      return JSONValue(items);
    case Json.Type.object:
      JSONValue[string] members;
      foreach (key, member; value.byKeyValue) {
        members[key] = toJSONValue(member);
      }
      return JSONValue(members);
  }
}

Json toJson(JSONValue value) {
  final switch (value.type) {
    case JSONType.null_:
      return Json(null);
    case JSONType.true_:
      return Json(true);
    case JSONType.false_:
      return Json(false);
    case JSONType.integer:
      return Json(value.integer);
    case JSONType.uinteger:
      return value.uinteger <= long.max ? Json(cast(long) value.uinteger) : Json(BigInt(value.uinteger));
    case JSONType.float_:
      return Json(value.floating);
    case JSONType.string:
      return Json(value.str);
    case JSONType.array:
      auto items = Json.emptyArray;
      foreach (item; value.arrayNoRef) {
        items ~= toJson(item);
      }
      return items;
    case JSONType.object:
      auto members = Json.emptyObject;
      foreach (key, member; value.objectNoRef) {
        members[key] = toJson(member);
      }
      return members;
  }
}

unittest {
  import vibe.data.json : parseJsonString;

  auto wire = parseJsonString(`{"a":[1,2.5,"x",true,null,{"b":{}}],"n":-3}`);
  assert(toJson(toJSONValue(wire)) == wire);
  assert(toJSONValue(Json.undefined).type == JSONType.null_);
  assert(toJson(JSONValue(ulong.max)).toString == "18446744073709551615");
}
