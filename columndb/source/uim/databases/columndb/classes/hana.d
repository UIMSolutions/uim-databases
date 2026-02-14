module uim.databases.columndb.classes.hana;

import uim.databases.columndb;
import std.algorithm : canFind, map;
import std.array : array;
import std.conv : to;
import std.digest.sha : sha256Of;
import std.digest : toHexString;
import std.exception : enforce;
import std.math : sqrt;
import std.process : execute;
import std.string : split, strip, toLower;

/// HANA-like schema definition
struct HanaTableColumnDef {
  string name;
  ColumnType type;
  bool nullable = true;
  bool indexed = false;
}

/// Simple trained linear model for PAL-like usage
struct HanaLinearModel {
  string id;
  double slope;
  double intercept;
  string featureColumn;
  string targetColumn;
}

/// Data virtualization source adapter
interface IVirtualSourceAdapter {
  string sourceName() const;
  Json[] fetchRows(Json query);
}

/// In-memory adapter for virtualized inline datasets
class InlineVirtualSourceAdapter : IVirtualSourceAdapter {
  private {
    string _name;
    Json[] _rows;
  }

  this(string name, Json[] rows) {
    _name = name;
    _rows = rows.dup;
  }

  override string sourceName() const {
    return _name;
  }

  override Json[] fetchRows(Json query) {
    if (query.type != Json.Type.object_ || !query["field"].defined || !query["value"].defined) {
      return _rows.dup;
    }

    auto field = query["field"].get!string;
    auto expected = query["value"];

    Json[] filtered;
    foreach (row; _rows) {
      if (row.type == Json.Type.object_ && row[field].defined && row[field] == expected) {
        filtered ~= row;
      }
    }

    return filtered;
  }
}

/// SAP HANA-like in-memory HTAP engine over ColumnDB primitives
class HanaLikeDatabase {
  private {
    string _name;
    CdbDatabase _store;
    IVirtualSourceAdapter[string] _virtualSources;
    HanaLinearModel[string] _models;
    Json[] _txLog;
    ulong _txCounter;
    string _apiTokenHash;
  }

  this(string name = "hana-like") {
    _name = name;
    _store = new CdbDatabase(name);
    _txLog = [];
  }

  string name() const {
    return _name;
  }

  CdbDatabase rawDatabase() {
    return _store;
  }

  void setApiToken(string token) {
    enforce(token.length > 0, "API token must not be empty");
    _apiTokenHash = sha256Of(token).toHexString();
  }

  bool isSecurityEnabled() const {
    return _apiTokenHash.length > 0;
  }

  bool authorize(string token) const {
    if (_apiTokenHash.length == 0) return true;
    return sha256Of(token).toHexString() == _apiTokenHash;
  }

  ICdbTable createTable(string tableName, HanaTableColumnDef[] columns) {
    enforce(columns.length > 0, "Table requires at least one column");

    auto table = _store.createTable(tableName);
    foreach (col; columns) {
      table.addColumn(new CdbColumn(col.name, col.type));
    }

    Json cols = Json.emptyArray;
    foreach (col; columns) {
      Json item = Json.emptyObject;
      item["name"] = col.name;
      item["type"] = cast(int) col.type;
      cols ~= item;
    }

    appendTxLog("create_table", [
      "table": Json(tableName),
      "columns": cols
    ]);

    return table;
  }

  void insertRow(string tableName, Json[string] row) {
    auto table = _store.getTable(tableName);
    table.insertRow(row);

    Json rowObject = Json.emptyObject;
    foreach (key, value; row) {
      rowObject[key] = value;
    }

    appendTxLog("insert_row", [
      "table": Json(tableName),
      "row": rowObject
    ]);
  }

  Json[string][] queryEquals(string tableName, string columnName, Json value) {
    auto table = _store.getTable(tableName);
    auto matches = table.query(columnName, value);

    Json[string][] rows;
    foreach (index; matches) {
      rows ~= table.getRow(index);
    }
    return rows;
  }

  Json aggregateRealtime(string tableName, string measureColumn, string op, string groupByColumn = "") {
    auto table = _store.getTable(tableName);
    auto rows = table.getAllRows();

    string normalized = op.toLower();

    if (groupByColumn.length == 0) {
      return aggregateRows(rows, measureColumn, normalized);
    }

    Json grouped = Json.emptyObject;
    Json[string][][string] buckets;

    foreach (row; rows) {
      auto key = row[groupByColumn].toString();
      buckets[key] ~= row;
    }

    foreach (key, bucketRows; buckets) {
      grouped[key] = aggregateRows(bucketRows, measureColumn, normalized);
    }

    return grouped;
  }

