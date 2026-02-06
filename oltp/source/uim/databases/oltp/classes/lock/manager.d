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



