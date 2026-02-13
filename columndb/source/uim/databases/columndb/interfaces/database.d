module uim.databases.columndb.interfaces.database;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

interface ICdbDatabase {
  /// Database name
  string name() const;

  /// Create a new table
  ICdbTable createTable(string tableName) const;

  /// Get table
  ICdbTable getTable(string tableName) const;

  /// Drop table
  void dropTable(string tableName) const;

  /// Table exists
  bool hasTable(string tableName) const;

  /// Get all table names
  string[] tableNames() const;

  /// Get number of tables
  ulong tableCount() const;

  /// Get total memory usage
  ulong getTotalMemory() const;

  /// Get database statistics
  DatabaseStats getStats() const;
}
