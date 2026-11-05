module app;

import uim.hdb.adapters.inbound.admin_web;
import uim.hdb.adapters.inbound.rest_api;
import uim.hdb.adapters.inbound.security;
import uim.hdb.adapters.outbound.file_user_store;
import uim.hdb.adapters.outbound.file_statement_log;
import uim.hdb.adapters.outbound.openssl_credential_crypto;
import uim.hdb;
import std.conv : to;
import std.functional : toDelegate;
import std.path : buildPath;
import std.process : environment;
import vibe.d;

/// Composition Root: einziger Ort, an dem Adapter und Kern verdrahtet werden.
void main()
{
    auto tablesDir = environment.get("TABLES_DIR", "data/tables");
    auto repo = new RoutingTableRepository(new MemoryTableRepository,
        new FileTableRepository(buildPath(tablesDir, "file")), new JsonTableRepository(buildPath(tablesDir, "json")));
    auto log = new FileStatementLog(environment.get("DATA_FILE", "data/hdb.log"));
    auto service = new SqlService(repo, log);
    service.recover();    // Zustand aus dem Protokoll wiederherstellen, bevor HTTP startet
    service.mergeDelta(); // eingespielte Daten sofort in den komprimierten Main-Store

    auto access = new AccessService(new FileUserStore(environment.get("USERS_FILE", "data/hdb-users.json")),
        new OpensslCredentialCrypto);
    auto adminName = environment.get("ADMIN_USER", "admin");
    auto generated = access.bootstrap(adminName, environment.get("ADMIN_PASSWORD", ""));
    if (generated.length)
        logWarn("Erster Start: Benutzer '%s' mit Passwort '%s' angelegt. Bitte unter /admin/account ändern.", adminName, generated);

    // Alle eingehenden Adapter sehen nur die abgesicherte Sicht auf den Kern.
    auto secured = new SecuredSqlUseCase(service, toDelegate(&currentPrincipal));

    auto router = new URLRouter;
    new SecurityGate(access).register(router); // muss vor allen anderen Routen stehen
    new SqlRestApi(secured).register(router);
    registerHdbRestApi(router, secured, access, toDelegate(&currentPrincipal));
    new ODataController(secured).register(router);
    new SqlAdminUi(secured, access).register(router);
    
    // Fiori-Frontend: OData-Client, der nur /odata/v4 und die Anmeldung nutzt
    router.get("/ui5", staticRedirect("/ui5/"));
    router.get("/ui5/", serveStaticFile("public/ui5/index.html"));

    // Serve static assets if needed
    router.get("/*", serveStaticFiles("public/"));

    auto settings = new HTTPServerSettings;
    settings.port = environment.get("PORT", "8080").to!ushort;
    settings.bindAddresses = ["0.0.0.0"];
    listenHTTP(settings, router);

    runApplication();
}
