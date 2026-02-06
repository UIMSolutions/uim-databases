/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.oltp.interfaces.connection;

import uim.databases.oltp.interfaces.transaction;

/// Interface for database connections
interface IConnection {
    /// Open the connection
    void open();
    
    /// Close the connection
    void close();
    
    /// Check if connection is open
    @property bool isOpen();
    
    /// Begin a new transaction
    ITransaction beginTransaction(IsolationLevel level = IsolationLevel.readCommitted);
    
    /// Execute a query without transaction
    auto execute(string query, string[string] params = null);
    
    /// Ping the connection to keep it alive
    bool ping();
    
    /// Get connection string
    @property string connectionString();
}
