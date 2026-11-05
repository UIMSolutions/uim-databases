module uim.hdb.domain.types.tablestats;

import uim.hdb.domain.types.tablestorage : TableStorage;
import uim.hdb.domain.value : ColumnType;

struct ColumnStats {
    string name;
    size_t rows, mainRows, deltaRows, mainDistinct, deltaDistinct;
    uint mainBits;
    size_t mainCodeBytes;
    ColumnType type;
}

struct TableStats {
    string table;
    size_t rows, deletedRows;
    ColumnStats[] columns;
    TableStorage storage;
}
