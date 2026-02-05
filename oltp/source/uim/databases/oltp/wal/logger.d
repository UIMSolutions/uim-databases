module uim.databases.oltp.wal.logger;

import core.sync.mutex;
import std.stdio;
import std.file;
import std.path;
import std.array;
import vibe.core.log;
import vibe.data.json;
import uim.databases.oltp.wal.record;

/// Write-Ahead Logger for durability
class WALLogger {
    private {
        string _logDirectory;
        string _currentLogFile;
        File _logFile;
        Mutex _mutex;
        WALRecord[] _buffer;
        size_t _bufferSize;
        bool _autoFlush;
    }
    
    this(string logDirectory = "./wal", size_t bufferSize = 100, bool autoFlush = true) {
        _logDirectory = logDirectory;
        _bufferSize = bufferSize;
        _autoFlush = autoFlush;
        _mutex = new Mutex();
        
        ensureLogDirectory();
        openNewLogFile();
    }
    
    ~this() {
        close();
    }
    
    private void ensureLogDirectory() {
        if (!exists(_logDirectory)) {
            mkdirRecurse(_logDirectory);
            logInfo("Created WAL directory: %s", _logDirectory);
        }
    }
    
    private void openNewLogFile() {
        import std.datetime : Clock;
        auto timestamp = Clock.currTime().toISOExtString();
        _currentLogFile = buildPath(_logDirectory, "wal_" ~ timestamp ~ ".log");
        _logFile = File(_currentLogFile, "a");
        logInfo("Opened WAL file: %s", _currentLogFile);
    }
    
    /// Log a WAL record
    void log(WALRecord record) {
        synchronized(_mutex) {
            _buffer ~= record;
            
            if (_autoFlush && _buffer.length >= _bufferSize) {
                flush();
            }
        }
    }
    
    /// Log transaction begin
    void logBegin(string transactionId) {
        log(WALRecord(WALRecordType.begin, transactionId));
    }
    
    /// Log insert operation
    void logInsert(string transactionId, string tableName, string rowId, Json data) {
        log(WALRecord(WALRecordType.insert, transactionId, tableName, rowId, data));
    }
    
    /// Log update operation
    void logUpdate(string transactionId, string tableName, string rowId, Json data) {
        log(WALRecord(WALRecordType.update, transactionId, tableName, rowId, data));
    }
    
    /// Log delete operation
    void logDelete(string transactionId, string tableName, string rowId) {
        log(WALRecord(WALRecordType.delete_, transactionId, tableName, rowId));
    }
    
    /// Log transaction commit
    void logCommit(string transactionId) {
        log(WALRecord(WALRecordType.commit, transactionId));
        flush(); // Always flush on commit
    }
    
    /// Log transaction rollback
    void logRollback(string transactionId) {
        log(WALRecord(WALRecordType.rollback, transactionId));
        flush(); // Always flush on rollback
    }
    
    /// Log checkpoint
    void logCheckpoint() {
        log(WALRecord(WALRecordType.checkpoint, "system"));
        flush();
    }
    
    /// Flush buffer to disk
    void flush() {
        synchronized(_mutex) {
            if (_buffer.length == 0) {
                return;
            }
            
            foreach (record; _buffer) {
                _logFile.writeln(record.toJson().toString());
            }
            _logFile.flush();
            
            logInfo("Flushed %d WAL records", _buffer.length);
            _buffer.length = 0;
        }
    }
    
    /// Close the WAL logger
    void close() {
        synchronized(_mutex) {
            flush();
            if (_logFile.isOpen) {
                _logFile.close();
                logInfo("Closed WAL file: %s", _currentLogFile);
            }
        }
    }
    
    /// Read all records from a log file
    static WALRecord[] readLogFile(string logFilePath) {
        WALRecord[] records;
        
        if (!exists(logFilePath)) {
            return records;
        }
        
        auto file = File(logFilePath, "r");
        foreach (line; file.byLine) {
            try {
                auto json = parseJsonString(line.idup);
                records ~= WALRecord.fromJson(json);
            } catch (Exception e) {
                logError("Failed to parse WAL record: %s", e.msg);
            }
        }
        file.close();
        
        return records;
    }
    
    /// Recover from WAL logs
    static WALRecord[] recover(string logDirectory) {
        import std.algorithm : sort;
        import std.range : array;
        
        WALRecord[] allRecords;
        
        if (!exists(logDirectory)) {
            return allRecords;
        }
        
        // Get all log files sorted by name (which includes timestamp)
        auto logFiles = dirEntries(logDirectory, "wal_*.log", SpanMode.shallow)
            .array
            .sort!((a, b) => a.name < b.name);
        
        foreach (entry; logFiles) {
            auto records = readLogFile(entry.name);
            allRecords ~= records;
            logInfo("Recovered %d records from %s", records.length, entry.name);
        }
        
        logInfo("Total recovered records: %d", allRecords.length);
        return allRecords;
    }
    
    /// Truncate old WAL files
    void truncate() {
        synchronized(_mutex) {
            flush();
            _logFile.close();
            
            // Archive old log file
            if (exists(_currentLogFile)) {
                auto archivePath = _currentLogFile ~ ".archived";
                rename(_currentLogFile, archivePath);
                logInfo("Archived WAL file: %s", archivePath);
            }
            
            // Open new log file
            openNewLogFile();
        }
    }
}
