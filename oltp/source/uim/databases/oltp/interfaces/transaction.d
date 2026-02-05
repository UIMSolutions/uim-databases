module uim.databases.oltp.interfaces.transaction;

import std.datetime;

/// Transaction isolation levels
enum IsolationLevel {
    readUncommitted,
    readCommitted,
    repeatableRead,
    serializable
}

/// Transaction state
enum TransactionState {
    active,
    committed,
    aborted,
    failed
}

/// Interface for OLTP transactions
interface ITransaction {
    /// Begin a new transaction
    void begin();
    
    /// Commit the transaction
    void commit();
    
    /// Rollback the transaction
    void rollback();
    
    /// Execute a query within the transaction
    auto execute(string query, string[string] params = null);
    
    /// Get the transaction state
    @property TransactionState state();
    
    /// Get the transaction ID
    @property string id();
    
    /// Get the isolation level
    @property IsolationLevel isolationLevel();
    
    /// Set the isolation level
    @property void isolationLevel(IsolationLevel level);
    
    /// Check if transaction is active
    @property bool isActive();
    
    /// Get transaction start time
    @property SysTime startTime();
}
