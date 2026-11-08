module uim.hdb.adapters.inbound.admin_web;

import uim.hdb.application.ports;
import uim.hdb;
import uim.hdb.adapters.inbound.security : currentPrincipal, sessionCookie;
import uim.hdb.domain.entities.user;
import uim.hdb.domain.value;
import core.time : MonoTime;
import std.algorithm : all, any, canFind, map, max, min, startsWith;
import std.array : array, join, replace;
import std.conv : to;
import std.exception : enforce;
import std.file : readText;
import std.format : format;
import std.string : icmp, indexOf, strip, toLower, toUpper;
import std.uni : isAlphaNum;
import vibe.data.json : Json, parseJsonString;
import vibe.http.common : Cookie, HTTPStatusException;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import vibe.http.status : HTTPStatus;
import vibe.textfilter.urlencode : urlEncode;

/// Daten, die das Layout auf jeder Seite braucht.
struct AdminPage {
    string title;
    string active; // "dashboard", "sql" oder der Tabellenname
    string[] tables;
    bool locked; // eine offene Transaktion sperrt die Datenbank
    string replicaOf; // Quelle, wenn der Mandant ein schreibgeschütztes Ziel ist (nur für Administratoren ermittelt)
    string userName, roleLabel;
    string tenant; // Mandant des Benutzers
    bool canWrite, isAdmin;
    bool isSystem; // Systemadministrator: nur Mandanten, Benutzer des Systembereichs und das eigene Konto
    string ok;
    string err;
}

struct Cell {
    string text;
    bool isNull;
}

struct RowView {
    Cell[] cells;
    string match; // JSON-Array der Originalwerte, identifiziert die Zeile beim Bearbeiten und Löschen
}

struct ColumnInfo {
    string name;
    string type;
    string inputType;
    ColumnStats stats;
    string codeSize;
}

struct TableSummary {
    string name;
    string storage;
    size_t rows, deletedRows, deltaRows, columns;
    string codeSize;
}

struct DashboardView {
    TableSummary[] tables;
    size_t totalRows, totalDeleted, totalDelta;
    string totalSize;
    MergeStatus merge;
}

struct TableStatsView {
    TableSummary summary;
    ColumnInfo[] columns;
}

struct StatsView {
    DashboardView overview;
    TableStatsView[] tables;
    size_t totalColumns;
}

struct TableView {
    string name;
    string storage;
    ColumnInfo[] columns;
    RowView[] rows;
    size_t live, deleted, matching;
    size_t page = 1, pageCount = 1, pageSize = defaultPageSize;
    string where, sort;
    bool desc;
    string queryError;

    /// Query-String dieser Ansicht mit anderer Seite und Sortierung.
    string query(size_t toPage, string bySort, bool byDesc) const {
        string[] parts = ["page=" ~ toPage.to!string, "size=" ~ pageSize.to!string];
        if (bySort.length)
            parts ~= ["sort=" ~ urlEncode(bySort), "dir=" ~ (byDesc ? "desc" : "asc")];
        if (where.length)
            parts ~= "where=" ~ urlEncode(where);
        return parts.join("&");
    }

    string pageUrl(size_t toPage) const {
        return "?" ~ query(toPage, sort, desc);
    }

    /// Erster Klick sortiert aufsteigend, jeder weitere dreht die Richtung um.
    string sortUrl(string column) const {
        return "?" ~ query(1, column, icmp(sort, column) == 0 && !desc);
    }

    string sortMark(string column) const {
        return icmp(sort, column) != 0 ? "" : (desc ? " ▼" : " ▲");
    }

    string backQuery() const {
        return query(page, sort, desc);
    }

    string exportUrl() const {
        return "/admin/tables/" ~ name ~ "/export?" ~ query(1, sort, desc);
    }

    string consoleUrl() const {
        return "/admin/sql?q=" ~ urlEncode(selectSql(name, where, sort, desc, pageSize, 0));
    }

    size_t firstRow() const {
        return rows.length ? (page - 1) * pageSize + 1 : 0;
    }

    size_t lastRow() const {
        return rows.length ? (page - 1) * pageSize + rows.length : 0;
    }
}

struct UsersView {
    UserRow[] users;
    string[] roles;
}

struct UserRow {
    string name, role;
    bool active, self;
}

struct TenantRow {
    string name, label;
    bool active;
    size_t users;
}

struct BackupRow {
    string name, label, created, size;
    long tables, rows;
    bool readable;
    string kind;
}

struct ConsoleStatement {
    string sql;
    string[] columns;
    Cell[][] rows;
    size_t totalRows;
    long affected;
    string message;
    string error;
    string elapsed;
}

struct ConsoleView {
    string input;
    string transaction; // offene Transaktion dieser Konsole
    ConsoleStatement[] results;
}

