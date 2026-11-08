/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module app;

import uim.hdb;
import uim.hdb.gateway : GatewayConfigFile, GatewayProxy;

/// Composition Root: einziger Ort, an dem Adapter und Kern verdrahtet werden.
/// HDB_MODE wählt die Betriebsart: multi (Standard), single oder gateway. Eingebettet ist keine Betriebsart des
/// Servers, sondern die Bibliothek (dub build --config=library, Modul uim.hdb.embedded).
void main() @safe {
    ServerMode mode;
    try
        mode = parseServerMode(environment.get("HDB_MODE", ""));
    catch (Exception e)
        return logError("%s", e.msg);
    if (mode == ServerMode.gateway)
        return runGateway();
    immutable single = mode == ServerMode.single;

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
    if (!registry.has(defaultTenant) && (firstStart || migrated || legacyUsers || single))
        registry.put(Tenant(defaultTenant, "Default", true));
    if (single) {
        // Zurück von mehreren Mandanten nur ohne weitere Mandanten: deren Daten wären sonst nicht mehr erreichbar
        auto others = registry.all().filter!(t => t.name != defaultTenant).map!(t => t.name).array;
        if (others.length)
            return logError("HDB_MODE=single needs a server with only the tenant '%s', but there are also: %s. "
                ~ "Move or delete these tenants first, or run with HDB_MODE=multi.", defaultTenant, others.join(", "));
    }

    // Eigene Rollen aller Mandanten und des Bereichs system; die vordefinierten stehen nicht in der Datei
    // Befristete Freigaben laufen nach der Systemuhr (UTC); erlaubte Netze kommen aus der Mandantenliste
    auto access = new AccessService(userStore, new OpensslCredentialCrypto, null, &registry.isActive,
        new FileRoleStore(environment.get("ROLES_FILE", "data/hdb-roles.json")), null, &registry.networks);
    void announce(string tenant, string name, string generated) {
        if (generated.length)
            logWarn("Erster Start: Benutzer '%s' im Mandanten '%s' mit Passwort '%s' angelegt. Bitte unter /admin/account ändern.",
                name, tenant, generated);
    }

    if (registry.has(defaultTenant)) {
        auto adminName = environment.get("ADMIN_USER", "admin");
        announce(defaultTenant, adminName, access.bootstrap(defaultTenant, adminName, environment.get("ADMIN_PASSWORD", "")));
    }
    if (single)
        access.restrictTo(defaultTenant); // ohne Mandantenfeld und ohne Systembereich
    else {
        auto systemAdmin = environment.get("SYSTEM_ADMIN_USER", "sysadmin");
        announce(systemTenant, systemAdmin, access.bootstrap(systemTenant, systemAdmin, environment.get(
                "SYSTEM_ADMIN_PASSWORD", "")));
    }

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
    // X-Forwarded-For zählt nur von diesen Proxys (durch Komma getrennt, Adressen oder Netze); ohne die Variable
    // gilt die Adresse der Verbindung
    auto trustedProxies = parseNetworks(environment.get("TRUSTED_PROXIES", "").split(","));
    new SecurityGate(access, trustedProxies).register(router); // muss vor allen anderen Routen stehen
    registerServerInfo(router, mode);
    new SqlRestApi(secured).register(router);
    registerHdbRestApi(router, secured, access, backups, tenants, databases, toDelegate(&currentPrincipal));
    new ODataController(secured).register(router);
    auto adminUi = new SqlAdminUi(secured, access, backups, tenants, databases);
    adminUi.singleTenant = single;
    adminUi.register(router);

    // Fiori-Frontend: OData-Client, der nur /odata/v4 und die Anmeldung nutzt
    router.get("/ui5", staticRedirect("/ui5/"));
    router.get("/ui5/", serveStaticFile("public/ui5/index.html"));

    // Serve static assets if needed
    router.get("/*", serveStaticFiles("public/"));

    listenHTTP(serverSettings(), router);
    logInfo("Betriebsart: %s", modeName(mode));

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

private HTTPServerSettings serverSettings() @safe {
    auto settings = new HTTPServerSettings;
    settings.port = environment.get("PORT", "8080").to!ushort;
    settings.bindAddresses = ["0.0.0.0"];
    settings.maxRequestSize = environment.get("MAX_REQUEST_MB", "256").to!ulong * 1024 * 1024; // hochgeladene Sicherungen
    return settings;
}

/// Verteilter Betrieb: dieser Prozess hat keine Daten und keine Benutzer, er leitet jede Anfrage an den hdb-Server
/// des Mandanten weiter (GATEWAY_CONFIG, siehe uim.hdb.gateway.routes). Die Backends sollten das Gateway in
/// TRUSTED_PROXIES eintragen, sonst gelten deren erlaubte Netze für die Adresse des Gateways.
private void runGateway() @safe {
    auto path = environment.get("GATEWAY_CONFIG", "data/hdb-gateway.json");
    GatewayConfigFile config;
    try
        config = new GatewayConfigFile(path);
    catch (Exception e)
        return logError("Gateway: Konfiguration %s nicht lesbar: %s", path, e.msg);
    auto router = new URLRouter;
    registerServerInfo(router, ServerMode.gateway);
    new GatewayProxy(&config.current, environment.get("GATEWAY_CONNECT_SECONDS", "5").to!long.seconds,
        environment.get("GATEWAY_READ_SECONDS", "300").to!long.seconds).register(router);
    listenHTTP(serverSettings(), router);
    logInfo("Betriebsart: gateway, Backends: %s", config.current().backendIds);
    runApplication();
}
