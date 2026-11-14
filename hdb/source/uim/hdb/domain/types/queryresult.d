module uim.hdb.domain.types.queryresult;

import uim.hdb;

mixin(ShowModule!());

@safe:

struct QueryResult {
    string[] columns;
    Value[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}