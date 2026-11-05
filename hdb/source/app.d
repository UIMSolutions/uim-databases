module app;

import uim.hdb.adapters.inbound.admin_web;
import uim.hdb.adapters.inbound.rest_api;
import uim.hdb.adapters.outbound.file_statement_log;
import uim.hdb.adapters.outbound.in_memory_repository;
import uim.hdb;
import std.conv : to;
import std.process : environment;
import vibe.d;

/// Composition Root: einziger Ort, an dem Adapter und Kern verdrahtet werden.
void main()
{
    auto repo = new InMemoryTableRepository;
    auto log = new FileStatementLog(environment.get("DATA_FILE", "data/hana-lite.log"));
    auto service = new SqlService(repo, log);
    service.recover();    // Zustand aus dem Protokoll wiederherstellen, bevor HTTP startet
    service.mergeDelta(); // eingespielte Daten sofort in den komprimierten Main-Store
    auto api = new SqlRestApi(service);

    auto router = new URLRouter;
    api.register(router);
    
    auto admin = new SqlAdminUi(service, environment.get("ADMIN_USER", "admin"), environment.get("ADMIN_PASSWORD", ""));
    admin.register(router);
    
    // Serve static assets if needed
    router.get("/*", serveStaticFiles("public/"));

    auto settings = new HTTPServerSettings;
    settings.port = environment.get("PORT", "8080").to!ushort;
    settings.bindAddresses = ["0.0.0.0"];
    listenHTTP(settings, router);

    runApplication();
}
