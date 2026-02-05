module uim.databases.rtad.stream.processor;

import core.sync.rwmutex;
import core.thread;
import std.datetime;
import std.algorithm;
import std.array;
import vibe.core.log;
import uim.databases.rtad.storage;

/// Stream processor for real-time data ingestion
class StreamProcessor {
    private {
        TimeSeriesStorage _storage;
        DataPoint[] _buffer;
        ReadWriteMutex _mutex;
        bool _running;
        Thread _processorThread;
        size_t _bufferSize;
        size_t _flushIntervalMs;
    }
    
    this(TimeSeriesStorage storage, size_t bufferSize = 10000, size_t flushIntervalMs = 1000) {
        _storage = storage;
        _bufferSize = bufferSize;
        _flushIntervalMs = flushIntervalMs;
        _mutex = new ReadWriteMutex();
    }
    
    /// Start stream processor
    void start() {
        if (_running) return;
        _running = true;
        _processorThread = new Thread(&processorLoop);
        _processorThread.start();
        logInfo("Stream processor started");
    }
    
    /// Stop stream processor
    void stop() {
        _running = false;
        if (_processorThread) {
            _processorThread.join();
        }
        flush();
        logInfo("Stream processor stopped");
    }
    
    /// Add data point to stream
    void pushDataPoint(DataPoint point) {
        synchronized(_mutex.writer) {
            _buffer ~= point;
            
            if (_buffer.length >= _bufferSize) {
                flush();
            }
        }
    }
    
    /// Add multiple data points
    void pushDataPoints(DataPoint[] points) {
        synchronized(_mutex.writer) {
            _buffer ~= points;
            
            while (_buffer.length >= _bufferSize) {
                flush();
            }
        }
    }
    
    /// Get buffer size
    @property size_t bufferLength() {
        synchronized(_mutex.reader) {
            return _buffer.length;
        }
    }
    
    /// Flush buffer to storage
    void flush() {
        synchronized(_mutex.writer) {
            if (_buffer.empty) return;
            
            foreach (point; _buffer) {
                _storage.upsertMetric(point.metric, point.tags, point);
            }
            
            logInfo("Flushed %d points to storage", _buffer.length);
            _buffer = [];
        }
    }
    
    private {
        void processorLoop() {
            while (_running) {
                Thread.sleep(dur!"msecs"(_flushIntervalMs));
                flush();
            }
        }
    }
}

import core.time;
