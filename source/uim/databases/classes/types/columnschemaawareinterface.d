module uim.databases.types;

import uim.databases;

@safe:

interface IColumnSchemaAware {
    // Generate the SQL fragment for a single column in a table.
    string getColumnSql(TableISchema tableSchema, string columnName, Driver aDriver);

    // Convert a SQL column definition to an abstract type definition.
    IData[string] convertColumnDefinition(array columnDefinition, Driver aDriver);
}
