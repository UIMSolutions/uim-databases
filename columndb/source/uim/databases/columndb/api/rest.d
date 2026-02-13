/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.api.rest;

import uim.databases.columndb;
import vibe.d;

@safe:

/// Request/Response structs for REST API
struct CreateTableRequest {
  string tableName;
  CdbTableSchema[] columns;
}

struct CdbTableSchema {
  string name;
  string type;  // "INTEGER", "DOUBLE", "STRING", "BOOLEAN", "TIMESTAMP"
}

struct InsertRowRequest {
  string tableName;
  Json[string] row;
}

struct InsertRowsRequest {
  string tableName;
  Json[string][] rows;
}

struct GetRowResponse {
  bool success;
  string tableName;
  ulong index;
  Json[string] row;
  string error;
}

struct QueryRequest {
  string tableName;
  string columnName;
  Json value;
}

struct QueryResponse {
  bool success;
  string tableName;
  string columnName;
  ulong[] indices;
  size_t matchCount;
  string error;
}

struct TableInfoResponse {
  string tableName;
  string[] columnNames;
  ulong rowCount;
  ulong columnCount;
}

struct ColumnStatsResponse {
  string columnName;
  string type;
  ulong rowCount;
  ulong distinctValues;
  ulong nullCount;
  Json minValue;
  Json maxValue;
  Json avgValue;
}

struct DatabaseStatsResponse {
  string databaseName;
  ulong tableCount;
  string[] tableNames;
  ulong totalMemory;
}

/// REST API for Column Database
class CdbDatabaseAPI {
  private ICdbDatabase db;

  this(ICdbDatabase database) {
    this.db = database;
  }

  // POST /cdb/table - Create table
  @method(HTTPMethod.POST)
  @path("/cdb/table")
  Json createTable(CreateTableRequest req) {
    Json response = Json.emptyObject;
    try {
      auto table = db.createTable(req.tableName);
      
      foreach (colSchema; req.columns) {
        ColumnType colType = parseColumnType(colSchema.type);
        auto column = new Column(colSchema.name, colType);
        table.addColumn(column);
      }
      
      response["success"] = true;
      response["tableName"] = req.tableName;
      response["columnCount"] = req.columns.length;
      response["message"] = "Table created successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // GET /cdb/table/:name - Get table info
  @method(HTTPMethod.GET)
  @path("/cdb/table/:name")
  TableInfoResponse getTableInfo(string _name) {
    TableInfoResponse response;
    response.tableName = _name;
    
    try {
      auto table = db.getTable(_name);
      response.columnNames = table.columnNames();
      response.rowCount = table.rowCount();
      response.columnCount = table.columnCount();
    } catch (Exception e) {
      response.tableName = _name ~ " (ERROR: " ~ e.msg ~ ")";
    }
    
    return response;
  }

  // POST /cdb/row - Insert row
  @method(HTTPMethod.POST)
  @path("/cdb/row")
  Json insertRow(InsertRowRequest req) {
    Json response = Json.emptyObject;
    try {
      auto table = db.getTable(req.tableName);
      table.insertRow(req.row);
      
      response["success"] = true;
      response["tableName"] = req.tableName;
      response["message"] = "Row inserted successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // POST /cdb/rows - Insert multiple rows
  @method(HTTPMethod.POST)
  @path("/cdb/rows")
  Json insertRows(InsertRowsRequest req) {
    Json response = Json.emptyObject;
    try {
      auto table = db.getTable(req.tableName);
      
      foreach (row; req.rows) {
        table.insertRow(row);
      }
      
      response["success"] = true;
      response["tableName"] = req.tableName;
      response["rowsInserted"] = req.rows.length;
      response["message"] = "Rows inserted successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  // GET /cdb/row/:table/:index - Get row
  @method(HTTPMethod.GET)
  @path("/cdb/row/:table/:index")
  GetRowResponse getRow(string _table, string _index) {
    GetRowResponse response;
    response.tableName = _table;
    response.success = false;
    
    try {
      ulong index = _index.to!ulong;
      auto table = db.getTable(_table);
      response.index = index;
      response.row = table.getRow(index);
      response.success = true;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // POST /cdb/query - Query column
  @method(HTTPMethod.POST)
  @path("/cdb/query")
  QueryResponse query(QueryRequest req) {
    QueryResponse response;
    response.tableName = req.tableName;
    response.columnName = req.columnName;
    response.success = false;
    
    try {
      auto table = db.getTable(req.tableName);
      response.indices = table.query(req.columnName, req.value);
      response.matchCount = response.indices.length;
      response.success = true;
    } catch (Exception e) {
      response.error = e.msg;
    }
    
    return response;
  }

  // GET /cdb/column/:table/:name/stats - Get column statistics
  @method(HTTPMethod.GET)
  @path("/cdb/column/:table/:name/stats")
  ColumnStatsResponse getColumnStats(string _table, string _name) {
    ColumnStatsResponse response;
    response.columnName = _name;
    
    try {
      auto table = db.getTable(_table);
      auto stats = table.getColumnStats(_name);
      
      response.type = stats.type.to!string;
      response.rowCount = stats.rowCount;
      response.distinctValues = stats.distinctValues;
      response.nullCount = stats.nullCount;
      response.minValue = stats.minValue;
      response.maxValue = stats.maxValue;
      response.avgValue = stats.avgValue;
    } catch (Exception e) {
      response.columnName = _name ~ " (ERROR: " ~ e.msg ~ ")";
    }
    
    return response;
  }

  // GET /cdb/stats - Get database statistics
  @method(HTTPMethod.GET)
  @path("/cdb/stats")
  DatabaseStatsResponse getStats() {
    DatabaseStatsResponse response;
    
    auto stats = db.getStats();
    response.databaseName = stats.databaseName;
    response.tableCount = stats.tableCount;
    response.tableNames = db.tableNames();
    response.totalMemory = stats.totalMemory;
    
    return response;
  }

  // GET /cdb/tables - List all tables
  @method(HTTPMethod.GET)
  @path("/cdb/tables")
  Json listTables() {
    Json response = Json.emptyObject;
    response["tables"] = Json.emptyArray;
    
    foreach (name; db.tableNames()) {
      try {
        auto table = db.getTable(name);
        Json tableInfo = Json.emptyObject;
        tableInfo["name"] = name;
        tableInfo["rows"] = table.rowCount();
        tableInfo["columns"] = table.columnCount();
        response["tables"] ~= tableInfo;
      } catch (Exception) {}
    }
    
    response["count"] = response["tables"].length;
    return response;
  }

  // DELETE /cdb/table/:name - Drop table
  @method(HTTPMethod.DELETE)
  @path("/cdb/table/:name")
  Json dropTable(string _name) {
    Json response = Json.emptyObject;
    try {
      db.dropTable(_name);
      response["success"] = true;
      response["tableName"] = _name;
      response["message"] = "Table dropped successfully";
    } catch (Exception e) {
      response["success"] = false;
      response["error"] = e.msg;
    }
    return response;
  }

  private ColumnType parseColumnType(string typeName) {
    switch (typeName.toUpper()) {
      case "INTEGER":
        return ColumnType.INTEGER;
      case "DOUBLE":
        return ColumnType.DOUBLE;
      case "STRING":
        return ColumnType.STRING;
      case "BOOLEAN":
        return ColumnType.BOOLEAN;
      case "TIMESTAMP":
        return ColumnType.TIMESTAMP;
      default:
        throw new Exception("Unknown column type: " ~ typeName);
    }
  }
}
