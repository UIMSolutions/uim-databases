module uim.databases.oltp.classes.transaction;

import std.datetime;
import std.uuid;
import vibe.core.log;
import uim.databases.oltp.interfaces.transaction;
import uim.databases.oltp.interfaces.connection;

/// Basic implementation of ITransaction
class Transaction : ITransaction {
    private {
        string _id;
        IConnection _connection;
        TransactionState _state;
        IsolationLevel _isolationLevel;
        SysTime _startTime;
    }
    
    this(IConnection connection, IsolationLevel level = IsolationLevel.readCommitted) {
        _connection = connection;
        _isolationLevel = level;
        _id = randomUUID().toString();
        _state = TransactionState.active;
    }
    
    /// Begin a new transaction
    override void begin() {
        if (_state == TransactionState.active) {
            logWarn("Transaction already active");
            return;
        }
        
        _startTime = Clock.currTime();
        _state = TransactionState.active;
        
        // Execute BEGIN TRANSACTION command
        string isolationCommand;
        final switch (_isolationLevel) {
            case IsolationLevel.readUncommitted:
                isolationCommand = "SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED";
                break;
            case IsolationLevel.readCommitted:
                isolationCommand = "SET TRANSACTION ISOLATION LEVEL READ COMMITTED";
                break;
            case IsolationLevel.repeatableRead:
                isolationCommand = "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ";
                break;
            case IsolationLevel.serializable:
                isolationCommand = "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE";
                break;
        }
        
        _connection.execute(isolationCommand);
        _connection.execute("BEGIN TRANSACTION");
        
        logInfo("Transaction %s started with isolation level %s", _id, _isolationLevel);
    }
    
    /// Commit the transaction
    override void commit() {
        if (_state != TransactionState.active) {
            throw new Exception("Cannot commit: transaction is not active");
        }
        
        try {
            _connection.execute("COMMIT");
            _state = TransactionState.committed;
            logInfo("Transaction %s committed", _id);
        } catch (Exception e) {
            _state = TransactionState.failed;
            logError("Transaction %s commit failed: %s", _id, e.msg);
            throw e;
        }
    }
    
    /// Rollback the transaction
    override void rollback() {
        if (_state != TransactionState.active) {
            logWarn("Transaction %s is not active, cannot rollback", _id);
            return;
        }
        
        try {
            _connection.execute("ROLLBACK");
            _state = TransactionState.aborted;
            logInfo("Transaction %s rolled back", _id);
        } catch (Exception e) {
            _state = TransactionState.failed;
            logError("Transaction %s rollback failed: %s", _id, e.msg);
            throw e;
        }
    }
    
    /// Execute a query within the transaction
    override auto execute(string query, string[string] params = null) {
        if (_state != TransactionState.active) {
            throw new Exception("Cannot execute query: transaction is not active");
        }
        
        return _connection.execute(query, params);
    }
    
    /// Get the transaction state
    @property override TransactionState state() {
        return _state;
    }
    
    /// Get the transaction ID
    @property override string id() {
        return _id;
    }
    
    /// Get the isolation level
    @property override IsolationLevel isolationLevel() {
        return _isolationLevel;
    }
    
    /// Set the isolation level
    @property override void isolationLevel(IsolationLevel level) {
        if (_state == TransactionState.active) {
            throw new Exception("Cannot change isolation level while transaction is active");
        }
        _isolationLevel = level;
    }
    
    /// Check if transaction is active
    @property override bool isActive() {
        return _state == TransactionState.active;
    }
    
    /// Get transaction start time
    @property override SysTime startTime() {
        return _startTime;
    }
}
