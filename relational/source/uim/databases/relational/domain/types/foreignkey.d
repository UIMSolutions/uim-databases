/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.domain.types.foreignkey;

import uim.databases.relational.domain.types.identifier;

@safe:

/// Value object: `column` references `referencedTable.referencedColumn`.
struct ForeignKey {
  private {
    string _column;
    string _referencedTable;
    string _referencedColumn;
  }

  /// Throws: SchemaException for invalid names.
  this(string column, string referencedTable, string referencedColumn) {
    requireIdentifier(column, "foreign key column");
    requireIdentifier(referencedTable, "referenced table");
    requireIdentifier(referencedColumn, "referenced column");
    _column = column;
    _referencedTable = referencedTable;
    _referencedColumn = referencedColumn;
  }

  string column() const pure nothrow @nogc {
    return _column;
  }

  string referencedTable() const pure nothrow @nogc {
    return _referencedTable;
  }

  string referencedColumn() const pure nothrow @nogc {
    return _referencedColumn;
  }
}