private class TableNotFound : Exception {
    this(string msg) {
        super(msg);
    }
}

private enum size_t defaultPageSize = 50;
private enum size_t maxPageSize = 500;
private enum size_t maxConsoleRows = 500;

/// Eingehender Adapter: Administrationsoberfläche (HTML) -> ISqlUseCase.
/// Anmeldung und Rechte prüfen SecurityGate und der ISqlUseCase-Dekorator; hier wird nur noch dargestellt.
final class SqlAdminUi {
    private ISqlUseCase sql;
    private IAccessUseCase access;
    private IBackupUseCase backups;
    private ITenantUseCase tenants;
    private IReplicationUseCase replication;

    this(ISqlUseCase sql, IAccessUseCase access, IBackupUseCase backups, ITenantUseCase tenants,
        IReplicationUseCase replication) {
        this.replication = replication;
        this.sql = sql;
        this.access = access;
        this.backups = backups;
        this.tenants = tenants;
    }

    void register(URLRouter router) {
        // Systemadministratoren haben keine Daten: ihre Startseite ist die Mandantenliste
        router.any("/admin", &systemGuard);
        router.any("/admin/*", &systemGuard);
        router.get("/", &home);
        router.get("/admin/login", &loginPage);
        router.post("/admin/login", &login);
        router.post("/admin/logout", &logout);
        router.get("/admin/account", &account);
        router.post("/admin/account/password", &changePassword);
        router.get("/admin/users", &users);
        router.post("/admin/users", &createUser);
        router.post("/admin/users/:user/update", &updateUser);
        router.post("/admin/users/:user/password", &resetPassword);
        router.post("/admin/users/:user/delete", &deleteUser);
        router.get("/admin/tenants", &tenantList);
        router.post("/admin/tenants", &createTenant);
        router.post("/admin/tenants/:tenant/update", &updateTenant);
        router.post("/admin/tenants/:tenant/delete", &deleteTenant);
        router.get("/admin/replication", &replicationPage);
        router.post("/admin/replication", &configureReplica);
        router.post("/admin/replication/stop", &stopReplica);
        router.post("/admin/replication/resync", &resyncReplica);
        router.get("/admin/backups", &backupList);
        router.post("/admin/backups", &createBackup);
        router.post("/admin/backups/upload", &uploadBackup);
        router.post("/admin/backups/schedule", &updateSchedule);
        router.get("/admin/backups/:backup/download", &downloadBackup);
        router.post("/admin/backups/:backup/restore", &restoreBackup);
        router.post("/admin/backups/:backup/delete", &deleteBackup);
        router.get("/admin", &dashboard);
        router.get("/admin/stats", &statistics);
        router.get("/admin/help", &help);
        router.post("/admin/merge", &merge);
        router.post("/admin/checkpoint", &checkpoint);
        router.get("/admin/sql", &console);
        router.post("/admin/sql", &runConsole);
        router.post("/admin/tables", &createTable);
        router.get("/admin/tables/:name", &table);
        router.get("/admin/tables/:name/export", &exportCsv);
        router.post("/admin/tables/:name/rows", &insertRow);
        router.post("/admin/tables/:name/rows/update", &updateRow);
        router.post("/admin/tables/:name/rows/delete", &deleteRow);
        router.post("/admin/tables/:name/truncate", &truncateTable);
        router.post("/admin/tables/:name/drop", &dropTable);
    }

    private void home(HTTPServerRequest req, HTTPServerResponse res) {
        res.redirect("/admin");
    }

    private void systemGuard(HTTPServerRequest req, HTTPServerResponse res) {
        if (currentPrincipal().isSystem && isTenantDataPath(req.requestPath.toString))
            res.redirect("/admin/tenants");
    }

    private AdminPage pageFor(HTTPServerRequest req, string title, string active) {
        AdminPage p;
        p.title = title;
        p.active = active;
        p.ok = req.query.get("ok", "");
        p.err = req.query.get("err", "");
        auto me = currentPrincipal();
        p.userName = me.name;
        p.roleLabel = roleName(me.role);
        p.tenant = me.tenant;
        p.isSystem = me.isSystem;
        p.canWrite = !p.isSystem && me.role >= HdbRole.editor;
        p.isAdmin = me.role == HdbRole.admin;
        if (p.isSystem)
            return p;
        try
            p.tables = sql.listTables();
        catch (Exception)
            p.locked = true;
        if (p.isAdmin)
            try {
                auto status = replication.replicationStatus();
                if (status.replica)
                    p.replicaOf = status.url;
            } catch (Exception) {
            }
        return p;
    }

    private void renderError(HTTPServerRequest req, HTTPServerResponse res, HTTPStatus status, string message) {
        auto page = pageFor(req, "Error", "");
        page.err = message;
        res.statusCode = status;
        res.render!("error.dt", page);
    }

