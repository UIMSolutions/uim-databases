/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.classes.database;

import uim.databases.columndb;

@safe:

/// Column database
class ColumnDatabase {
  private {
    string _name;
    IColumnTable[string] _tables;
  }

  this(string name = "columndb") {
    _name = name;
  }

  /// Database name
  string name() const {
    return _name;
  }

  /// Create a new table
  IColumnTable createTable(string tableName) {
    if (tableName in _tables) {
      throw new TableException("Table already exists: " ~ tableName);
    }
    
    auto table = new ColumnTable(tableName);
    _tables[tableName] = table;
    return table;
  }

  /// Get table
  IColumnTable getTable(string tableName) {
    if (tableName !in _tables) {
      throw new TableException("Table not found: " ~ tableName);
    }
    return _tables[tableName];
  }

  /// Drop table
  void dropTable(string tableName) {
    if (tableName !in _tables) {
      throw new TableException("Table not found: " ~ tableName);
    }
    _tables.remove(tableName);
  }

  /// Table exists
  bool hasTable(string tableName) const {
    return (tableName in _tables) !is null;
  }

  /// Get all table names
  string[] tableNames() const {
    return _tables.keys;
  }

  /// Get number of tables
  ulong tableCount() const {
    return _tables.length;
  }

  /// Get total memory usage
  ulong getTotalMemory() const {
    ulong total = 0;
    foreach (table; _tables) {
      auto ctable = cast(ColumnTable)table;
      if (ctable !is null) {
        total += ctable.getStats().totalMemory;
      }
    }
    return total;
  }

  /// Get database statistics
  DatabaseStats getStats() const {
    DatabaseStats stats;
    stats.databaseName = _name;
    stats.tableCount = tableCount();
    stats.totalMemory = getTotalMemory();
    
    foreach (name, table; _tables) {
      auto ctable = cast(ColumnTable)table;
      if (ctable !is null) {
        TableStatsInfo info;
        info.tableName = name;
        info.rowCount = table.rowCount();
        info.columnCount = table.columnCount();
        stats.tables ~= info;
      }
    }
    
    return stats;
  }
}

/// Database statistics
struct DatabaseStats {
  string databaseName;
  ulong tableCount;
  ulong totalMemory;
  TableStatsInfo[] tables;
}

/// Table info for stats
struct TableStatsInfo {
  string tableName;
  ulong rowCount;
  ulong columnCount;
}
