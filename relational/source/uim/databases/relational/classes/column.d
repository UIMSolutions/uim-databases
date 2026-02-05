module uim.databases.object.classes;

import uim.databases.object;
@safe:

/// Column definition
struct Column {
    string name;
    ColumnType type;
    bool nullable = true;
    bool primaryKey = false;
    bool unique = false;
    Json defaultValue;
    
    this(string name, ColumnType type, bool nullable = true) {
        this.name = name;
        this.type = type;
        this.nullable = nullable;
    }
}