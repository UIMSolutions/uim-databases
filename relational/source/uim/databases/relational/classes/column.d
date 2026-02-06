/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes;    

import uim.databases.relational;
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