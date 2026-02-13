/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes.table;

import uim.databases.relational;

@safe:

/// Table class
class RDBTable : UIMObject, IRDBTable {
  this(string name, IRDBSchema schema) {
    this.name = name;
    this.schema = schema;
  }

  protected string _name;
  string name() {
    return _name;
  }
  IRDBTable name(string value) {
    _name = value;
    return this;
  }

  protected IRDBSchema _schema;
  IRDBSchema schema() {
    return _schema;
  }
  IRDBTable schema(IRDBSchema value) {
    _schema = value;
    return this;
  }

  protected IRDBRow[] _rows;  
  IRDBRow[] rows() {
    return _rows;
  }
  IRDBTable rows(IRDBRow[] value) {
    _rows = value;
    return this;
  }

  protected size_t[JsonKey] _primaryKeyIndex; // pk_value -> row_index
  size_t[JsonKey] primaryKeyIndex() {
    return _primaryKeyIndex;
  }
  IRDBTable primaryKeyIndex(size_t[JsonKey] value) {
    _primaryKeyIndex = value;
    return this;
  }

  /// Insert a row
  long insert(Json data) {
    // Apply defaults
    foreach (col; schema.columns) {
      if (!data.hasKey(col.name) && !col.defaultValue.isUndefined) {
        data[col.name] = col.defaultValue;
      }
    }

    // Validate
    schema.validateRow(data);

    // Check primary key uniqueness
    if (schema.primaryKeyColumn.length > 0) {
      auto pkValue = data[schema.primaryKeyColumn];
      if (pkValue in primaryKeyIndex) {
        throw new Exception("Primary key violation: duplicate value");
      }
    }

    // Check unique constraints
    foreach (col; schema.columns) {
      if (col.unique && col.name in data) {
        auto value = data[col.name];
        foreach (row; rows) {
          if (col.name in row.data && jsonEquals(row.data[col.name], value)) {
            throw new Exception("Unique constraint violation on column '" ~ col.name ~ "'");
          }
        }
      }
    }

    auto row = IRDBRow(data);
    size_t index = rows.length;
    rows ~= row;

    // Update index
    if (schema.primaryKeyColumn.length > 0 && schema.primaryKeyColumn in data) {
      primaryKeyIndex[data[schema.primaryKeyColumn]] = index;
    }

    return index;
  }

  /// Select rows with WHERE clause
  QueryResult select(string[] selectColumns, WhereCondition[] conditions,
    string orderBy = "", bool ascending = true,
    size_t limit = 0, size_t offset = 0) {
    Row[] filtered;

    // Filter rows
    foreach (row; rows) {
      bool match = true;
      foreach (cond; conditions) {
        if (!cond.matches(row.data)) {
          match = false;
          break;
        }
      }
      if (match) {
        filtered ~= row;
      }
    }

    // Sort
    if (orderBy.length > 0) {
      filtered.sort!((a, b) {
        if (orderBy !in a.data || orderBy !in b.data)
          return false;
        int cmp = compareJsonValues(a.data[orderBy], b.data[orderBy]);
        return ascending ? cmp < 0 : cmp > 0;
      });
    }

    // Apply offset and limit
    if (offset > 0 && offset < filtered.length) {
      filtered = filtered[offset .. $];
    } else if (offset >= filtered.length) {
      filtered = null;
    }

    if (limit > 0 && limit < filtered.length) {
      filtered = filtered[0 .. limit];
    }

    // Project columns
    Json[] results;
    foreach (row; filtered) {
      Json projectedRow = Json.emptyObject;

      if (selectColumns.length == 0 || selectColumns[0] == "*") {
        projectedRow = row.data.clone;
      } else {
        selectColumns.filter!(col => col in row.data).each!(col => projectedRow[col] = row.data[col]);
      }
      results ~= projectedRow;
    }

    return QueryResult(results, selectColumns, results.length);
  }

  /// Update rows matching conditions
  size_t update(Json updates, WhereCondition[] conditions) {
    size_t updated = 0;

    foreach (ref row; rows) {
      bool match = true;
      foreach (cond; conditions) {
        if (!cond.matches(row.data)) {
          match = false;
          break;
        }
      }

      if (match) {
        // Merge updates
        foreach (string key, value; updates) {
          row.data[key] = value;
        }
        row.updatedAt = Clock.currTime();
        updated++;
      }
    }

    return updated;
  }

  /// Delete rows matching conditions
  size_t deleteRows(WhereCondition[] conditions) {
    size_t deleted = 0;
    Row[] remaining;

    foreach (row; rows) {
      bool match = true;
      foreach (cond; conditions) {
        if (!cond.matches(row.data)) {
          match = false;
          break;
        }
      }

      if (match) {
        deleted++;
      } else {
        remaining ~= row;
      }
    }

    rows = remaining;
    rebuildPrimaryKeyIndex();

    return deleted;
  }

  /// Count rows matching conditions
  size_t count(WhereCondition[] conditions = []) {
    if (conditions.length == 0) {
      return rows.length;
    }

    size_t cnt = 0;
    foreach (row; rows) {
      bool match = true;
      foreach (cond; conditions) {
        if (!cond.matches(row.data)) {
          match = false;
          break;
        }
      }
      if (match)
        cnt++;
    }
    return cnt;
  }

  /// Get row by primary key
  Json getByPrimaryKey(Json pkValue) {
    return JsonKey(pkValue) !in primaryKeyIndex
      ? Json(null) 
      : rows[primaryKeyIndex[JsonKey(pkValue)]].data.clone;
  }

  private void rebuildPrimaryKeyIndex() {
    _primaryKeyIndex.clear();
    if (schema.primaryKeyColumn.length == 0)
      return;

    foreach (i, row; rows) {
      if (schema.primaryKeyColumn in row.data) {
        auto jk = JsonKey(row.data[schema.primaryKeyColumn]);
        _primaryKeyIndex[jk] = i;
      }
    }
  }

  private bool jsonEquals(Json a, Json b) {
    if (a.type != b.type)
      return false;

    final switch (a.type) {
    case Json.Type.undefined:
    case Json.Type.null_:
      return true;
    case Json.Type.bool_:
      return a.get!bool == b.get!bool;
    case Json.Type.int_:
      return a.get!long == b.get!long;
    case Json.Type.float_:
      return a.get!double == b.get!double;
    case Json.Type.string:
      return a.get!string == b.get!string;
    case Json.Type.array:
    case Json.Type.object:
      return a.toString() == b.toString();
    }
  }

  private int compareJsonValues(Json a, Json b) {
    if (a.isUndefined && b.isUndefined)
      return 0;
    if (a.isUndefined)
      return 1;
    if (b.isUndefined)
      return -1;

    if (a.isInteger && b.isInteger) {
      long av = a.get!long;
      long bv = b.get!long;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    if ((a.isDouble || a.isInteger) &&
      (b.isDouble || b.isInteger)) {
      double av = a.type == Json.Type.float_ ? a.get!double : a.get!long;
      double bv = b.type == Json.Type.float_ ? b.get!double : b.get!long;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }
    if (a.isString && b.isString) {
      string av = a.get!string;
      string bv = b.get!string;
      return av < bv ? -1 : (av > bv ? 1 : 0);
    }

    return a.toString() < b.toString() ? -1 : (a.toString() > b.toString() ? 1 : 0);
  }
}
