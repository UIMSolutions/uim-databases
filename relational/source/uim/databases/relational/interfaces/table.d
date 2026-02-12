module uim.databases.relational.interfaces.table;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

interface IRDBTable {
  string name();
  IRDBTable name(string value);

  IRDBSchema schema();
  IRDBTable schema(IRDBSchema value);

  IRDBRow[] rows();
  IRDBTable rows(IRDBRow[] value);

  long[Json] primaryKeyIndex();
  IRDBTable primaryKeyIndex(long[Json] value);

  long insert(Json data);

  QueryResult select(string[] selectColumns, WhereCondition[] conditions,
    string orderBy = "", bool ascending = true,
    size_t limit = 0, size_t offset = 0);

  size_t update(Json updates, WhereCondition[] conditions);

  size_t deleteRows(WhereCondition[] conditions);

  size_t count(WhereCondition[] conditions = []);

  Json getByPrimaryKey(Json pkValue);
}
