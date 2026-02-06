module uim.databases.oltp.classes.pool;

import core.sync.mutex;
import uim.databases.oltp;
@safe:

/// Thread-safe connection pool implementation
class ConnectionPool : IConnectionPool {
    private {
        DList!IConnection _availableConnections;
        DList!IConnection _busyConnections;
        string _connectionString;
        size_t _maxPoolSize;
        size_t _minPoolSize;
        Mutex _mutex;
        size_t _totalAcquired;
        size_t _totalReleased;
    }
    
    this(string connectionString, size_t maxPoolSize = 10, size_t minPoolSize = 2) {
        _connectionString = connectionString;
        _maxPoolSize = maxPoolSize;
        _minPoolSize = minPoolSize;
        _mutex = new Mutex();
        _totalAcquired = 0;
        _totalReleased = 0;
        
        // Initialize minimum connections
        initializePool();
    }
    
    private void initializePool() {
        synchronized(_mutex) {
            for (size_t i = 0; i < _minPoolSize; i++) {
                auto conn = createConnection();
                _availableConnections.insertBack(conn);
            }
            logInfo("Connection pool initialized with %d connections", _minPoolSize);
        }
    }
    
    private IConnection createConnection() {
        auto conn = new Connection(_connectionString);
        conn.open();
        return conn;
    }
    
    /// Acquire a connection from the pool
    override IConnection acquire() {
        synchronized(_mutex) {
            // Try to get from available connections
            if (!_availableConnections.empty) {
                auto conn = _availableConnections.front;
                _availableConnections.removeFront();
                
                // Verify connection is still alive
                if (!conn.ping()) {
                    logWarn("Dead connection found, creating new one");
                    conn = createConnection();
                }
                
                _busyConnections.insertBack(conn);
                _totalAcquired++;
                return conn;
            }
            
            // Create new connection if under max pool size
            size_t totalCount = _availableConnections[].walkLength + _busyConnections[].walkLength;
            if (totalCount < _maxPoolSize) {
                auto conn = createConnection();
                _busyConnections.insertBack(conn);
                _totalAcquired++;
                logInfo("Created new connection, pool size now: %d", totalCount + 1);
                return conn;
            }
            
            // Pool is exhausted
            throw new Exception("Connection pool exhausted: all connections are busy");
        }
    }
    
    /// Release a connection back to the pool
    override void release(IConnection connection) {
        synchronized(_mutex) {
            // Remove from busy connections
            import std.algorithm : remove;
            bool found = false;
            
            foreach (i, conn; _busyConnections[]) {
                if (conn is connection) {
                    _busyConnections.linearRemove(_busyConnections[].take(i + 1).tail(1));
                    found = true;
                    break;
                }
            }
            
            if (!found) {
                logWarn("Attempted to release connection that was not in busy pool");
                return;
            }
            
            // Add back to available connections if connection is healthy
            if (connection.isOpen && connection.ping()) {
                _availableConnections.insertBack(connection);
                _totalReleased++;
            } else {
                logWarn("Released connection is not healthy, discarding");
                connection.close();
            }
        }
    }
    
    /// Get the number of available connections
    @property override size_t availableCount() {
        synchronized(_mutex) {
            return _availableConnections[].walkLength;
        }
    }
    
    /// Get the total number of connections
    @property override size_t totalCount() {
        synchronized(_mutex) {
            return _availableConnections[].walkLength + _busyConnections[].walkLength;
        }
    }
    
    /// Get the maximum pool size
    @property override size_t maxPoolSize() {
        return _maxPoolSize;
    }
    
    /// Set the maximum pool size
    @property override void maxPoolSize(size_t size) {
        synchronized(_mutex) {
            _maxPoolSize = size;
        }
    }
    
    /// Clear all connections
    override void clear() {
        synchronized(_mutex) {
            // Close all available connections
            foreach (conn; _availableConnections[]) {
                conn.close();
            }
            _availableConnections.clear();
            
            logInfo("Connection pool cleared");
        }
    }
    
    /// Get pool statistics
    override string getStatistics() {
        synchronized(_mutex) {
            return format(
                "Pool Statistics:\n" ~
                "  Available: %d\n" ~
                "  Busy: %d\n" ~
                "  Total: %d\n" ~
                "  Max Size: %d\n" ~
                "  Total Acquired: %d\n" ~
                "  Total Released: %d",
                availableCount,
                _busyConnections[].walkLength,
                totalCount,
                _maxPoolSize,
                _totalAcquired,
                _totalReleased
            );
        }
    }
}

// Import needed for walkLength
import std.range : walkLength, take;
import std.range.primitives : front;