    /// Führt eine Änderung aus und leitet mit dem Ergebnis als Hinweis zurück (Post/Redirect/Get).
    /// `target` wird erst nach `work` ausgewertet, damit das Ziel vom Ergebnis abhängen kann.
    private void act(HTTPServerRequest req, HTTPServerResponse res, lazy string target, string delegate() work) {
        string query = req.form.get("back", "");
        if (query.any!(c => c == '\r' || c == '\n'))
            query = "";
        if (query.length)
            query ~= "&";
        try
            query ~= "ok=" ~ urlEncode(work());
        catch (HTTPStatusException e)
            throw e;
        catch (Exception e)
            query ~= "err=" ~ urlEncode(e.msg);
        res.redirect(target ~ "?" ~ query);
    }

    private void loginPage(HTTPServerRequest req, HTTPServerResponse res) {
        if (currentPrincipal().authenticated)
            return res.redirect("/admin");
        // feste Texte statt Query-Inhalt: die Seite ist öffentlich und soll keine fremden Nachrichten anzeigen
        string loginError;
        string loginNotice = "changed" in req.query ? "Password changed. Please sign in again." : "";
        string tenantValue = req.cookies.get(tenantCookie, "");
        if (!isPlainTenant(tenantValue))
            tenantValue = "";
        res.render!("login.dt", loginError, loginNotice, tenantValue);
    }

    private void login(HTTPServerRequest req, HTTPServerResponse res) {
        LoginResult session;
        string tenantValue = req.form.get("tenant", "").strip;
        try
            session = access.login(tenantValue, req.form.get("user", ""), req.form.get("password", ""));
        catch (AuthenticationRequired e) {
            string loginError = e.msg;
            string loginNotice;
            res.statusCode = HTTPStatus.unauthorized;
            return res.render!("login.dt", loginError, loginNotice, tenantValue);
        }
        // Nur zum Vorausfüllen des Formulars, kein Geheimnis
        auto remembered = res.setCookie(tenantCookie, session.principal.tenant, "/admin", Cookie.Encoding.none);
        remembered.httpOnly = true;
        remembered.sameSite = Cookie.SameSite.strict;
        remembered.maxAge = 365 * 24 * 3600;
        auto cookie = res.setCookie(sessionCookie, session.token, "/admin", Cookie.Encoding.none);
        cookie.httpOnly = true;
        cookie.sameSite = Cookie.SameSite.strict;
        cookie.maxAge = session.expiresInSeconds;
        cookie.secure = req.tls || req.headers.get("X-Forwarded-Proto", "") == "https";
        res.redirect("/admin");
    }

    private void logout(HTTPServerRequest req, HTTPServerResponse res) {
        access.logout(req.cookies.get(sessionCookie, ""));
        res.setCookie(sessionCookie, null, "/admin");
        res.redirect("/admin/login");
    }

    private void account(HTTPServerRequest req, HTTPServerResponse res) {
        auto page = pageFor(req, "My account", "account");
        res.render!("account.dt", page);
    }

    /// Ein neues Passwort beendet alle Sitzungen, auch diese.
    private void changePassword(HTTPServerRequest req, HTTPServerResponse res) {
        try
            access.changeOwnPassword(currentPrincipal(), req.form.get("current", ""), matchingPasswords(req));
        catch (Exception e)
            return res.redirect("/admin/account?err=" ~ urlEncode(e.msg));
        res.setCookie(sessionCookie, null, "/admin");
        res.redirect("/admin/login?changed=1");
    }

    private void tenantList(HTTPServerRequest req, HTTPServerResponse res) {
        TenantRow[] rows;
        try {
            foreach (t; tenants.listTenants(currentPrincipal()))
                rows ~= TenantRow(t.name, t.label, t.active, t.users);
        } catch (AccessDenied e)
            return renderError(req, res, HTTPStatus.forbidden, e.msg);
        auto page = pageFor(req, "Tenants", "tenants");
        res.render!("tenants.dt", page, rows);
    }

