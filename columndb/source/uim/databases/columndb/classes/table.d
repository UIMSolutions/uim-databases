/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.classes.table;

import uim.databases.columndb;
import std.algorithm;

@safe:

/// Column-based table implementation
class ColumnTable : IColumnTable {
  private {
    string _name;
    IColumn[string] _columns;
    string[] _columnOrder;
  }

  this(string name) {
    _name = name;
    _columns = null;
    _columnOrder = [];
  }

  override string name() const {
    return _name;
  }

  override void addColumn(IColumn column) {
    if (column.name() in _columns) {
      throw new DuplicateColumnException(column.name());
    }
    
    // All columns must have same row count
    if (_columns.length > 0 && column.rowCount() != rowCount()) {
      throw new ColumnException("New column has different row count");
    }
    
    _columns[column.name()] = column;
    _columnOrder ~= column.name();
  }

  override IColumn getColumn(string name) {
    if (name !in _columns) {
      throw new ColumnNotFoundException(name);
    }
    return _columns[name];
  }

  override string[] columnNames() const {
    return _columnOrder.dup;
  }

  override ulong rowCount() const {
    if (_columns.length == 0) return 0;
    return _columns[_columnOrder[0]].rowCount();
  }

  override ulong columnCount() const {
    return _columns.length;
  }

  override void insertRow(Json[string] row) {
    foreach (colName; _columnOrder) {
      if (colName in row) {
        _columns[colName].append(row[colName]);
      } else {
        _columns[colName].append(Json(null));
      }
    }
  }

  override Json[string] getRow(ulong index) {
    Json[string] result;
    foreach (colName; _columnOrder) {
      result[colName] = _columns[colName].get(index);
    }
    return result;
  }

  override Json[string][] getAllRows() {
    Json[string][] result;
    ulong numRows = rowCount();
    for (ulong i = 0; i < numRows; i++) {
      result ~= getRow(i);
    }
    return result;
  }

  override ulong[] query(string columnName, Json value) {
    IColumn col = getColumn(columnName);
    ulong[] indices;
    
    for (ulong i = 0; i < col.rowCount(); i++) {
      if (col.get(i) == value) {
        indices ~= i;
      }
    }
    
    return indices;
  }

  override ColumnStats getColumnStats(string columnName) {
    auto col = cast(Column)getColumn(columnName);
    if (col is null) {
      throw new ColumnException("Column does not support statistics");
    }
    return col.getStats();
  }

  /// Get table statistics
  TableStats getStats() const {
    TableStats stats;
    stats.tableName = _name;
    stats.columnCount = columnCount();
    stats.rowCount = rowCount();
    
    foreach (colName; _columnOrder) {
      stats.totalMemory += _columns[colName].memoryUsage();
    }
    
    return stats;
  }

  /// Scan all rows matching predicate
  ulong[] scan(bool function(Json[string]) predicate) {
    ulong[] result;
    ulong numRows = rowCount();
    
    for (ulong i = 0; i < numRows; i++) {
      if (predicate(getRow(i))) {
        result ~= i;
      }
    }
    
    return result;
  }
}

/// Table statistics
struct TableStats {
  string tableName;
  ulong columnCount;
  ulong rowCount;
  ulong totalMemory;
}
