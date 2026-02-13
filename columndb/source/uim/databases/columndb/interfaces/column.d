/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.interfaces.column;

@safe:

/// Column data types
enum ColumnType {
  INTEGER,    // 64-bit signed integer
  DOUBLE,     // 64-bit floating point
  STRING,     // UTF-8 string
  BOOLEAN,    // Boolean value
  TIMESTAMP   // System time
}

/// Column interface - represents a single column of data
interface ICdbColumn {
  /// Column name
  string name();
  
  /// Column type
  ColumnType type();
  
  /// Get number of rows
  ulong rowCount();
  
  /// Append a value
  void append(Json value);
  
  /// Get value at index
  Json get(ulong index);
  
  /// Set value at index
  void set(ulong index, Json value);
  
  /// Get all values
  Json[] getAll();
  
  /// Compress column data
  void compress();
  
  /// Get memory usage in bytes
  ulong memoryUsage();
}

/// Table interface - collection of columns
interface IColumnTable {
  /// Table name
  string name();
  
  /// Add a column
  void addColumn(IColumn column);
  
  /// Get column by name
  IColumn getColumn(string name);
  
  /// Get all column names
  string[] columnNames();
  
  /// Get number of rows
  ulong rowCount();
  
  /// Get number of columns
  ulong columnCount();
  
  /// Insert a row
  void insertRow(Json[string] row);
  
  /// Get row as JSON object
  Json[string] getRow(ulong index);
  
  /// Get all rows
  Json[string][] getAllRows();
  
  /// Query by column values
  ulong[] query(string columnName, Json value);
  
  /// Get column statistics
  ColumnStats getColumnStats(string columnName);
}

/// Column statistics
struct ColumnStats {
  ulong rowCount;
  ColumnType type;
  Json minValue;
  Json maxValue;
  Json avgValue;
  ulong distinctValues;
  ulong nullCount;
  double compression;
}
