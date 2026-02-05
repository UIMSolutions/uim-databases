module app;

import vibe.core.core;
import vibe.http.server;
import vibe.core.log;
import uim.databases.rtad;

shared static this() {
    auto settings = new HTTPServerSettings();
    settings.port = 8086;
    settings.bindAddresses = ["127.0.0.1"];
    
    // Initialize components
    auto storage = new TimeSeriesStorage("main", 1_000_000);
    auto processor = new StreamProcessor(storage, 10_000, 1_000);
    auto queryEngine = new QueryEngine(storage);
    
    // Create REST API
    auto api = new RTADRestAPI(storage, processor, queryEngine);
    
    // Start processor
    processor.start();
    
    // Setup and listen
    listenHTTP(settings, api.router);
    
    logInfo("Real-time Analytical Database server running on http://localhost:8086");
}
