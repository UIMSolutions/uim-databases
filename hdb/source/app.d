/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module app;

import uim.hdb;

/// Composition Root: einziger Ort, an dem Adapter und Kern verdrahtet werden.
void main() {
    // Eine Datenbank je Mandant unter TENANTS_DIR. Daten aus der Zeit vor den Mandanten (TABLES_DIR, DATA_FILE,
    // BACKUP_DIR) ziehen beim ersten Start in den Mandanten default.
    auto tenantsDir = environment.get("TENANTS_DIR", "data/tenants");
    immutable migrated = migrateLegacyData(tenantsDir, environment.get("TABLES_DIR", "data/tables"),
        environment.get("DATA_FILE", "data/hdb.log"), environment.get("BACKUP_DIR", "data/backups"));
    auto registry = new TenantRegistry(new FileTenantStore(environment.get("TENANTS_FILE", "data/hdb-tenants.json")));
    auto userStore = new FileUserStore(environment.get("USERS_FILE", "data/hdb-users.json"));
    // default entsteht beim ersten Start und bei der Umstellung, wenn es bisherige Daten oder Benutzer gibt
    // (Benutzer ohne Mandant gehören zu default, siehe FileUserStore). Wurde er gelöscht, bleibt er weg.
    auto knownUsers = userStore.load();
    immutable firstStart = registry.all().length == 0 && knownUsers.length == 0;
    immutable legacyUsers = knownUsers.canFind!(u => u.tenant == defaultTenant);
    if (!registry.has(defaultTenant) && (firstStart || migrated || legacyUsers))
        registry.put(Tenant(defaultTenant, "Default", true));

    // Eigene Rollen aller Mandanten und des Bereichs system; die vordefinierten stehen nicht in der Datei
    auto access = new AccessService(userStore, new OpensslCredentialCrypto, null, &registry.isActive,
        new FileRoleStore(environment.get("ROLES_FILE", "data/hdb-roles.json")));
    void announce(string tenant, string name, string generated) {
        if (generated.length)
            logWarn("Erster Start: Benutzer '%s' im Mandanten '%s' mit Passwort '%s' angelegt. Bitte unter /admin/account ändern.",
                name, tenant, generated);
    }

    if (registry.has(defaultTenant)) {
        auto adminName = environment.get("ADMIN_USER", "admin");
        announce(defaultTenant, adminName, access.bootstrap(defaultTenant, adminName, environment.get("ADMIN_PASSWORD", "")));
    }
    auto systemAdmin = environment.get("SYSTEM_ADMIN_USER", "sysadmin");
    announce(systemTenant, systemAdmin, access.bootstrap(systemTenant, systemAdmin, environment.get(
            "SYSTEM_ADMIN_PASSWORD", "")));

    // Alle eingehenden Adapter sehen nur die abgesicherte, nach Mandanten getrennte Sicht auf den Kern.
    auto storage = new FileTenantStorage(tenantsDir);
    // Replikation: jeder Mandant kann Quelle und Ziel sein. REPLICATION_ALLOWED_HOSTS (durch Komma getrennt) begrenzt,
    // welche Quellen Mandanten-Admins eintragen dürfen; REPLICATION_RETAIN, wie viele Änderungen abrufbar bleiben.
    auto replicationClient = new HttpReplicationClient(environment.get("REPLICATION_ALLOWED_HOSTS", "").split(",")
        .map!(h => h.strip).array);
    auto databases = new TenantDatabases(storage, toDelegate(&currentPrincipal), replicationClient,
        environment.get("REPLICATION_RETAIN", "10000").to!size_t);
    foreach (t; registry.all())
        databases.open(t.name); // Zustand aus dem Protokoll wiederherstellen, bevor HTTP startet
    auto tenants = new TenantService(registry, access, databases, storage);
    ISqlUseCase secured = databases;
    IBackupUseCase backups = databases;

    // Fällige Sicherungen anlegen; der Takt legt nur fest, wie schnell eine fällige Sicherung bemerkt wird
    setTimer(environment.get("BACKUP_TICK_SECONDS", "60").to!long.seconds, () nothrow{
        try {
            if (auto error = databases.tick())
                logWarn("Geplante Sicherung fehlgeschlagen: %s", error);
        } catch (Exception e) {
            try
                logWarn("Geplante Sicherung fehlgeschlagen: %s", e.msg);
            catch (Exception) {
            }
        }
    }, true);

    // Ziele holen Änderungen ihrer Quelle; jedes Ziel hat seinen eigenen Abstand, der Takt prüft nur, wer fällig ist
    bool replicating;
    setTimer(1.seconds, () nothrow {
        if (replicating)
            return; // ein Lauf wartet noch auf eine Quelle
        replicating = true;
        scope (exit)
            replicating = false;
        try {
            foreach (error; databases.replicationTick())
                logWarn("Replikation fehlgeschlagen: %s", error);
        } catch (Exception e) {
            try
                logWarn("Replikation fehlgeschlagen: %s", e.msg);
            catch (Exception) {
            }
        }
    }, true);

    auto router = new URLRouter;
    new SecurityGate(access).register(router); // muss vor allen anderen Routen stehen
    new SqlRestApi(secured).register(router);
    registerHdbRestApi(router, secured, access, backups, tenants, databases, toDelegate(&currentPrincipal));
    new ODataController(secured).register(router);
    new SqlAdminUi(secured, access, backups, tenants, databases).register(router);

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
        unixServer = new UnixServer(socketPath, [
                new UnixController(secured, access)
            ]);
        unixServer.start();
    }

    runApplication();

    if (unixServer !is null)
        unixServer.stop();
}
