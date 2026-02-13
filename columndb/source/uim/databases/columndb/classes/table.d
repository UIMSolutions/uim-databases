/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.classes.table;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

/// Column-based table implementation
class CdbTable : ICdbTable {
  private {
    string _name;
    ICdbColumn[string] _columns;
    string[] _columnOrder;
  }

  this(string name) {
    _name = name;
    _columns = null;
    _columnOrder = [];
  }

  string name() const {
    return _name;
  }

  void addColumn(ICdbColumn column) {
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

  override ICdbColumn getColumn(string name) {
    if (name !in _columns) {
      throw new ColumnNotFoundException(name);
    }
    return _columns[name];
  }

  override string[] columnNames() const {
    return _columnOrder.dup;
  }

  ulong rowCount() const {
    if (_columns.length == 0) return 0;
    return _columns[_columnOrder[0]].rowCount();
  }

  ulong columnCount() const {
    return _columns.length;
  }

  void insertRow(Json[string] row) {
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
    ICdbColumn col = getColumn(columnName);
    ulong[] indices;
    
    for (ulong i = 0; i < col.rowCount(); i++) {
      if (col.get(i) == value) {
        indices ~= i;
      }
    }
    
    return indices;
  }

  override ColumnStats getColumnStats(string columnName) {
    auto col = cast(CdbColumn)getColumn(columnName);
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
///
unittest {
  auto table = new CdbTable("test");
  assert(table.name == "test");
  assert(table.rowCount == 0);
  assert(table.columnCount == 0);
  
  auto col1 = new CdbColumn("id", ColumnType.Int);
  col1.append(1);
  col1.append(2);
  col1.append(3);
  
  auto col2 = new CdbColumn("name", ColumnType.String);
  col2.append("Alice");
  col2.append("Bob");
  col2.append("Charlie");
  
  table.addColumn(col1);
  table.addColumn(col2);
  
  assert(table.rowCount == 3);
  assert(table.columnCount == 2);
  
  auto row = table.getRow(1);
  assert(row["id"] == 2);
  assert(row["name"] == "Bob");
  
  auto indices = table.query("name", "Charlie");
  assert(indices.length == 1 && indices[0] == 2);
  
  auto stats = table.getStats();
  assert(stats.tableName == "test");
  assert(stats.rowCount == 3);
  assert(stats.columnCount == 2);
  assert(stats.totalMemory > 0);    
}

