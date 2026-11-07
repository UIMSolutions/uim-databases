module app;

import uim.hdb;

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

    auto backups = new BackupService(service, new FileBackupStore(environment.get("BACKUP_DIR", "data/backups")),
        toDelegate(&currentPrincipal));

    // Fällige Sicherungen anlegen; der Takt legt nur fest, wie schnell eine fällige Sicherung bemerkt wird
    setTimer(environment.get("BACKUP_TICK_SECONDS", "60").to!long.seconds, () nothrow {
        try {
            if (auto error = backups.tick())
                logWarn("Geplante Sicherung fehlgeschlagen: %s", error);
        } catch (Exception e) {
            try
                logWarn("Geplante Sicherung fehlgeschlagen: %s", e.msg);
            catch (Exception) {
            }
        }
    }, true);

    auto router = new URLRouter;
    new SecurityGate(access).register(router); // muss vor allen anderen Routen stehen
    new SqlRestApi(secured).register(router);
    registerHdbRestApi(router, secured, access, backups, toDelegate(&currentPrincipal));
    new ODataController(secured).register(router);
    new SqlAdminUi(secured, access, backups).register(router);
    
    // Fiori-Frontend: OData-Client, der nur /odata/v4 und die Anmeldung nutzt
    router.get("/ui5", staticRedirect("/ui5/"));
    router.get("/ui5/", serveStaticFile("public/ui5/index.html"));

    // Serve static assets if needed
    router.get("/*", serveStaticFiles("public/"));

    auto settings = new HTTPServerSettings;
    settings.port = environment.get("PORT", "8080").to!ushort;
    settings.bindAddresses = ["0.0.0.0"];
    settings.maxRequestSize = environment.get("MAX_REQUEST_MB", "256").to!ulong * 1024 * 1024; // hochgeladene Sicherungen
    listenHTTP(settings, router);

    // Optional: lokale Clients ohne TCP. Anmeldung und Rollen gelten wie über HTTP
    UnixServer unixServer;
    auto socketPath = environment.get("UNIX_SOCKET", "");
    if (socketPath.length) {
        unixServer = new UnixServer(socketPath, [new UnixController(secured, access)]);
        unixServer.start();
    }

    runApplication();

    if (unixServer !is null)
        unixServer.stop();
}
