module uim.databases.oltp.oltpapp;

import vibe.vibe;
import uim.databases.oltp.database;
import uim.databases.oltp.api;

/// OLTP Database Server Application
class OLTPApp {
    private {
        OLTPDatabase _database;
        OLTPRestAPI _api;
        string _dbName;
        ushort _port;
    }
    
    this(string dbName = "mydb", ushort port = 8080) {
        _dbName = dbName;
        _port = port;
    }
    
    /// Start the database server
    void start() {
        logInfo("Starting OLTP Database Server...");
        
        // Initialize database
        _database = new OLTPDatabase(_dbName);
        
        // Initialize REST API
        _api = new OLTPRestAPI(_database, _port);
        
        // Start API server
        _api.start();
        
        logInfo("OLTP Database Server started successfully");
        logInfo("Database: %s", _dbName);
        logInfo("API Port: %d", _port);
        logInfo("Access the API at: http://localhost:%d", _port);
    }
    
    /// Stop the database server
    void stop() {
        logInfo("Stopping OLTP Database Server...");
        _database.shutdown();
        logInfo("OLTP Database Server stopped");
    }
}

/// Main entry point for the OLTP server
int main(string[] args) {
    string dbName = "oltpdb";
    ushort port = 8080;
    
    // Parse command line arguments
    if (args.length > 1) {
        dbName = args[1];
    }
    if (args.length > 2) {
        import std.conv : to;
        port = args[2].to!ushort;
    }
    
    auto app = new OLTPApp(dbName, port);
    
    try {
        app.start();
        
        // Run the event loop
        return runApplication();
    } catch (Exception e) {
        logError("Error: %s", e.msg);
        return 1;
    }
}