  Json[] textSearch(string tableName, string columnName, string term) {
    auto table = _store.getTable(tableName);
    auto rows = table.getAllRows();
    auto wanted = tokenize(term);

    Json[] result;
    foreach (row; rows) {
      if (!(columnName in row)) continue;
      auto tokens = tokenize(row[columnName].type == Json.Type.string ? row[columnName].get!string : row[columnName].toString());

      bool allPresent = true;
      foreach (word; wanted) {
        if (!tokens.canFind(word)) {
          allPresent = false;
          break;
        }
      }

      if (allPresent) {
        Json obj = Json.emptyObject;
        foreach (k, v; row) obj[k] = v;
        result ~= obj;
      }
    }

    return result;
  }

  string[] graphNeighbors(string edgeTable, string nodeId, string direction = "out") {
    auto table = _store.getTable(edgeTable);
    auto rows = table.getAllRows();

    string[] neighbors;
    foreach (row; rows) {
      if (!("source" in row) || !("target" in row)) continue;

      auto src = row["source"].toString().strip("\"");
      auto dst = row["target"].toString().strip("\"");

      if (direction == "out" && src == nodeId) {
        neighbors ~= dst;
      } else if (direction == "in" && dst == nodeId) {
        neighbors ~= src;
      } else if (direction == "both" && src == nodeId) {
        neighbors ~= dst;
      } else if (direction == "both" && dst == nodeId) {
        neighbors ~= src;
      }
    }

    return neighbors;
  }

  void registerVirtualSource(IVirtualSourceAdapter adapter) {
    _virtualSources[adapter.sourceName()] = adapter;
  }

  Json[] queryVirtualSource(string sourceName, Json query) {
    enforce(sourceName in _virtualSources, "Virtual source not found: " ~ sourceName);
    return _virtualSources[sourceName].fetchRows(query);
  }

  HanaLinearModel trainLinearRegression(string tableName, string featureColumn, string targetColumn) {
    auto table = _store.getTable(tableName);
    auto rows = table.getAllRows();

    double sumX, sumY, sumXY, sumXX;
    double count;

    foreach (row; rows) {
      if (!(featureColumn in row) || !(targetColumn in row)) continue;

      auto x = toDouble(row[featureColumn]);
      auto y = toDouble(row[targetColumn]);

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
      count += 1.0;
    }

    enforce(count >= 2.0, "Not enough numeric points for training");

    auto denominator = (count * sumXX) - (sumX * sumX);
    enforce(denominator != 0.0, "Degenerate training set");

    auto slope = ((count * sumXY) - (sumX * sumY)) / denominator;
    auto intercept = (sumY - slope * sumX) / count;

    auto modelId = "linreg-" ~ (++_txCounter).to!string;

    HanaLinearModel model;
    model.id = modelId;
    model.slope = slope;
    model.intercept = intercept;
    model.featureColumn = featureColumn;
    model.targetColumn = targetColumn;

    _models[modelId] = model;

    appendTxLog("train_model", [
      "modelId": Json(modelId),
      "slope": Json(slope),
      "intercept": Json(intercept),
      "featureColumn": Json(featureColumn),
      "targetColumn": Json(targetColumn)
    ]);

    return model;
  }

  double predict(string modelId, double featureValue) {
    enforce(modelId in _models, "Model not found: " ~ modelId);
    auto model = _models[modelId];
    return model.slope * featureValue + model.intercept;
  }

  Json runPythonModel(string scriptPath, Json payload) {
    return runExternalModel("python3", scriptPath, payload);
  }

  Json runRModel(string scriptPath, Json payload) {
    return runExternalModel("Rscript", scriptPath, payload);
  }

  Json snapshot() const {
    Json log = Json.emptyArray;
    foreach (item; _txLog) log ~= item;

    return [
      "database": Json(_name),
      "txCounter": Json(_txCounter),
      "txLog": log,
      "tableCount": Json(_store.tableCount())
    ];
  }

  void restoreFromSnapshot(Json snapshotJson) {
    enforce(snapshotJson.type == Json.Type.object_, "Invalid snapshot format");
    enforce(snapshotJson["txLog"].defined && snapshotJson["txLog"].type == Json.Type.array, "Snapshot missing txLog");

    auto existing = _store.tableNames();
    foreach (tableName; existing) {
      _store.dropTable(tableName);
    }

    _txLog = [];
    _models = null;
    _txCounter = 0;

    foreach (event; snapshotJson["txLog"]) {
      replayEvent(event);
      _txLog ~= event;
    }

    if (snapshotJson["txCounter"].defined) {
      _txCounter = snapshotJson["txCounter"].get!ulong;
    }
  }

