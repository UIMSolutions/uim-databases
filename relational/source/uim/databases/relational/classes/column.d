/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.relational.classes.column;

import uim.databases.relational;

@safe:

/// Column definition
class RDBColumn : UIMObject, IRDBColumn {
  this(string name, ColumnType type, bool nullable = true) {
    this._name = name;
    this._type = type;
    this._nullable = nullable;
  }

  static RDBColumn opCall(string name, ColumnType type, bool nullable = true) {
    return new RDBColumn(name, type, nullable);
  }

  protected Json _defaultValue;

  // #region name
  // Getter and setter for name
  private string _name;
  @property string name() {
    return _name;
  }

  @property void name(string value) {
    _name = value;
  }
  // #endregion name

  // #region type
  protected ColumnType _type;
  // Getter and setter for type
  @property ColumnType type() {
    return _type;
  }

  @property void type(ColumnType value) {
    _type = value;
  }
  // #endregion type

  // #region nullable
  protected bool _nullable = true;
  // Getter and setter for nullable
  @property bool nullable() {
    return _nullable;
  }

  @property IRDBColumn nullable(bool value) {
    _nullable = value;
    return this;
  }
  // #endregion nullable

  // #region primaryKey
  protected bool _primaryKey = false;
  // Getter and setter for primaryKey
  @property bool primaryKey() {
    return _primaryKey;
  }

  @property IRDBColumn primaryKey(bool value) {
    _primaryKey = value;
    return this;
  }
  // #endregion primaryKey

  // #region unique
  protected bool _unique = false;
  // Getter and setter for unique
  @property bool unique() {
    return _unique;
  }

  @property IRDBColumn unique(bool value) {
    _unique = value;
    return this;
  }
  // #endregion unique

  // #region defaultValue
  // Getter and setter for defaultValue
  @property Json defaultValue() {
    return _defaultValue;
  }

  @property IRDBColumn defaultValue(Json value) {
    _defaultValue = value;
    return this;  
  }
  // #endregion defaultValue
}
///
unittest {
  import std.stdio;
  import std.json;
  
  void testColumn() {
    auto col = RDBColumn("id", ColumnType.INTEGER, false);
    assert(col.name == "id");
    assert(col.type == ColumnType.INTEGER);
    assert(col.nullable == false);
    assert(col.primaryKey == false);
    assert(col.unique == false);
    
    col.primaryKey = true;
    col.unique = true;
    
    assert(col.primaryKey == true);
    assert(col.unique == true);
  }
}
