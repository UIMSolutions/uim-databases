module uim.hdb.domain.types.queryresult;

import uim.hdb;

struct QueryResult {
    string[] columns;
    Value[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}