    private void createTenant(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/tenants", {
            auto t = tenants.createTenant(currentPrincipal(), req.form.get("tenant", ""), req.form.get("label", ""),
                req.form.get("user", ""), matchingPasswords(req));
            return "Tenant " ~ t.name ~ " created";
        });
    }

    private void updateTenant(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/tenants", {
            auto t = tenants.updateTenant(currentPrincipal(), req.params["tenant"], req.form.get("label", ""),
                req.form.get("active", "") == "1");
            return "Tenant " ~ t.name ~ (t.active ? " updated" : " deactivated. All its sessions have ended.");
        });
    }

    private void deleteTenant(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/tenants", {
            tenants.deleteTenant(currentPrincipal(), req.params["tenant"]);
            return "Tenant " ~ req.params["tenant"] ~ " deleted";
        });
    }

    private void users(HTTPServerRequest req, HTTPServerResponse res) {
        auto me = currentPrincipal();
        UsersView view;
        try {
            foreach (u; access.listUsers(me))
                view.users ~= UserRow(u.name, roleName(u.role), u.active, u.name == me.name);
        } catch (AccessDenied e)
            return renderError(req, res, HTTPStatus.forbidden, e.msg);
        view.roles = [roleName(HdbRole.viewer), roleName(HdbRole.editor), roleName(HdbRole.admin)];
        auto page = pageFor(req, "Users", "users");
        res.render!("users.dt", page, view);
    }

    private void createUser(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/users", {
            auto u = access.createUser(currentPrincipal(), req.form.get("user", ""), matchingPasswords(req),
                parseRole(req.form.get("role", "")));
            return "HdbUser " ~ u.name ~ " created";
        });
    }

    private void updateUser(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/users", {
            auto u = access.updateUser(currentPrincipal(), req.params["user"], parseRole(req.form.get("role", "")),
                req.form.get("active", "") == "1");
            return "HdbUser " ~ u.name ~ " updated";
        });
    }

    private void resetPassword(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/users", {
            access.resetPassword(currentPrincipal(), req.params["user"], matchingPasswords(req));
            return "Password reset for " ~ req.params["user"];
        });
    }

    private void deleteUser(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/users", {
            access.deleteUser(currentPrincipal(), req.params["user"]);
            return "HdbUser " ~ req.params["user"] ~ " deleted";
        });
    }

    private void replicationPage(HTTPServerRequest req, HTTPServerResponse res) {
        ReplicationStatus status;
        try
            status = replication.replicationStatus();
        catch (AccessDenied e)
            return renderError(req, res, HTTPStatus.forbidden, e.msg);
        auto page = pageFor(req, "Replication", "replication");
        res.render!("replication.dt", page, status);
    }

    private void configureReplica(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/replication", {
            ReplicationConfig config;
            config.url = req.form.get("url", "");
            config.tenant = req.form.get("tenant", "");
            config.user = req.form.get("user", "");
            config.password = req.form.get("password", "");
            try
                config.intervalSeconds = req.form.get("interval", "2").to!int;
            catch (Exception)
                throw new Exception("The interval must be a whole number of seconds");
            replication.configureReplica(config);
            return "Replication started. The first run replaces all tables of this tenant.";
        });
    }

    private void stopReplica(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/replication", {
            replication.stopReplica();
            return "Replication stopped. This tenant keeps its data and accepts changes again.";
        });
    }

    private void resyncReplica(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/replication", {
            replication.resyncReplica();
            return "A full sync starts with the next run";
        });
    }

    private void backupList(HTTPServerRequest req, HTTPServerResponse res) {
        BackupRow[] rows;
        BackupSchedule schedule;
        try {
            foreach (b; backups.list())
                rows ~= BackupRow(b.name, b.label, b.created, humanSize(b.size), b.tables, b.rows, b.readable, b.kind);
            schedule = backups.schedule();
        } catch (AccessDenied e)
            return renderError(req, res, HTTPStatus.forbidden, e.msg);
        auto page = pageFor(req, "Backups", "backups");
        res.render!("backups.dt", page, rows, schedule);
    }

    private void updateSchedule(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/backups", {
            backups.updateSchedule(req.form.get("enabled", "") == "1", req.form.get("intervalHours", "").to!int,
                req.form.get("keepScheduled", "").to!int, req.form.get("keepSafety", "").to!int);
            return "Schedule saved";
        });
    }

    private void createBackup(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/backups", () => "Backup " ~ backups.create(req.form.get("label", "")).name ~ " created");
    }

    private void uploadBackup(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/backups", {
            requireRole(currentPrincipal(), HdbRole.admin); // vor dem Lesen der Datei
            auto file = "file" in req.files;
            enforce(file !is null, "Choose a backup file");
            return "Backup " ~ backups.upload(readText(file.tempPath.toString)).name ~ " uploaded";
        });
    }

    private void downloadBackup(HTTPServerRequest req, HTTPServerResponse res) {
        string content;
        try
            content = backups.download(req.params["backup"]);
        catch (AccessDenied e)
            return renderError(req, res, HTTPStatus.forbidden, e.msg);
        catch (BackupNotFound e)
            return renderError(req, res, HTTPStatus.notFound, e.msg);
        res.headers["Content-Disposition"] = `attachment; filename="` ~ req.params["backup"] ~ `"`;
        res.writeBody(content, "application/octet-stream");
    }

    private void restoreBackup(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/backups", {
            auto safety = backups.restore(req.params["backup"]);
            return "Database restored. The previous state is saved as " ~ safety.name;
        });
    }

    private void deleteBackup(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin/backups", {
            backups.remove(req.params["backup"]);
            return "Backup deleted";
        });
    }

    private void dashboard(HTTPServerRequest req, HTTPServerResponse res) {
        auto page = pageFor(req, "Dashboard", "dashboard");
        DashboardView view;
        view.merge = sql.mergeStatus();
        try
            addTotals(view, sql.stats());
        catch (Exception e)
            page.err = e.msg;
        res.render!("dashboard.dt", page, view);
    }

    private void statistics(HTTPServerRequest req, HTTPServerResponse res) {
        auto page = pageFor(req, "Statistics", "stats");
        StatsView view;
        view.overview.merge = sql.mergeStatus();
        try {
            auto all = sql.stats();
            addTotals(view.overview, all);
            foreach (i, t; all) {
                view.tables ~= TableStatsView(view.overview.tables[i], t.columns.map!(c => columnInfo(c)).array);
                view.totalColumns += t.columns.length;
            }
        } catch (Exception e)
            page.err = e.msg;
        res.render!("stats.dt", page, view);
    }

    private void help(HTTPServerRequest req, HTTPServerResponse res) {
        auto page = pageFor(req, "Help", "help");
        res.render!("help.dt", page);
    }

    private void merge(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin", () => sql.mergeDeltaAsync() ? "Delta merge started" : "A delta merge is already running");
    }

    private void checkpoint(HTTPServerRequest req, HTTPServerResponse res) {
        act(req, res, "/admin", {
            sql.checkpoint();
            return "Checkpoint written";
        });
    }

    private void createTable(HTTPServerRequest req, HTTPServerResponse res) {
        string target = "/admin";
        act(req, res, target, {
            auto name = req.form.get("table", "").strip;
            auto stmt = createTableSql(name, req.form.getAll("col_name"), req.form.getAll("col_type"),
                req.form.get("storage", ""));
            sql.execute(stmt);
            target = "/admin/tables/" ~ name.toLower;
            return "Table " ~ name ~ " created";
        });
    }

    private void table(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        TableStats stats;
        try
            stats = statsOf(name);
        catch (TableNotFound e)
            return renderError(req, res, HTTPStatus.notFound, e.msg);
        catch (Exception e)
            return renderError(req, res, HTTPStatus.conflict, e.msg); // gesperrt

        auto page = pageFor(req, stats.table, stats.table.toLower);
        TableView view;
        view.name = stats.table.toLower;
        view.storage = storageName(stats.storage);
        view.live = stats.rows;
        view.deleted = stats.deletedRows;
        view.columns = stats.columns.map!(columnInfo).array;
        view.where = req.query.get("where", "").strip;
        view.pageSize = min(max(numberParam(req, "size", defaultPageSize), 1), maxPageSize);
        view.desc = req.query.get("dir", "") == "desc";
        auto sort = req.query.get("sort", "");
        if (stats.columns.any!(c => icmp(c.name, sort) == 0))
            view.sort = sort;

        try {
            auto count = "SELECT COUNT(*) FROM " ~ view.name
                ~ (view.where.length ? " WHERE " ~ view.where : "");
            view.matching = sql.execute(count).rows[0][0].get!long.to!size_t;
            view.pageCount = max(1, (view.matching + view.pageSize - 1) / view.pageSize);
            view.page = min(max(numberParam(req, "page", 1), 1), view.pageCount);
            auto r = sql.execute(selectSql(view.name, view.where, view.sort, view.desc,
                view.pageSize, (view.page - 1) * view.pageSize));
            view.rows = r.rows.map!(rowView).array;
        } catch (Exception e)
            view.queryError = e.msg;
        res.render!("table_view.dt", page, view);
    }

    private void exportCsv(HTTPServerRequest req, HTTPServerResponse res) {
        string name, csv;
        try {
            name = tableParam(req);
            auto stats = statsOf(name);
            auto sort = req.query.get("sort", "");
            if (!stats.columns.any!(c => icmp(c.name, sort) == 0))
                sort = "";
            auto r = sql.execute(selectSql(name, req.query.get("where", "").strip, sort,
                req.query.get("dir", "") == "desc", 0, 0));
            csv = toCsv(r.columns, r.rows);
        } catch (Exception e)
            return renderError(req, res, HTTPStatus.badRequest, e.msg);
        res.headers["Content-Disposition"] = `attachment; filename="` ~ name ~ `.csv"`;
        res.writeBody(csv, "text/csv; charset=utf-8");
    }

    private void insertRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        act(req, res, tablePath(name), {
            auto cols = statsOf(name).columns;
            sql.execute("INSERT INTO " ~ name ~ " VALUES (" ~ formLiterals(req, cols).join(", ") ~ ")");
            return "Row inserted";
        });
    }

    private void updateRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        act(req, res, tablePath(name), {
            auto cols = statsOf(name).columns;
            auto lits = formLiterals(req, cols);
            string[] assignments;
            foreach (i, c; cols)
                assignments ~= c.name ~ " = " ~ lits[i];
            auto r = sql.execute("UPDATE " ~ name ~ " SET " ~ assignments.join(", ")
                ~ " WHERE " ~ rowPredicate(cols, req.form.get("match", "")));
            return rowCount(r.affected) ~ " updated";
        });
    }

    private void deleteRow(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        act(req, res, tablePath(name), {
            auto cols = statsOf(name).columns;
            auto r = sql.execute("DELETE FROM " ~ name ~ " WHERE " ~ rowPredicate(cols, req.form.get("match", "")));
            return rowCount(r.affected) ~ " deleted";
        });
    }

    private void truncateTable(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        act(req, res, tablePath(name), () => rowCount(sql.execute("DELETE FROM " ~ name).affected) ~ " deleted");
    }

    private void dropTable(HTTPServerRequest req, HTTPServerResponse res) {
        auto name = tableParam(req);
        act(req, res, "/admin", {
            sql.execute("DROP TABLE " ~ name);
            return "Table " ~ name ~ " dropped";
        });
    }

    private void console(HTTPServerRequest req, HTTPServerResponse res) {
        auto page = pageFor(req, "SQL Console", "sql");
        ConsoleView view;
        view.input = req.query.get("q", "");
        res.render!("sql_console.dt", page, view);
    }

    /// Führt die Anweisungen nacheinander aus und stoppt beim ersten Fehler.
    /// Die Transaktions-Id wandert im Formular mit, damit BEGIN auch über mehrere Aufrufe trägt.
    private void runConsole(HTTPServerRequest req, HTTPServerResponse res) {
        ConsoleView view;
        view.input = req.form.get("statement", "");
        view.transaction = req.form.get("transaction", "");
        foreach (stmt; splitStatements(view.input)) {
            ConsoleStatement item;
            item.sql = stmt;
            immutable verb = stmt.toUpper;
            immutable ends = verb.startsWith("COMMIT") || verb.startsWith("ROLLBACK");
            immutable begin = MonoTime.currTime;
            try {
                auto r = sql.executeIn(view.transaction, stmt);
                item.columns = r.columns;
                item.totalRows = r.rows.length;
                item.rows = r.rows[0 .. min(r.rows.length, maxConsoleRows)]
                    .map!(row => row.map!(cell).array).array;
                item.affected = r.affected;
                item.message = r.message;
                if (r.transaction.length)
                    view.transaction = r.transaction;
            } catch (Exception e)
                item.error = e.msg;
            item.elapsed = format("%.2f ms", (MonoTime.currTime - begin).total!"usecs" / 1000.0);
            if (ends)
                view.transaction = ""; // auch im Fehlerfall: die Transaktion ist dann abgelaufen oder beendet
            view.results ~= item;
            if (item.error.length)
                break;
        }
        auto page = pageFor(req, "SQL Console", "sql");
        res.render!("sql_console.dt", page, view);
    }

    private TableStats statsOf(string name) {
        foreach (t; sql.stats())
            if (icmp(t.table, name) == 0)
                return t;
        throw new TableNotFound("Table not found: " ~ name);
    }
}

