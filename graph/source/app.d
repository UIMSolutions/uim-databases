module app;

import vibe.core.core;
import vibe.http.server;
import vibe.core.log;
import uim.databases.graph.storage.graph;
import uim.databases.graph.storage.node;
import uim.databases.graph.storage.edge;
import uim.databases.graph.api;

void main() {
    auto settings = new HTTPServerSettings();
    settings.port = 8080;
    settings.bindAddresses = ["127.0.0.1"];
    
    // Initialize graph
    auto graph = new GraphStorage("main");
    
    // Create REST API
    auto api = new GraphRestAPI(graph);
    
    // Setup and listen
    auto listener = listenHTTP(settings, api.router);
    scope (exit) listener.stopListening();
    
    logInfo("Graph database server running on http://localhost:8080");
    logInfo("Graph: %s (nodes: %d, edges: %d)", 
        graph.name, graph.nodeCount, graph.edgeCount);
    
    runEventLoop();
}
