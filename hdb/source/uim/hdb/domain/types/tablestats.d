module uim.hdb.domain.types.tablestats;

import uim.hdb;
import uim.hdb.domain.types.columnstats;
import uim.hdb.domain.enumerations.tablestorage;

struct TableStats {
    string table;
    size_t rows, deletedRows;
    ColumnStats[] columns;
    TableStorage storage;

    Json toJson() const {
        return Json.emptyObject
            .set("table", table)
            .set("rows", rows)
            .set("deletedRows", deletedRows)
            .set("columns", columns.map!(c => c.toJson).array.toJson)
            .set("storage", storage.to!string);
    }
}