private enum tenantCookie = "hdb_tenant";

/// Seiten mit Mandantendaten. Systemadministratoren werden von dort zur Mandantenliste geleitet.
bool isTenantDataPath(string path) @safe {
    import std.algorithm : any;

    if (path == "/admin")
        return true;
    return ["/admin/stats", "/admin/sql", "/admin/merge", "/admin/checkpoint", "/admin/tables", "/admin/backups",
        "/admin/replication"]
        .any!(p => path == p || path.startsWith(p ~ "/"));
}

/// Was aus dem Cookie ins Formular darf: nur, was ein Mandantenname sein kann.
private bool isPlainTenant(string value) {
    try
        return value.length == 0 || validTenantName(value) == value;
    catch (Exception)
        return false;
}

private string matchingPasswords(HTTPServerRequest req) {
    auto password = req.form.get("password", "");
    enforce(password == req.form.get("confirm", ""), "Passwords do not match");
    return password;
}

private string tablePath(string name) {
    return "/admin/tables/" ~ name;
}

private string tableParam(HTTPServerRequest req) {
    auto name = req.params["name"];
    if (!isIdentifier(name))
        throw new HTTPStatusException(HTTPStatus.notFound, "Invalid table name");
    return name.toLower;
}

private size_t numberParam(HTTPServerRequest req, string key, size_t fallback) {
    try
        return req.query.get(key, "").to!size_t;
    catch (Exception)
        return fallback;
}

