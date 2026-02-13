module uim.databases.relational.interfaces.database;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

interface IRDBDatabase {
  string name();
  IRDBDatabase name(string value);

  IRDBTable[string] tables();
  IRDBDatabase tables(IRDBTable[string] value);

  IRDBTable table(string name);
  IRDBDatabase addTable(IRDBTable table);
}