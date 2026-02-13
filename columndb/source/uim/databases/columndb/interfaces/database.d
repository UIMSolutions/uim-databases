module uim.databases.columndb.interfaces.database;

interfaces ICdbDatabase {
  /// Database name
  string name() const;
  
  /// Create a new table
  IColumnTable createTable(string tableName);
  
  /// Get table
  IColumnTable getTable(string tableName);
  
  /// Drop table
  void dropTable(string tableName);
  
  /// Table exists
  bool hasTable(string tableName) const;
  
  /// Get all table names
  string[] tableNames() const;

    /// Database name
  string name() const;

  /// Get number of tables
  ulong tableCount() const;
  
  /// Get total memory usage
  ulong getTotalMemory() const;
  
  /// Get database statistics
  DatabaseStats getStats() const;
}