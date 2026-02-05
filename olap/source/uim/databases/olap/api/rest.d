module uim.databases.olap.api.rest;

import vibe.vibe;
import uim.databases.olap.warehouse;

/// REST API for OLAP Warehouse
class OLAPRestAPI {
    private {
        DataWarehouse _warehouse;
        HTTPServerSettings _settings;
    }
    
    this(DataWarehouse warehouse, ushort port = 9090, string bindAddress = "127.0.0.1") {
        _warehouse = warehouse;
        _settings = new HTTPServerSettings();
        _settings.port = port;
        _settings.bindAddresses = [bindAddress];
    }
    
    /// Start the REST API server
    void start() {
        auto router = new URLRouter();
        
        // Warehouse info
        router.get("/", &getInfo);
        router.get("/stats", &getStats);
        
        // Cube management
        router.post("/cubes", &createCube);
        router.get("/cubes", &listCubes);
        router.get("/cubes/:cubeName", &getCubeInfo);
        router.delete_("/cubes/:cubeName", &deleteCube);
        
        // Data loading
        router.post("/cubes/:cubeName/facts", &loadFactData);
        router.post("/cubes/:cubeName/dimensions/:dimName", &loadDimensionData);
        
        // OLAP queries
        router.post("/cubes/:cubeName/aggregate", &aggregate);
        router.post("/cubes/:cubeName/slice", &slice);
        router.post("/cubes/:cubeName/dice", &dice);
        router.post("/cubes/:cubeName/pivot", &pivot);
        router.post("/cubes/:cubeName/drilldown", &drillDown);
        router.post("/cubes/:cubeName/rollup", &rollUp);
        
        // Query builder
        router.post("/query", &executeQuery);
        
        listenHTTP(_settings, router);
        
        logInfo("OLAP REST API started on %s:%d", _settings.bindAddresses[0], _settings.port);
    }
    
    // Handler methods
    
    void getInfo(HTTPServerRequest req, HTTPServerResponse res) {
        auto info = Json.emptyObject;
        info["name"] = _warehouse.name;
        info["version"] = "1.0.0";
        info["type"] = "OLAP Data Warehouse";
        res.writeJsonBody(info);
    }
    
    void getStats(HTTPServerRequest req, HTTPServerResponse res) {
        res.writeJsonBody(_warehouse.getStatistics());
    }
    
    void createCube(HTTPServerRequest req, HTTPServerResponse res) {
        auto body = req.json;
        
        try {
            auto cubeName = body["name"].get!string;
            auto measures = body["measures"].deserializeJson!(string[]);
            auto dimensionKeys = body["dimensionKeys"].deserializeJson!(string[]);
            
            _warehouse.createCube(cubeName, measures, dimensionKeys);
            
            // Add dimensions if provided
            if ("dimensions" in body) {
                foreach (dimJson; body["dimensions"]) {
                    auto dimName = dimJson["name"].get!string;
                    auto attributes = dimJson["attributes"].deserializeJson!(string[]);
                    _warehouse.addDimension(cubeName, dimName, attributes);
                }
            }
            
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Cube created")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void listCubes(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubes = _warehouse.getCubeNames();
        res.writeJsonBody(Json(["cubes": serializeToJson(cubes)]));
    }
    
    void getCubeInfo(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        
        try {
            auto cube = _warehouse.getCube(cubeName);
            res.writeJsonBody(cube.getMetadata());
        } catch (Exception e) {
            res.statusCode = HTTPStatus.notFound;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void deleteCube(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        
        try {
            _warehouse.deleteCube(cubeName);
            res.writeJsonBody(Json(["success": Json(true), "message": Json("Cube deleted")]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void loadFactData(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto data = req.json;
        
        try {
            Json[] rows;
            if (data.type == Json.Type.array) {
                foreach (row; data) {
                    rows ~= row;
                }
            } else {
                rows = [data];
            }
            
            _warehouse.loadFactData(cubeName, rows);
            
            res.writeJsonBody(Json([
                "success": Json(true),
                "rowsLoaded": Json(rows.length),
                "message": Json("Fact data loaded")
            ]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void loadDimensionData(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto dimName = req.params["dimName"];
        auto data = req.json;
        
        try {
            Json[] rows;
            if (data.type == Json.Type.array) {
                foreach (row; data) {
                    rows ~= row;
                }
            } else {
                rows = [data];
            }
            
            _warehouse.loadDimensionData(cubeName, dimName, rows);
            
            res.writeJsonBody(Json([
                "success": Json(true),
                "rowsLoaded": Json(rows.length),
                "message": Json("Dimension data loaded")
            ]));
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void aggregate(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto body = req.json;
        
        try {
            auto dimensions = body["dimensions"].deserializeJson!(string[]);
            auto measures = body["measures"].deserializeJson!(string[]);
            Json filters = Json.emptyObject;
            if ("filters" in body) {
                filters = body["filters"];
            }
            
            auto result = _warehouse.aggregate(cubeName, dimensions, measures, filters);
            res.writeJsonBody(result);
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void slice(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto body = req.json;
        
        try {
            auto dimension = body["dimension"].get!string;
            auto value = body["value"].get!string;
            auto measures = body["measures"].deserializeJson!(string[]);
            
            auto result = _warehouse.slice(cubeName, dimension, value, measures);
            res.writeJsonBody(result);
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void dice(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto body = req.json;
        
        try {
            auto filters = body["filters"];
            auto dimensions = body["dimensions"].deserializeJson!(string[]);
            auto measures = body["measures"].deserializeJson!(string[]);
            
            auto result = _warehouse.dice(cubeName, filters, dimensions, measures);
            res.writeJsonBody(result);
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void pivot(HTTPServerRequest req, HTTPServerResponse res) {
        auto cubeName = req.params["cubeName"];
        auto body = req.json;
        
        try {
            auto rowDimensions = body["rowDimensions"].deserializeJson!(string[]);
            auto columnDimensions = body["columnDimensions"].deserializeJson!(string[]);
            auto measures = body["measures"].deserializeJson!(string[]);
            Json filters = Json.emptyObject;
            if ("filters" in body) {
                filters = body["filters"];
            }
            
            auto result = _warehouse.pivot(cubeName, rowDimensions, columnDimensions, measures, filters);
            res.writeJsonBody(result);
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
    
    void drillDown(HTTPServerRequest req, HTTPServerResponse res) {
        // TODO: Implement drill-down
        res.writeJsonBody(Json(["success": Json(false), "error": Json("Not implemented")]));
    }
    
    void rollUp(HTTPServerRequest req, HTTPServerResponse res) {
        // TODO: Implement roll-up
        res.writeJsonBody(Json(["success": Json(false), "error": Json("Not implemented")]));
    }
    
    void executeQuery(HTTPServerRequest req, HTTPServerResponse res) {
        auto body = req.json;
        
        try {
            auto cubeName = body["cube"].get!string;
            auto dimensions = body["dimensions"].deserializeJson!(string[]);
            auto measures = body["measures"].deserializeJson!(string[]);
            Json filters = Json.emptyObject;
            if ("filters" in body) {
                filters = body["filters"];
            }
            
            auto result = _warehouse.aggregate(cubeName, dimensions, measures, filters);
            res.writeJsonBody(result);
        } catch (Exception e) {
            res.statusCode = HTTPStatus.badRequest;
            res.writeJsonBody(Json(["success": Json(false), "error": Json(e.msg)]));
        }
    }
}
