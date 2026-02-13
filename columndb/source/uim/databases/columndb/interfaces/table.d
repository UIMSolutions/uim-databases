module uim.databases.columndb.interfaces.table;

interface ICdbTable {
  /// Table name
  string name();
  
  /// Add a column
  void addColumn(ICdbColumn column);
  
  /// Get column by name
  ICdbColumn getColumn(string name);
  
  /// Check if column exists
  bool hasColumn(string name) const;
  
  /// Get all column names
  string[] columnNames() const;
  
  /// Get number of rows
  size_t rowCount() const;
  
  /// Query rows by column value
  ulong[] query(string columnName, Json value);
  
  /// Get column statistics
  ColumnStats getColumnStats(string columnName);

  size_t columnCount() const; 

  void insertRow(Json[string] row);

  Json[string] getRow(ulong index);

  Json[string][] getAllRows();

  ulong[] query(string columnName, Json value);

  /// Get table statistics
  TableStats getStats() const; 

  /// Scan all rows matching predicate
  ulong[] scan(bool function(Json[string]) predicate);
}