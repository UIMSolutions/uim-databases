/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.interfaces.column;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

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
