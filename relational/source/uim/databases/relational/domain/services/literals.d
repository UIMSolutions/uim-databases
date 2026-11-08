/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.services.literals;

import uim.databases.relational.domain.enumerations;
import uim.databases.relational.domain.exceptions;
import uim.databases.relational.domain.types.value;
import std.conv : ConvException, to;

@safe:

/// Interprets a textual literal (e.g. a key taken from a URL) as a value of the given column type.
/// Throws: ValidationException when the text does not fit the type.
Value parseLiteral(string text, ColumnType type) {
  try {
    final switch (type) {
      case ColumnType.INTEGER:
        return Value.integer(text.to!long);
      case ColumnType.FLOAT:
        return Value.floating(text.to!double);
      case ColumnType.BOOLEAN:
        return Value.boolean(text.to!bool);
      case ColumnType.STRING, ColumnType.DATE, ColumnType.JSON:
        return Value.text(text);
    }
  } catch (ConvException) {
    throw new ValidationException("'" ~ text ~ "' is not a valid " ~ type.to!string);
  }
}

unittest {
  import std.exception : assertThrown;

  assert(parseLiteral("42", ColumnType.INTEGER) == Value.integer(42));
  assert(parseLiteral("true", ColumnType.BOOLEAN) == Value.boolean(true));
  assert(parseLiteral("x", ColumnType.STRING) == Value.text("x"));
  assertThrown!ValidationException(parseLiteral("4x", ColumnType.INTEGER));
}
