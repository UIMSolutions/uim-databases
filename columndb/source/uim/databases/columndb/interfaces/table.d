module uim.databases.columndb.interfaces.table;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

interface ICdbTable {
  /// Table name
  string name() const;
  
  /// Add a column
  void addColumn(ICdbColumn column);
  
  /// Get column by name
  ICdbColumn getColumn(string name) const;
  
  /// Check if column exists
  bool hasColumn(string name) const;
  
  /// Get all column names
  string[] columnNames() const;
  
  /// Get number of rows
  size_t rowCount() const;
  
  /// Query rows by column value
  ulong[] query(string columnName, Json value) const;
  
  /// Get column statistics
  ColumnStats getColumnStats(string columnName) const;

  size_t columnCount() const; 

  void insertRow(Json[string] row);

  Json[string] getRow(ulong index);

  Json[string][] getAllRows();

  ulong[] query(string columnName, Json value) const;

  /// Get table statistics
  TableStats getStats() const; 

  /// Scan all rows matching predicate
  ulong[] scan(bool function(Json[string]) predicate) const;
}