  Json health() const {
    return [
      "name": Json(_name),
      "mode": Json("in-memory HTAP"),
      "tables": Json(_store.tableCount()),
      "virtualSources": Json(_virtualSources.length),
      "models": Json(_models.length),
      "securityEnabled": Json(isSecurityEnabled())
    ];
  }

  private void appendTxLog(string eventType, Json[string] payload) {
    Json item = Json.emptyObject;
    item["txId"] = ++_txCounter;
    item["event"] = eventType;

    Json p = Json.emptyObject;
    foreach (k, v; payload) p[k] = v;
    item["payload"] = p;

    _txLog ~= item;
  }

  private void replayEvent(Json eventItem) {
    auto eventType = eventItem["event"].get!string;
    auto payload = eventItem["payload"];

    if (eventType == "create_table") {
      HanaTableColumnDef[] defs;
      foreach (col; payload["columns"]) {
        HanaTableColumnDef def;
        def.name = col["name"].get!string;
        def.type = cast(ColumnType) col["type"].get!int;
        defs ~= def;
      }
      auto table = _store.createTable(payload["table"].get!string);
      foreach (def; defs) {
        table.addColumn(new CdbColumn(def.name, def.type));
      }
      return;
    }

    if (eventType == "insert_row") {
      Json[string] row;
      foreach (key, value; payload["row"]) {
        row[key] = value;
      }
      _store.getTable(payload["table"].get!string).insertRow(row);
      return;
    }

    if (eventType == "train_model") {
      HanaLinearModel model;
      model.id = payload["modelId"].get!string;
      model.slope = payload["slope"].get!double;
      model.intercept = payload["intercept"].get!double;
      model.featureColumn = payload["featureColumn"].get!string;
      model.targetColumn = payload["targetColumn"].get!string;
      _models[model.id] = model;
    }
  }

  private Json aggregateRows(Json[string][] rows, string measureColumn, string op) {
    if (op == "count") {
      return Json(rows.length);
    }

    double[] values;
    foreach (row; rows) {
      if (!(measureColumn in row)) continue;
      values ~= toDouble(row[measureColumn]);
    }

    enforce(values.length > 0, "No numeric values for aggregate operation");

    if (op == "sum") {
      double sum = 0;
      foreach (v; values) sum += v;
      return Json(sum);
    }

    if (op == "avg") {
      double sum = 0;
      foreach (v; values) sum += v;
      return Json(sum / values.length);
    }

    if (op == "min") {
      double minVal = values[0];
      foreach (v; values[1 .. $]) {
        if (v < minVal) minVal = v;
      }
      return Json(minVal);
    }

    if (op == "max") {
      double maxVal = values[0];
      foreach (v; values[1 .. $]) {
        if (v > maxVal) maxVal = v;
      }
      return Json(maxVal);
    }

    if (op == "stddev") {
      double sum = 0;
      foreach (v; values) sum += v;
      auto mean = sum / values.length;
      double variance = 0;
      foreach (v; values) variance += (v - mean) * (v - mean);
      variance /= values.length;
      return Json(sqrt(variance));
    }

    throw new Exception("Unsupported aggregate op: " ~ op);
  }

  private string[] tokenize(string text) {
    string[] tokens;
    foreach (token; text.toLower().split(" ")) {
      auto cleaned = token.strip(" .,;:!?\"'()[]{}\t\n\r");
      if (cleaned.length > 0) tokens ~= cleaned;
    }
    return tokens;
  }

  private double toDouble(Json value) {
    final switch (value.type) {
      case Json.Type.integer:
        return cast(double) value.get!long;
      case Json.Type.uinteger:
        return cast(double) value.get!ulong;
      case Json.Type.float_:
        return value.get!double;
      case Json.Type.string:
        return value.get!string.to!double;
      default:
        throw new Exception("Value is not numeric: " ~ value.toString());
    }
  }

  private Json runExternalModel(string runtime, string scriptPath, Json payload) {
    auto result = execute([runtime, scriptPath, payload.toString()]);

    Json response = Json.emptyObject;
    response["exitCode"] = result.status;
    response["stdout"] = result.output;
    response["stderr"] = result.stderrOutput;

    return response;
  }
}
