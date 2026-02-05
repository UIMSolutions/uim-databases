module uim.databases.oltp.interfaces.pool;

import uim.databases.oltp.interfaces.connection;

/// Interface for connection pooling
interface IConnectionPool {
    /// Acquire a connection from the pool
    IConnection acquire();
    
    /// Release a connection back to the pool
    void release(IConnection connection);
    
    /// Get the number of available connections
    @property size_t availableCount();
    
    /// Get the total number of connections
    @property size_t totalCount();
    
    /// Get the maximum pool size
    @property size_t maxPoolSize();
    
    /// Set the maximum pool size
    @property void maxPoolSize(size_t size);
    
    /// Clear all connections
    void clear();
    
    /// Get pool statistics
    string getStatistics();
}
