/// Requests entering the driving ports, as raw data; the interactors build validated domain values.
module uim.databases.object.application.dtos.commands;

import std.json : JSONValue;

@safe:

/// A JSON object. A string member `_id` sets the document id (it is not stored in the data);
/// without it, a random UUID is used.
struct InsertDocumentCommand {
  JSONValue document;
}

/// A JSON object replacing the stored data. A member `_id`, if present, must equal the document id.
struct ReplaceDocumentCommand {
  JSONValue document;
}

struct ConditionInput {
  /// Dot-separated path, e.g. `address.city`.
  string field;
  /// See parseQueryOperator; empty means `==`.
  string op;
  JSONValue value;
}

struct FindQuery {
  ConditionInput[] where;
  /// Empty: insertion order.
  string sortField;
  bool descending;
  size_t skip;
  /// 0 means no limit.
  size_t limit;
}

struct CountQuery {
  ConditionInput[] where;
}