/// Literale aus den Formularfeldern v0, v1, ...; das Feld n<i> steht für NULL.
private string[] formLiterals(HTTPServerRequest req, ColumnStats[] cols) {
    string[] lits;
    foreach (i, c; cols) {
        auto key = i.to!string;
        lits ~= req.form.get("n" ~ key, "").length ? "NULL"
            : toSqlLiteral(valueFromInput(c.type, req.form.get("v" ~ key, "")));
    }
    return lits;
}

private string rowCount(long n) {
    return n.to!string ~ (n == 1 ? " row" : " rows");
}

/// Kennzahlen je Tabelle und Summen für Dashboard und Statistik.
private void addTotals(ref DashboardView view, TableStats[] all) {
    size_t totalBytes;
    foreach (t; all) {
        auto s = summarize(t);
        view.tables ~= s;
        view.totalRows += s.rows;
        view.totalDeleted += s.deletedRows;
        view.totalDelta += s.deltaRows;
        foreach (c; t.columns)
            totalBytes += c.mainCodeBytes;
    }
    view.totalSize = humanSize(totalBytes);
}

private TableSummary summarize(TableStats t) {
    TableSummary s;
    s.name = t.table.toLower;
    s.storage = storageName(t.storage);
    s.rows = t.rows;
    s.deletedRows = t.deletedRows;
    s.columns = t.columns.length;
    size_t bytes;
    foreach (c; t.columns) {
        s.deltaRows = max(s.deltaRows, c.deltaRows);
        bytes += c.mainCodeBytes;
    }
    s.codeSize = humanSize(bytes);
    return s;
}

