module uim.databases.relational.interfaces.schema;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

interface IRDBSchema {
  string tableName();
  IRDBSchema tableName(string name);

  IRDBColumn[] columns();
  IRDBSchema columns(IRDBColumn[] columns);

  string primaryKeyColumn();
  IRDBSchema primaryKeyColumn(string name);

  string[][string] foreignKeys();
  IRDBSchema foreignKeys(string[][string] value);

  string[][string] uniqueConstraints();
  IRDBSchema uniqueConstraints(string[][string] value);

  /// Add a column to the schema
  IRDBSchema addColumn(IRDBColumn column);
  IRDBSchema addForeignKey(string column, string refTable, string refColumn);

  IRDBColumn getColumn(string name);
  IRDBSchema validateRow(Json row);

  Json toJson();
}
