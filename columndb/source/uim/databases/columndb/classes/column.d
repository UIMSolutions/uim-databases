/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.columndb.classes.column;

import uim.databases.columndb;

mixin(ShowModule!());

@safe:

/// Column implementation
class CdbColumn : ICdbColumn {
  private {
    string _name;
    ColumnType _type;
    Json[] _values;
  }

  this(string name, ColumnType type) {
    _name = name;
    _type = type;
    _values = [];
  }

  override string name() const {
    return _name;
  }

  override ColumnType type() const {
    return _type;
  }

  override ulong rowCount() const {
    return _values.length;
  }

  override void append(Json value) {
    if (!isValidType(value)) {
      throw new TypeMismatchException(typeToString(_type), getJsonType(value));
    }
    _values ~= value;
  }

  override Json get(ulong index) {
    if (index >= _values.length) {
      throw new IndexOutOfBoundsException(index, _values.length);
    }
    return _values[index];
  }

  override void set(ulong index, Json value) {
    if (index >= _values.length) {
      throw new IndexOutOfBoundsException(index, _values.length);
    }
    if (!isValidType(value)) {
      throw new TypeMismatchException(typeToString(_type), getJsonType(value));
    }
    _values[index] = value;
  }

  override Json[] getAll() const {
    return _values.dup;
  }

  override void compress() {
    // Placeholder for compression logic
    // In production, this would apply compression algorithms
  }

  override ulong memoryUsage() const {
    ulong usage = 0;
    foreach (val; _values) {
      usage += val.toString().length;
    }
    return usage;
  }

  /// Get column statistics
  ColumnStats getStats() const {
    ColumnStats stats;
    stats.rowCount = _values.length;
    stats.type = _type;
    stats.nullCount = countNulls();
    stats.distinctValues = countDistinct();
    
    if (_values.length > 0) {
      switch (_type) {
        case ColumnType.INTEGER:
          calculateIntegerStats(stats);
          break;
        case ColumnType.DOUBLE:
          calculateDoubleStats(stats);
          break;
        default:
          break;
      }
    }
    
    return stats;
  }

  private bool isValidType(Json value) const {
    if (value.type == Json.Type.null_) return true;
    
    final switch (_type) {
      case ColumnType.INTEGER:
        return value.type == Json.Type.integer;
      case ColumnType.DOUBLE:
        return value.type == Json.Type.float_;
      case ColumnType.STRING:
        return value.type == Json.Type.string;
      case ColumnType.BOOLEAN:
        return value.type == Json.Type.true_ || value.type == Json.Type.false_;
      case ColumnType.TIMESTAMP:
        return value.type == Json.Type.string;
    }
  }

  private string getJsonType(Json value) const {
    return value.type.to!string;
  }

  private string typeToString(ColumnType type) const {
    final switch (type) {
      case ColumnType.INTEGER: return "INTEGER";
      case ColumnType.DOUBLE: return "DOUBLE";
      case ColumnType.STRING: return "STRING";
      case ColumnType.BOOLEAN: return "BOOLEAN";
      case ColumnType.TIMESTAMP: return "TIMESTAMP";
    }
  }

  private ulong countNulls() const {
    return _values.count!(v => v.type == Json.Type.null_);
  }

  private ulong countDistinct() const {
    Json[] unique;
    foreach (val; _values) {
      if (val.type != Json.Type.null_ && !unique.canFind(val)) {
        unique ~= val;
      }
    }
    return unique.length;
  }

  private void calculateIntegerStats(ref ColumnStats stats) const {
    long min = long.max;
    long max = long.min;
    long sum = 0;
    ulong count = 0;

    foreach (val; _values) {
      if (val.type != Json.Type.null_) {
        long intVal = val.get!long;
        min = min < intVal ? min : intVal;
        max = max > intVal ? max : intVal;
        sum += intVal;
        count++;
      }
    }

    if (count > 0) {
      stats.minValue = Json(min);
      stats.maxValue = Json(max);
      stats.avgValue = Json(cast(double)sum / count);
    }
  }

  private void calculateDoubleStats(ref ColumnStats stats) const {
    double min = double.max;
    double max = double.min;
    double sum = 0;
    ulong count = 0;

    foreach (val; _values) {
      if (val.type != Json.Type.null_) {
        double dblVal = val.get!double;
        min = min < dblVal ? min : dblVal;
        max = max > dblVal ? max : dblVal;
        sum += dblVal;
        count++;
      }
    }

    if (count > 0) {
      stats.minValue = Json(min);
      stats.maxValue = Json(max);
      stats.avgValue = Json(sum / count);
    }
  }
}
///
unittest {
  import std.stdio;
  import std.random;
  
  void testColumn() {
    auto col = new CdbColumn("test", ColumnType.INTEGER);
    col.append(Json(10));
    col.append(Json(20));
    col.append(Json(30));
    
    assert(col.rowCount == 3);
    assert(col.get(0).get!long == 10);
    assert(col.get(1).get!long == 20);
    assert(col.get(2).get!long == 30);
    
    auto stats = col.getStats();
    assert(stats.rowCount == 3);
    assert(stats.type == ColumnType.INTEGER);
    assert(stats.minValue.get!long == 10);
    assert(stats.maxValue.get!long == 30);
    assert(stats.avgValue.get!double == 20.0);
    
    writeln("CdbColumn tests passed.");

    // Test type validation
    bool exceptionThrown = false;
    try {
      col.append(Json("invalid"));
    } catch (TypeMismatchException) {
      exceptionThrown = true;   
    }
    assert(exceptionThrown);

    // Test index out of bounds
    exceptionThrown = false;
    try {
      col.get(10);
    } catch (IndexOutOfBoundsException) {
      exceptionThrown = true;
    }
    assert(exceptionThrown);    

    exceptionThrown = false;
    try {      col.set(10, Json(100));
    } catch (IndexOutOfBoundsException) {
      exceptionThrown = true;       
    }
    assert(exceptionThrown);
  }
}