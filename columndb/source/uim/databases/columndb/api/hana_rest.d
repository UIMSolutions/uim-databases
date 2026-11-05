module uim.databases.columndb.api.hana_rest;

import uim.databases.columndb;
import vibe.d;

/// HANA-like table create request
struct HanaCreateTableRequest {
  string token;
  string tableName;
  HanaColumnSchema[] columns;
}

struct HanaColumnSchema {
  string name;
  string type;
  bool nullable = true;
  bool indexed = false;
}

struct HanaInsertRowRequest {
  string token;
  string tableName;
  Json[string] row;
}

struct HanaAggregateRequest {
  string token;
  string tableName;
  string measureColumn;
  string op;
  string groupByColumn;
}

struct HanaTextSearchRequest {
  string token;
  string tableName;
  string columnName;
  string term;
}

struct HanaGraphNeighborsRequest {
  string token;
  string edgeTable;
  string nodeId;
  string direction = "out";
}

struct HanaTrainModelRequest {
  string token;
  string tableName;
  string featureColumn;
  string targetColumn;
}

struct HanaPredictRequest {
  string token;
  string modelId;
  double featureValue;
}

struct HanaRuntimeModelRequest {
  string token;
  string scriptPath;
  Json payload;
}

struct HanaVirtualRegisterRequest {
  string token;
  string sourceName;
  Json[] rows;
}

struct HanaVirtualQueryRequest {
  string token;
  string sourceName;
  Json query;
}

struct HanaRestoreRequest {
  string token;
  Json snapshot;
}

struct HanaTokenRequest {
  string token;
}

/// REST API for HANA-like capabilities
class HanaLikeDatabaseAPI {
  private HanaLikeDatabase db;

  this(HanaLikeDatabase db) {
    this.db = db;
  }

  @method(HTTPMethod.GET)
  @path("/hana/health")
  Json health() {
    return db.health();
  }

  @method(HTTPMethod.POST)
  @path("/hana/security/token")
  Json setToken(HanaTokenRequest req) {
    db.setApiToken(req.token);
    return [
      "success": Json(true),
      "message": Json("API token configured")
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/table")
  Json createTable(HanaCreateTableRequest req) {
    requireAuth(req.token);

    HanaTableColumnDef[] defs;
    foreach (c; req.columns) {
      defs ~= HanaTableColumnDef(c.name, parseColumnType(c.type), c.nullable, c.indexed);
    }

    db.createTable(req.tableName, defs);

    return [
      "success": Json(true),
      "table": Json(req.tableName),
      "columns": Json(req.columns.length)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/row")
  Json insertRow(HanaInsertRowRequest req) {
    requireAuth(req.token);
    db.insertRow(req.tableName, req.row);

    return [
      "success": Json(true),
      "table": Json(req.tableName)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/query")
  Json queryEquals(Json request) {
    auto token = request["token"].defined ? request["token"].get!string : "";
    requireAuth(token);

    auto tableName = request["tableName"].get!string;
    auto columnName = request["columnName"].get!string;
    auto value = request["value"];

    auto rows = db.queryEquals(tableName, columnName, value);

    Json result = Json.emptyArray;
    foreach (row; rows) {
      Json item = Json.emptyObject;
      foreach (k, v; row) item[k] = v;
      result ~= item;
    }

    return [
      "success": Json(true),
      "rows": result,
      "count": Json(rows.length)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/analytics/aggregate")
  Json aggregate(HanaAggregateRequest req) {
    requireAuth(req.token);

    return [
      "success": Json(true),
      "result": db.aggregateRealtime(req.tableName, req.measureColumn, req.op, req.groupByColumn)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/text/search")
  Json textSearch(HanaTextSearchRequest req) {
    requireAuth(req.token);
    auto rows = db.textSearch(req.tableName, req.columnName, req.term);

    Json responseRows = Json.emptyArray;
    foreach (row; rows) responseRows ~= row;

    return [
      "success": Json(true),
      "count": Json(rows.length),
      "rows": responseRows
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/graph/neighbors")
  Json graphNeighbors(HanaGraphNeighborsRequest req) {
    requireAuth(req.token);
    auto neighbors = db.graphNeighbors(req.edgeTable, req.nodeId, req.direction);

    Json list = Json.emptyArray;
    foreach (n; neighbors) list ~= n;

    return [
      "success": Json(true),
      "neighbors": list,
      "count": Json(neighbors.length)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/ml/linear/train")
  Json trainLinear(HanaTrainModelRequest req) {
    requireAuth(req.token);
    auto model = db.trainLinearRegression(req.tableName, req.featureColumn, req.targetColumn);

    return [
      "success": Json(true),
      "modelId": Json(model.id),
      "slope": Json(model.slope),
      "intercept": Json(model.intercept)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/ml/linear/predict")
  Json predict(HanaPredictRequest req) {
    requireAuth(req.token);

    return [
      "success": Json(true),
      "prediction": Json(db.predict(req.modelId, req.featureValue))
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/integration/python")
  Json runPython(HanaRuntimeModelRequest req) {
    requireAuth(req.token);

    return [
      "success": Json(true),
      "result": db.runPythonModel(req.scriptPath, req.payload)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/integration/r")
  Json runR(HanaRuntimeModelRequest req) {
    requireAuth(req.token);

    return [
      "success": Json(true),
      "result": db.runRModel(req.scriptPath, req.payload)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/virtual/register")
  Json registerVirtual(HanaVirtualRegisterRequest req) {
    requireAuth(req.token);

    db.registerVirtualSource(new InlineVirtualSourceAdapter(req.sourceName, req.rows));

    return [
      "success": Json(true),
      "source": Json(req.sourceName),
      "rows": Json(req.rows.length)
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/virtual/query")
  Json queryVirtual(HanaVirtualQueryRequest req) {
    requireAuth(req.token);

    auto rows = db.queryVirtualSource(req.sourceName, req.query);
    Json responseRows = Json.emptyArray;
    foreach (r; rows) responseRows ~= r;

    return [
      "success": Json(true),
      "rows": responseRows,
      "count": Json(rows.length)
    ];
  }

  @method(HTTPMethod.GET)
  @path("/hana/ha/snapshot")
  Json snapshot() {
    return [
      "success": Json(true),
      "snapshot": db.snapshot()
    ];
  }

  @method(HTTPMethod.POST)
  @path("/hana/ha/restore")
  Json restore(HanaRestoreRequest req) {
    requireAuth(req.token);
    db.restoreFromSnapshot(req.snapshot);

    return [
      "success": Json(true),
      "message": Json("Snapshot restored")
    ];
  }

  private void requireAuth(string token) {
    if (!db.authorize(token)) {
      throw new HTTPStatusException(HTTPStatus.forbidden, "Invalid API token");
    }
  }

  private ColumnType parseColumnType(string typeName) {
    switch (typeName.toUpper()) {
      case "INTEGER": return ColumnType.INTEGER;
      case "DOUBLE": return ColumnType.DOUBLE;
      case "STRING": return ColumnType.STRING;
      case "BOOLEAN": return ColumnType.BOOLEAN;
      case "TIMESTAMP": return ColumnType.TIMESTAMP;
      case "SPATIAL": return ColumnType.SPATIAL;
      case "TEXT": return ColumnType.TEXT;
      case "GRAPH": return ColumnType.GRAPH;
      case "JSON": return ColumnType.JSON;
      default: throw new Exception("Unknown column type: " ~ typeName);
    }
  }
}
