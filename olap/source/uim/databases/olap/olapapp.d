module uim.databases.olap.olapapp;

import vibe.vibe;
import uim.databases.olap;

/// OLAP Data Warehouse Server Application
class OLAPApp {
    private {
        DataWarehouse _warehouse;
        OLAPRestAPI _api;
        string _warehouseName;
        ushort _port;
    }
    
    this(string warehouseName = "warehouse", ushort port = 9090) {
        _warehouseName = warehouseName;
        _port = port;
    }
    
    /// Start the warehouse server
    void start() {
        logInfo("Starting OLAP Data Warehouse Server...");
        
        // Initialize warehouse
        _warehouse = new DataWarehouse(_warehouseName);
        
        // Initialize REST API
        _api = new OLAPRestAPI(_warehouse, _port);
        
        // Start API server
        _api.start();
        
        logInfo("OLAP Data Warehouse Server started successfully");
        logInfo("Warehouse: %s", _warehouseName);
        logInfo("API Port: %d", _port);
        logInfo("Access the API at: http://localhost:%d", _port);
    }
}

/// Main entry point for the OLAP server
int main(string[] args) {
    string warehouseName = "warehouse";
    ushort port = 9090;
    
    // Parse command line arguments
    if (args.length > 1) {
        warehouseName = args[1];
    }
    if (args.length > 2) {
        import std.conv : to;
        port = args[2].to!ushort;
    }
    
    auto app = new OLAPApp(warehouseName, port);
    
    try {
        app.start();
        
        // Run the event loop
        return runApplication();
    } catch (Exception e) {
        logError("Error: %s", e.msg);
        return 1;
    }
}
