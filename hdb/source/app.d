module app;

import adapters.inbound.rest_api;
import adapters.outbound.file_statement_log;
import adapters.outbound.in_memory_repository;
import uim.hdb;
import std.conv : to;
import std.process : environment;
import vibe.d;

struct UserRow {
    string id;
    string name;
    string email;
    string role;
    string status;
}

class AdminWebInterface {
    // GET /admin/users
    void getUsers(HTTPServerRequest req, HTTPServerResponse res) {
        string pageTitle = "User Management";
        string activeTable = "users";
        ulong totalCount = 120;

        // Sample data retrieved from database
        UserRow[] records = [
            UserRow("usr_101", "Alice Freeman", "alice@example.com", "Admin", "Active"),
            UserRow("usr_102", "Bob Smith", "bob@example.com", "Editor", "Active"),
            UserRow("usr_103", "Charlie Brown", "charlie@example.com", "User", "Inactive")
        ];

        // Render the view passing local variables to Diet
        res.render!("table_view.dt", pageTitle, activeTable, totalCount, records);
    }

    // POST /admin/users/create
    @path("/users/create")
    void postUsersCreate(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = req.form.get("name");
        auto email = req.form.get("email");
        auto role = req.form.get("role");

        // Insert into database logic here...

        res.redirect("/admin/users");
    }
}

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
    auto webSettings = new WebInterfaceSettings;
    webSettings.urlPrefix = "/admin";
    router.registerWebInterface(new AdminWebInterface, webSettings);
    
    // Serve static assets if needed
    router.get("/*", serveStaticFiles("public/"));

    auto settings = new HTTPServerSettings;
    settings.port = environment.get("PORT", "8080").to!ushort;
    settings.bindAddresses = ["0.0.0.0"];
    listenHTTP(settings, router);

    runApplication();
}
