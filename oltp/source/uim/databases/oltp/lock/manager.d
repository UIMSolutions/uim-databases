module uim.databases.oltp.lock.manager;

import core.sync.mutex;
import core.thread;
import std.datetime;
import std.algorithm;
import vibe.core.log;
import uim.databases.oltp.lock.mode;

/// Represents a lock held on a resource
struct Lock {
    string resourceId;
    string transactionId;
    LockMode mode;
    SysTime acquiredAt;
}

/// Lock manager for handling concurrent access
class LockManager {
    private {
        Lock[][string] _locks; // resourceId -> [locks]
        Mutex _mutex;
        Duration _timeout;
    }
    
    this(Duration timeout = 10.seconds) {
        _mutex = new Mutex();
        _timeout = timeout;
    }
    
    /// Acquire a lock on a resource
    bool acquire(string resourceId, string transactionId, LockMode mode) {
        auto startTime = MonoTime.currTime;
        
        while (true) {
            synchronized(_mutex) {
                if (canAcquire(resourceId, transactionId, mode)) {
                    addLock(resourceId, transactionId, mode);
                    logInfo("Lock acquired: %s by %s (%s)", resourceId, transactionId, mode);
                    return true;
                }
            }
            
            // Check timeout
            if (MonoTime.currTime - startTime > _timeout) {
                logWarn("Lock timeout: %s by %s (%s)", resourceId, transactionId, mode);
                return false;
            }
            
            // Wait a bit before retrying
            Thread.sleep(10.msecs);
        }
    }
    
    /// Release a lock
    void release(string resourceId, string transactionId) {
        synchronized(_mutex) {
            if (resourceId in _locks) {
                _locks[resourceId] = _locks[resourceId]
                    .filter!(l => l.transactionId != transactionId)
                    .array;
                
                if (_locks[resourceId].length == 0) {
                    _locks.remove(resourceId);
                }
                
                logInfo("Lock released: %s by %s", resourceId, transactionId);
            }
        }
    }
    
    /// Release all locks held by a transaction
    void releaseAll(string transactionId) {
        synchronized(_mutex) {
            string[] resourcesToRemove;
            
            foreach (resourceId, ref locks; _locks) {
                locks = locks.filter!(l => l.transactionId != transactionId).array;
                
                if (locks.length == 0) {
                    resourcesToRemove ~= resourceId;
                }
            }
            
            foreach (resourceId; resourcesToRemove) {
                _locks.remove(resourceId);
            }
            
            logInfo("All locks released for transaction %s", transactionId);
        }
    }
    
    /// Check if a lock can be acquired
    private bool canAcquire(string resourceId, string transactionId, LockMode mode) {
        // If transaction already holds a lock, allow upgrade
        if (resourceId in _locks) {
            foreach (lock; _locks[resourceId]) {
                if (lock.transactionId == transactionId) {
                    return true; // Allow same transaction to upgrade
                }
                
                // Check compatibility with existing locks
                if (!areCompatible(lock.mode, mode)) {
                    return false;
                }
            }
        }
        
        return true;
    }
    
    /// Add a lock to the manager
    private void addLock(string resourceId, string transactionId, LockMode mode) {
        auto lock = Lock(
            resourceId,
            transactionId,
            mode,
            Clock.currTime()
        );
        
        if (resourceId !in _locks) {
            _locks[resourceId] = [];
        }
        
        _locks[resourceId] ~= lock;
    }
    
    /// Get all locks for a resource
    Lock[] getLocksForResource(string resourceId) {
        synchronized(_mutex) {
            if (auto locks = resourceId in _locks) {
                return (*locks).dup;
            }
            return [];
        }
    }
    
    /// Get all locks for a transaction
    Lock[] getLocksForTransaction(string transactionId) {
        synchronized(_mutex) {
            Lock[] result;
            foreach (locks; _locks.values) {
                result ~= locks.filter!(l => l.transactionId == transactionId).array;
            }
            return result;
        }
    }
    
    /// Check for deadlocks (simplified version)
    bool hasDeadlock(string transactionId) {
        // TODO: Implement proper deadlock detection algorithm
        return false;
    }
    
    /// Get lock statistics
    Json getStatistics() {
        synchronized(_mutex) {
            auto stats = Json.emptyObject;
            stats["totalResources"] = _locks.length;
            
            size_t totalLocks = 0;
            foreach (locks; _locks.values) {
                totalLocks += locks.length;
            }
            stats["totalLocks"] = totalLocks;
            stats["timeout"] = _timeout.total!"seconds";
            
            return stats;
        }
    }
}

import vibe.data.json;
