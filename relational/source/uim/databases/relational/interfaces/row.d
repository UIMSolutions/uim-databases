module uim.databases.relational.interfaces.row;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

interface IRDBRow {
  Json data(); 
  IRDBRow data(Json value);

  Json data(string key);
  IRDBRow data(string key, Json value);

  @property SysTime createdAt();
  @property SysTime updatedAt();

  IRDBRow update(Json newData);
}  