private ColumnInfo columnInfo(ColumnStats c) {
    return ColumnInfo(c.name, typeName(c.type), inputTypeOf(c.type), c, humanSize(c.mainCodeBytes));
}

private string inputTypeOf(ColumnType type) {
    return isIntegerType(type) ? "integer" : isNumeric(type) ? "number" : "text";
}

private Cell cell(Value v) {
    return Cell(valueText(v), isNull(v));
}

private RowView rowView(Value[] row) {
    auto match = Json.emptyArray;
    foreach (v; row)
        match ~= isNull(v) ? Json(null) : Json(valueText(v));
    return RowView(row.map!(cell).array, match.toString());
}

string humanSize(size_t bytes) {
    if (bytes < 1024)
        return bytes.to!string ~ " B";
    if (bytes < 1024 * 1024)
        return format("%.1f KB", bytes / 1024.0);
    return format("%.1f MB", bytes / (1024.0 * 1024.0));
}

bool isIdentifier(string s) {
    return s.length > 0 && s.all!(c => isAlphaNum(c) || c == '_');
}

/// SELECT für die Tabellenansicht; limit 0 liest alle Zeilen (CSV-Export).
string selectSql(string table, string where, string sort, bool desc, size_t limit, size_t offset) {
    auto s = "SELECT * FROM " ~ table;
    if (where.length)
        s ~= " WHERE " ~ where;
    if (sort.length)
        s ~= " ORDER BY " ~ sort ~ (desc ? " DESC" : " ASC");
    if (limit)
        s ~= " LIMIT " ~ limit.to!string ~ " OFFSET " ~ offset.to!string;
    return s;
}

string createTableSql(string name, const(string)[] columns, const(string)[] types, string storage = "") {
    enforce(isIdentifier(name), "Invalid table name: " ~ name);
    enforce(columns.length == types.length, "Column names and types do not match");
    string[] seen, defs;
    foreach (i, raw; columns) {
        auto column = raw.strip;
        if (column.length == 0)
            continue; // leere Zeile im Formular
        enforce(isIdentifier(column), "Invalid column name: " ~ column);
        enforce(!seen.canFind(column.toLower), "Duplicate column: " ~ column);
        ColumnType type;
        try
            type = columnTypeOf(types[i]);
        catch (Exception)
            throw new Exception("Invalid column type: " ~ types[i]);
        seen ~= column.toLower;
        defs ~= column ~ " " ~ typeName(type); // nie die Eingabe: VARCHAR); DROP gilt sonst auch als VARCHAR
    }
    enforce(defs.length, "A table needs at least one column");
    immutable target = storage.length ? parseStorage(storage) : TableStorage.memory;
    return "CREATE TABLE " ~ name ~ " (" ~ defs.join(", ") ~ ")"
        ~ (target == TableStorage.memory ? "" : " USING " ~ storageName(target));
}

