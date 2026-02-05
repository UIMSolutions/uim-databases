module uim.databases.oltp.lock.mode;

/// Lock modes for concurrency control
enum LockMode {
    none,           // No lock
    shared_,        // Read lock (multiple readers allowed)
    exclusive,      // Write lock (exclusive access)
    intentShared,   // Intent to acquire shared locks
    intentExclusive // Intent to acquire exclusive locks
}

/// Check if two lock modes are compatible
bool areCompatible(LockMode mode1, LockMode mode2) {
    if (mode1 == LockMode.none || mode2 == LockMode.none) {
        return true;
    }
    
    // Shared locks are compatible with other shared locks
    if (mode1 == LockMode.shared_ && mode2 == LockMode.shared_) {
        return true;
    }
    
    // Intent locks have special compatibility rules
    if (mode1 == LockMode.intentShared || mode2 == LockMode.intentShared) {
        return mode1 != LockMode.exclusive && mode2 != LockMode.exclusive;
    }
    
    // Exclusive locks are not compatible with anything
    return false;
}
