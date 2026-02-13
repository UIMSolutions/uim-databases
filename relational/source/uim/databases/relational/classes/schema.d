/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes.schema;

import uim.databases.relational;

@safe:

/// Table schema
class RDBSchema : UIMObject, IRDBSchema {
  this(string tableName) {
    this.tableName = tableName;
  }

  // #region tableName
  protected string _tableName;
  string tableName() {
    return _tableName;
  }

  IRDBSchema tableName(string value) {
    _tableName = value;
    return this;
  }
  // #endregion tableName

  // #region columns
  protected IRDBColumn[] _columns;
  IRDBSchema columns(IRDBColumn[] value) {
    _columns = value;
    return this;
  }

  IRDBColumn[] columns() {
    return _columns;
  }
  // #endregion columns

  // #region primaryKeyColumn
  protected string _primaryKeyColumn;
  string primaryKeyColumn() {
    return _primaryKeyColumn;
  }

  IRDBSchema primaryKeyColumn(string value) {
    _primaryKeyColumn = value;
    return this;
  }
  // #endregion primaryKeyColumn

  // #region foreignKeys
  protected string[][string] _foreignKeys;
  string[][string] foreignKeys() {
    return _foreignKeys;
  }

  IRDBSchema foreignKeys(string[][string] value) {
    _foreignKeys = value;
    return this;
  }
  // #endregion foreignKeys

  // #region uniqueConstraints
  protected string[][string] _uniqueConstraints;
  string[][string] uniqueConstraints() {
    return _uniqueConstraints;
  }

  IRDBSchema uniqueConstraints(string[][string] value) {
    _uniqueConstraints = value;
    return this;
  }
  // #endregion uniqueConstraints

  /// Add a column to the schema
  IRDBSchema addColumn(IRDBColumn column) {
    _columns ~= column;
    if (column.primaryKey) {
      _primaryKeyColumn = column.name;
    }
    return this;
  }

  /// Add a foreign key constraint
  IRDBSchema addForeignKey(string column, string refTable, string refColumn) {
    _foreignKeys[column] = [refTable, refColumn];
    return this;
  }

  /// Get column by name
  IRDBColumn getColumn(string name) {
    foreach (ref col; columns) {
      if (col.name == name)
        return col;
    }
    return null;
  }

  /// Validate a row against the schema
  IRDBSchema validateRow(Json row) {
    foreach (col; columns) {
      if (col.name !in row) {
        if (!col.nullable && col.defaultValue.type == Json.Type.undefined) {
          throw new Exception("Column '" ~ col.name ~ "' cannot be null");
        }
        continue;
      }

      auto value = row[col.name];
      if (value.type == Json.Type.null_ && !col.nullable) {
        throw new Exception("Column '" ~ col.name ~ "' cannot be null");
      }

      // Type validation
      if (value.type != Json.Type.null_) {
        validateType(value, col.type, col.name);
      }
    }
    return this;
  }

  private void validateType(Json value, ColumnType expectedType, string colName) {
    bool valid = false;

    final switch (expectedType) {
    case ColumnType.INTEGER:
      valid = value.type == Json.Type.int_;
      break;
    case ColumnType.FLOAT:
      valid = value.type == Json.Type.float_ || value.type == Json.Type.int_;
      break;
    case ColumnType.STRING:
      valid = value.type == Json.Type.string;
      break;
    case ColumnType.BOOLEAN:
      valid = value.type == Json.Type.bool_;
      break;
    case ColumnType.DATE:
      valid = value.type == Json.Type.string; // ISO date string
      break;
    case ColumnType.JSON:
      valid = true; // Any JSON type
      break;
    }

    if (!valid) {
      throw new Exception("Column '" ~ colName ~ "' type mismatch");
    }
  }

  /// Get schema as JSON
  override Json toJson() {
    auto schemaJson = super.toJson();
    schemaJson["tableName"] = tableName;
    schemaJson["primaryKey"] = primaryKeyColumn;

    Json colsJson = Json.emptyArray;
    foreach (col; columns) {
      auto colJson = Json.emptyObject;
      colJson["name"] = col.name;
      colJson["type"] = to!string(col.type);
      colJson["nullable"] = col.nullable;
      colJson["primaryKey"] = col.primaryKey;
      colJson["unique"] = col.unique;
      colsJson ~= colJson;
    }
    schemaJson["columns"] = colsJson;

    Json fkJson = Json.emptyObject;
    foreach (col, refs; foreignKeys) {
      fkJson[col] = [refs[0], refs[1]].toJson;
    }
    schemaJson["foreignKeys"] = fkJson;

    Json ucJson = Json.emptyObject;
    foreach (col, constraint; uniqueConstraints) {
      ucJson[col] = constraint.toJson;
    }
    schemaJson["uniqueConstraints"] = ucJson;

    return schemaJson;
  }
}
/// 
unittest {
  import std.stdio;
  import std.json;

  void testSchema() {
    auto schema = RDBSchema("users")
      .addColumn(RDBColumn("id", ColumnType.INTEGER, false).primaryKey(true))
      .addColumn(RDBColumn("name", ColumnType.STRING, false))
      .addColumn(RDBColumn("email", ColumnType.STRING, true).unique(true))
      .addForeignKey("id", "profiles", "user_id");

    assert(schema.tableName == "users");
    assert(schema.columns.length == 3);
    assert(schema.primaryKeyColumn == "id");
    assert(schema.foreignKeys["id"] == ["profiles", "user_id"]);
    assert(schema.getColumn("email").unique);
  }
}