/// WHERE-Bedingung aus dem JSON-Array der Originalwerte. Tabellen haben keinen Primärschlüssel,
/// daher trifft sie alle Zeilen mit genau diesen Werten.
string rowPredicate(ColumnStats[] cols, string matchJson) {
    auto values = parseJsonString(matchJson);
    enforce(values.type == Json.Type.array && values.length == cols.length, "Row does not match the table");
    string[] parts;
    foreach (i, c; cols) {
        auto v = values[i];
        parts ~= v.type == Json.Type.null_ ? c.name ~ " IS NULL"
            : c.name ~ " = " ~ toSqlLiteral(valueFromInput(c.type, v.get!string));
    }
    return parts.join(" AND ");
}

/// Trennt an Semikolons außerhalb von 'Textliteralen'.
string[] splitStatements(string text) {
    string[] result;
    size_t start;
    bool quoted;
    foreach (i, char c; text) {
        if (c == '\'')
            quoted = !quoted;
        else if (c == ';' && !quoted) {
            result ~= text[start .. i];
            start = i + 1;
        }
    }
    result ~= text[start .. $];
    string[] statements;
    foreach (s; result)
        if (s.strip.length)
            statements ~= s.strip;
    return statements;
}

string toCsv(string[] columns, Value[][] rows) {
    string quote(string s) {
        return `"` ~ s.replace(`"`, `""`) ~ `"`;
    }

    auto csv = columns.map!(quote).join(",") ~ "\r\n";
    foreach (row; rows)
        csv ~= row.map!(v => isNull(v) ? "" : quote(valueText(v))).join(",") ~ "\r\n";
    return csv;
}

unittest {
    import std.exception : assertThrown;

    assert(splitStatements("BEGIN; INSERT INTO t VALUES ('a;b', 'it''s;'); COMMIT;")
        == ["BEGIN", "INSERT INTO t VALUES ('a;b', 'it''s;')", "COMMIT"]);
    assert(splitStatements(" ; ").length == 0);

    assert(createTableSql("t", ["id", " ", "n"], ["INTEGER", "INTEGER", "VARCHAR"])
        == "CREATE TABLE t (id INTEGER, n VARCHAR)");
    assertThrown(createTableSql("t; x", ["a"], ["INTEGER"]));
    assertThrown(createTableSql("t", ["a) --"], ["INTEGER"]));
    assertThrown(createTableSql("t", ["a"], ["INTEGER); DROP"]));
    assertThrown(createTableSql("t", ["a", "A"], ["INTEGER", "INTEGER"]));
    assertThrown(createTableSql("t", [""], ["INTEGER"]));
    assert(createTableSql("t", ["a"], ["INTEGER"], "memory") == "CREATE TABLE t (a INTEGER)");
    assert(createTableSql("t", ["a"], ["INTEGER"], "File") == "CREATE TABLE t (a INTEGER) USING FILE");
    assert(createTableSql("t", ["a"], ["INTEGER"], "JSON") == "CREATE TABLE t (a INTEGER) USING JSON");
    assertThrown(createTableSql("t", ["a"], ["INTEGER"], "FILE; DROP"));

    ColumnStats id, text;
    id.name = "id";
    id.type = ColumnType.integer;
    text.name = "n";
    text.type = ColumnType.text;
    assert(rowPredicate([id, text], `["1","it's"]`) == "id = 1 AND n = 'it''s'");
    assert(rowPredicate([id, text], `[null,null]`) == "id IS NULL AND n IS NULL");
    assertThrown(rowPredicate([id, text], `["1"]`));
    assertThrown(rowPredicate([id, text], `["1 OR 1=1","x"]`));

    assert(toCsv(["a", "b"], [[Value(1L), nullValue], [Value(`x"y`), Value(1.5)]])
        == "\"a\",\"b\"\r\n\"1\",\r\n\"x\"\"y\",\"1.5\"\r\n");

    assert(selectSql("t", "a = 1", "b", true, 10, 20) == "SELECT * FROM t WHERE a = 1 ORDER BY b DESC LIMIT 10 OFFSET 20");
    assert(selectSql("t", "", "", false, 0, 0) == "SELECT * FROM t");

    assert(humanSize(512) == "512 B" && humanSize(2048) == "2.0 KB");

    assert(isTenantDataPath("/admin") && isTenantDataPath("/admin/sql") && isTenantDataPath("/admin/tables/t/rows"));
    assert(isTenantDataPath("/admin/backups/x.hdbbak/download") && isTenantDataPath("/admin/merge"));
    assert(!isTenantDataPath("/admin/tenants") && !isTenantDataPath("/admin/users") && !isTenantDataPath("/admin/account"));
    assert(!isTenantDataPath("/admin/login") && !isTenantDataPath("/admin/help") && !isTenantDataPath("/admin/sqlx"));
    assert(isPlainTenant("") && isPlainTenant("acme") && !isPlainTenant("<x>") && !isPlainTenant("ACME"));
}
