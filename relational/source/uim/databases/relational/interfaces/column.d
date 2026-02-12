module uim.databases.relational.interfaces.column;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

interface IRDBColumn {
    string name();
    IRDBColumn name(string value);

    ColumnType type();
    IRDBColumn type(ColumnType value);

    bool nullable();
    IRDBColumn nullable(bool value);

    bool primaryKey();
    IRDBColumn primaryKey(bool value);

    bool unique();
    IRDBColumn unique(bool value);

    Json defaultValue();
    IRDBColumn defaultValue(Json value);
}
