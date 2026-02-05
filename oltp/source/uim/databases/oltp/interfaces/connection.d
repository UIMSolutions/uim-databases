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
