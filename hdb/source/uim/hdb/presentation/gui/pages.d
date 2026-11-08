/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Die Seiten des Admin-Clients. Jede zeigt nur, was die Rechte der Anmeldung erlauben; geprüft wird trotzdem
/// immer auf dem Server.
module uim.hdb.presentation.gui.pages;

import uim.hdb.presentation.gui.api;
import uim.hdb.presentation.gui.widgets;
import std.algorithm : canFind, filter, map, sort;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import std.string : strip;
import gtk.Box;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Entry;
import gtk.Label;
import gtk.ListBox;
import gtk.ListBoxRow;
import gtk.Paned;
import gtk.ScrolledWindow;
import gtk.TextView;
import gtk.TreePath;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.Widget;
import gtk.Window;
import gdk.Event;
import gtk.c.types : Orientation, PolicyType;
import gdk.c.types : GdkEventKey, GdkModifierType;

/// Was alle Seiten brauchen.
abstract class Page {
    protected HdbClient client;
    protected Window window;
    protected void delegate() signedOut;

    this(HdbClient client, Window window, void delegate() signedOut) {
        this.client = client;
        this.window = window;
        this.signedOut = signedOut;
    }

    abstract Widget widget();
    abstract string title();

    /// Lädt die Daten neu; beim Öffnen der Seite und über den Aktualisieren-Knopf.
    abstract void refresh();

    protected bool run(void delegate() action) {
        return guarded(window, action, signedOut);
    }
}

/// Tabellen: Liste links, Zeilen rechts mit WHERE-Filter und Seiten.
final class TablesPage : Page {
    private enum pageSize = 100;
    private Paned paned;
    private ListBox list;
    private DataGrid grid;
    private Entry where;
    private Label status;
    private string table;
    private long offset, total;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        list = new ListBox();
        list.addOnRowSelected((ListBoxRow row, ListBox _) {
            if (row is null)
                return;
            table = (cast(Label) row.getChild()).getText();
            offset = 0;
            loadRows();
        });
        auto left = new ScrolledWindow();
        left.setPolicy(PolicyType.NEVER, PolicyType.AUTOMATIC);
        left.add(list);
        left.setSizeRequest(200, -1);

        where = new Entry();
        where.setPlaceholderText("WHERE condition, e.g. amount >= 10 AND name LIKE 'A%'");
        where.setHexpand(true);
        where.addOnActivate((Entry _) { offset = 0; loadRows(); });
        status = new Label("Select a table");
        status.setXalign(0);
        auto bar = toolbar();
        bar.packStart(where, true, true, 0);
        bar.packStart(button("Filter", { offset = 0; loadRows(); }), false, false, 0);
        bar.packStart(button("◀", { if (offset >= pageSize) { offset -= pageSize; loadRows(); } }), false, false, 0);
        bar.packStart(button("▶", { if (offset + pageSize < total) { offset += pageSize; loadRows(); } }), false, false, 0);

        grid = new DataGrid();
        auto right = pageBox();
        right.packStart(bar, false, false, 0);
        right.packStart(grid.widget, true, true, 0);
        right.packStart(status, false, false, 0);

        paned = new Paned(Orientation.HORIZONTAL);
        paned.pack1(left, false, false);
        paned.pack2(right, true, false);
    }

    override Widget widget() {
        return paned;
    }

    override string title() {
        return "Tables";
    }

    override void refresh() {
        run({
            foreach (child; childrenOf(list))
                list.remove(child);
            auto names = client.tables();
            foreach (name; names) {
                auto label = new Label(name);
                label.setXalign(0);
                label.setMarginStart(8);
                label.setMarginTop(4);
                label.setMarginBottom(4);
                list.add(label);
            }
            list.showAll();
            if (!names.canFind(table)) {
                table = "";
                grid.clear();
                status.setText(names.length ? "Select a table" : "No tables you can see");
            } else
                loadRows();
        });
    }

    private void loadRows() {
        if (table.length == 0)
            return;
        run({
            auto page = client.rows(table, where.getText(), pageSize, offset);
            total = page.total;
            grid.show(page);
            status.setText(page.rows.length
                ? format("%s: rows %s to %s of %s", table, offset + 1, offset + page.rows.length, total)
                : format("%s: no rows found", table));
        });
    }
}

/// SQL-Konsole: Anweisung oben, Ergebnis unten, Strg+Enter führt aus. Eine mit BEGIN begonnene Transaktion gilt für
/// die folgenden Anweisungen, bis COMMIT oder ROLLBACK.
final class ConsolePage : Page {
    private Box box;
    private TextView input;
    private DataGrid grid;
    private Label status;
    private string transaction;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        input = new TextView();
        input.setMonospace(true);
        input.setWrapMode(GtkWrapMode.WORD_CHAR);
        input.getBuffer().setText("SELECT * FROM ");
        input.addOnKeyPress((GdkEventKey* e, Widget _) {
            immutable enter = e.keyval == 0xff0d || e.keyval == 0xff8d; // Return, KP_Enter
            if (enter && (e.state & GdkModifierType.CONTROL_MASK)) {
                execute();
                return true;
            }
            return false;
        });
        auto scroller = new ScrolledWindow();
        scroller.add(input);
        scroller.setSizeRequest(-1, 120);

        status = new Label("Ctrl+Enter runs the statement.");
        status.setXalign(0);
        status.setSelectable(true);
        status.setLineWrap(true);
        auto bar = toolbar();
        bar.packStart(button("Run", &execute), false, false, 0);
        bar.packStart(status, true, true, 0);

        grid = new DataGrid();
        box = pageBox();
        box.packStart(scroller, false, true, 0);
        box.packStart(bar, false, false, 0);
        box.packStart(grid.widget, true, true, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "SQL Console";
    }

    override void refresh() {
    }

    private void execute() {
        auto buffer = input.getBuffer();
        auto statement = buffer.getText().strip;
        if (statement.length == 0)
            return;
        bool ok = run({
            auto result = client.sql(statement, transaction);
            if (result.transaction.length)
                transaction = result.transaction;
            auto verb = statement.length >= 6 ? statement[0 .. 6] : statement;
            import std.uni : toUpper;

            if (["COMMIT", "ROLLBA"].canFind(verb.toUpper))
                transaction = "";
            grid.show(result.grid);
            auto text = result.message.length ? result.message
                : result.grid.columns.length ? format("%s row(s)", result.grid.rows.length)
                : format("%s row(s) affected", result.affected);
            status.setText(transaction.length ? text ~ " · transaction open" : text);
        });
        if (!ok) {
            grid.clear(); // kein altes Ergebnis neben einer neuen Fehlermeldung
            status.setText("Failed");
        }
    }
}

private import gtk.c.types : GtkWrapMode;

/// Statistik aller sichtbaren Tabellen.
final class StatsPage : Page {
    private Box box;
    private DataGrid grid;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        grid = new DataGrid();
        box = pageBox();
        box.packStart(grid.widget, true, true, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "Statistics";
    }

    override void refresh() {
        run({
            Grid g;
            g.columns = ["Table", "Storage", "Live rows", "Deleted rows", "Columns"];
            foreach (t; client.stats())
                g.rows ~= [t.table, t.storage, t.rows.to!string, t.deletedRows.to!string, t.columns.to!string];
            grid.show(g);
        });
    }
}

/// Benutzer des eigenen Bereichs (Recht manageAccess).
final class UsersPage : Page {
    private Box box;
    private DataGrid grid;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        auto bar = toolbar();
        bar.packStart(button("New user", &create), false, false, 0);
        bar.packStart(button("Change role", &changeRole), false, false, 0);
        bar.packStart(button("Enable / disable", &toggle), false, false, 0);
        bar.packStart(button("Reset password", &resetPassword), false, false, 0);
        bar.packStart(button("Delete", &remove), false, false, 0);
        grid = new DataGrid();
        box = pageBox();
        box.packStart(bar, false, false, 0);
        box.packStart(grid.widget, true, true, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "Users";
    }

    override void refresh() {
        run({
            Grid g;
            g.columns = ["User", "Role", "Status", "Additional roles"];
            foreach (u; client.users())
                g.rows ~= [u.name, u.role.length ? u.role : "(none)", u.active ? "Active" : "Disabled", u.grants.to!string];
            grid.show(g);
        });
    }

    private string selectedUser() {
        auto name = grid.selected("User");
        if (name.length == 0)
            showMessage(window, "Select a user first.", false);
        return name;
    }

    private string[] roleChoices() {
        string[] roles;
        run({ roles = client.roles(); });
        return client.me.isSystem ? roles : roles ~ "(none)";
    }

    private void create() {
        auto form = new FormDialog(window, "New user", "Create");
        form.text("name", "User name").choice("role", "Role", roleChoices(), "viewer")
            .text("password", "Password", "", true).text("confirm", "Repeat password", "", true)
            .note("At least 12 characters.");
        scope (exit)
            form.close();
        if (!form.run())
            return;
        if (form["password"] != form["confirm"])
            return showMessage(window, "The passwords don't match.");
        if (run({ client.createUser(form["name"], form["password"], roleValue(form["role"])); }))
            refresh();
    }

    private void changeRole() {
        auto name = selectedUser();
        if (name.length == 0)
            return;
        auto form = new FormDialog(window, "Role of " ~ name, "Save");
        form.choice("role", "Role", roleChoices(), grid.selected("Role"))
            .flag("active", "Active", grid.selected("Status") == "Active");
        scope (exit)
            form.close();
        if (form.run() && run({ client.updateUser(name, roleValue(form["role"]), form.checked("active")); }))
            refresh();
    }

    private void toggle() {
        auto name = selectedUser();
        if (name.length == 0)
            return;
        immutable active = grid.selected("Status") != "Active";
        if (run({ client.updateUser(name, roleValue(grid.selected("Role")), active); }))
            refresh();
    }

    private void resetPassword() {
        auto name = selectedUser();
        if (name.length == 0)
            return;
        auto form = new FormDialog(window, "Reset password of " ~ name, "Reset");
        form.text("password", "New password", "", true).text("confirm", "Repeat password", "", true)
            .note("This signs the user out everywhere.");
        scope (exit)
            form.close();
        if (!form.run())
            return;
        if (form["password"] != form["confirm"])
            return showMessage(window, "The passwords don't match.");
        if (run({ client.resetPassword(name, form["password"]); }))
            showMessage(window, "Password reset for " ~ name ~ ".", false);
    }

    private void remove() {
        auto name = selectedUser();
        if (name.length && confirm(window, "Delete user " ~ name ~ "?") && run({ client.deleteUser(name); }))
            refresh();
    }

    private static string roleValue(string shown) {
        return shown == "(none)" ? "" : shown;
    }
}

/// Sicherungen des Mandanten (Recht manageBackups).
final class BackupsPage : Page {
    private Box box;
    private DataGrid grid;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        auto bar = toolbar();
        bar.packStart(button("Create backup", &create), false, false, 0);
        bar.packStart(button("Restore", &restore), false, false, 0);
        bar.packStart(button("Delete", &remove), false, false, 0);
        grid = new DataGrid();
        box = pageBox();
        box.packStart(bar, false, false, 0);
        box.packStart(grid.widget, true, true, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "Backups";
    }

    override void refresh() {
        run({
            Grid g;
            g.columns = ["Name", "Label", "Created (UTC)", "Type", "Tables", "Rows", "Size"];
            foreach (b; client.backups())
                g.rows ~= [b.name, b.label, b.created, b.readable ? b.kind : "unreadable", b.tables.to!string,
                    b.rows.to!string, humanSize(b.size)];
            grid.show(g);
        });
    }

    private void create() {
        auto form = new FormDialog(window, "Create backup", "Create");
        form.text("label", "Label (optional)");
        scope (exit)
            form.close();
        if (form.run() && run({ client.createBackup(form["label"]); }))
            refresh();
    }

    private void restore() {
        auto name = grid.selected("Name");
        if (name.length == 0)
            return showMessage(window, "Select a backup first.", false);
        if (!confirm(window, "Replace ALL tables with backup " ~ name ~ "? Changes made since then are lost. "
                ~ "The current state is saved first as a safety backup."))
            return;
        string safety;
        if (run({ safety = client.restoreBackup(name); })) {
            showMessage(window, "Database restored. The previous state is saved as " ~ safety ~ ".", false);
            refresh();
        }
    }

    private void remove() {
        auto name = grid.selected("Name");
        if (name.length && confirm(window, "Delete backup " ~ name ~ " permanently?") && run({ client.deleteBackup(name); }))
            refresh();
    }
}

/// Mandanten (Bereich system: viewTenants zum Lesen, manageTenants zum Ändern).
final class TenantsPage : Page {
    private Box box;
    private DataGrid grid;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        box = pageBox();
        if (client.me.can("manageTenants")) {
            auto bar = toolbar();
            bar.packStart(button("New tenant", &create), false, false, 0);
            bar.packStart(button("Edit", &edit), false, false, 0);
            bar.packStart(button("Delete", &remove), false, false, 0);
            box.packStart(bar, false, false, 0);
        }
        grid = new DataGrid();
        box.packStart(grid.widget, true, true, 0);
        auto hint = new Label("Each tenant has its own tables, users and backups. You manage tenants here, but you "
                ~ "can't see their data. Disable a tenant before you delete it.");
        hint.setLineWrap(true);
        hint.setXalign(0);
        box.packStart(hint, false, false, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "Tenants";
    }

    override void refresh() {
        run({
            Grid g;
            g.columns = ["Tenant", "Label", "Status", "Users", "Allowed networks"];
            foreach (t; client.tenants())
                g.rows ~= [t.name, t.label, t.active ? "Active" : "Disabled", t.users.to!string,
                    t.networks.length ? t.networks.join(", ") : "All"];
            grid.show(g);
        });
    }

    private void create() {
        auto form = new FormDialog(window, "New tenant", "Create");
        form.text("name", "Tenant name").text("label", "Label (optional)")
            .text("admin", "First admin", "admin").text("password", "Password", "", true)
            .text("confirm", "Repeat password", "", true)
            .note("Lowercase letters, digits, '_' and '-'. Users type the tenant name when they sign in.");
        scope (exit)
            form.close();
        if (!form.run())
            return;
        if (form["password"] != form["confirm"])
            return showMessage(window, "The passwords don't match.");
        if (run({ client.createTenant(form["name"], form["label"], form["admin"], form["password"]); }))
            refresh();
    }

    private void edit() {
        auto name = grid.selected("Tenant");
        if (name.length == 0)
            return showMessage(window, "Select a tenant first.", false);
        auto form = new FormDialog(window, "Tenant " ~ name, "Save");
        form.text("label", "Label", grid.selected("Label"))
            .flag("active", "Active", grid.selected("Status") == "Active")
            .note("Disabling signs out all users of the tenant at once.");
        scope (exit)
            form.close();
        if (form.run() && run({ client.updateTenant(name, form["label"], form.checked("active")); }))
            refresh();
    }

    private void remove() {
        auto name = grid.selected("Tenant");
        if (name.length == 0)
            return;
        if (confirm(window, "Delete tenant " ~ name ~ " with all its users, tables and backups? This can't be undone.")
                && run({ client.deleteTenant(name); }))
            refresh();
    }
}

private string humanSize(long bytes) {
    if (bytes < 1024)
        return bytes.to!string ~ " B";
    if (bytes < 1024 * 1024)
        return format("%.1f KB", bytes / 1024.0);
    return format("%.1f MB", bytes / (1024.0 * 1024));
}

/// Ein Protokoll (Recht viewLogs): Filter oben, Einträge neueste zuerst, Blättern und Einstellungen (manageLogs).
/// Ein Doppelklick auf eine Zeile zeigt den ganzen Eintrag.
final class LogViewPage : Page {
    private enum pageSize = 200;
    private LogInfo info;
    private Box box;
    private DataGrid grid;
    private ComboBoxText severity, category;
    private Entry search, actor, tenant;
    private Label status;
    private Button newer, older;
    private LogRow[] rows;
    private long[] previous; // before der vorigen Seiten
    private long before;
    private long total;

    this(HdbClient client, Window window, void delegate() signedOut, LogInfo info) {
        super(client, window, signedOut);
        this.info = info;
        box = pageBox();

        auto bar = toolbar();
        severity = new ComboBoxText(false);
        foreach (s; ["All severities", "info", "warning", "error"])
            severity.appendText(s);
        severity.setActive(0);
        bar.packStart(severity, false, false, 0);
        if (info.available.length) {
            category = new ComboBoxText(false);
            category.appendText("All categories");
            foreach (c; info.available)
                category.appendText(c);
            category.setActive(0);
            bar.packStart(category, false, false, 0);
        }
        search = filterEntry("Search text");
        bar.packStart(search, true, true, 0);
        if (info.kind == "audit") {
            actor = filterEntry("User");
            bar.packStart(actor, false, false, 0);
        }
        if (client.me.isSystem && info.kind != "application") {
            tenant = filterEntry("Tenant");
            bar.packStart(tenant, false, false, 0);
        }
        bar.packStart(button("Search", &restart), false, false, 0);
        if (info.editable)
            bar.packEnd(button("Settings…", &editSettings), false, false, 0);
        box.packStart(bar, false, false, 0);

        grid = new DataGrid();
        grid.treeView.addOnRowActivated((TreePath, TreeViewColumn, TreeView) { showDetails(); });
        box.packStart(grid.widget, true, true, 0);

        auto bottom = toolbar();
        status = new Label("");
        status.setXalign(0);
        bottom.packStart(status, true, true, 0);
        newer = button("Newer", &showNewer);
        older = button("Older", &showOlder);
        bottom.packEnd(older, false, false, 0);
        bottom.packEnd(newer, false, false, 0);
        box.packStart(bottom, false, false, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return info.title;
    }

    override void refresh() {
        run({
            LogFilter f;
            f.limit = pageSize;
            f.before = before;
            if (severity.getActive() > 0)
                f.severity = severity.getActiveText();
            if (category !is null && category.getActive() > 0)
                f.category = category.getActiveText();
            f.text = search.getText();
            if (actor !is null)
                f.actor = actor.getText();
            if (tenant !is null)
                f.tenant = tenant.getText();
            auto found = client.logEntries(info.kind, f);
            rows = found.rows;
            total = found.total;
            show();
        });
    }

    private Entry filterEntry(string placeholder) {
        auto e = new Entry();
        e.setPlaceholderText(placeholder);
        e.setWidthChars(placeholder.length > 8 ? 24 : 12);
        e.addOnActivate((Entry _) { restart(); });
        return e;
    }

    /// Neue Suche ab dem neuesten Eintrag.
    private void restart() {
        previous = null;
        before = 0;
        refresh();
    }

    private void showOlder() {
        if (rows.length == 0)
            return;
        previous ~= before;
        before = rows[$ - 1].id;
        refresh();
    }

    private void showNewer() {
        if (previous.length == 0)
            return;
        before = previous[$ - 1];
        previous = previous[0 .. $ - 1];
        refresh();
    }

    private void show() {
        immutable withTenant = tenant !is null;
        Grid g;
        final switch (columnSet) {
        case Columns.audit:
            g.columns = ["Id", "Time (UTC)"] ~ (withTenant ? ["Tenant"] : []) ~ ["Severity", "Category", "User",
                "Address", "Action", "Target", "Result", "Message"];
            foreach (r; rows)
                g.rows ~= [r.id.to!string, shortTime(r.time)] ~ (withTenant ? [r.scope_] : []) ~ [r.severity, r.category,
                    r.actor, r.address, r.action, r.target, r.success ? "ok" : "failed", oneLine(r.message)];
            break;
        case Columns.event:
            g.columns = ["Id", "Time (UTC)"] ~ (withTenant ? ["Tenant"] : []) ~ ["Severity", "Category", "Message"];
            foreach (r; rows)
                g.rows ~= [r.id.to!string, shortTime(r.time)] ~ (withTenant ? [r.scope_] : []) ~ [r.severity,
                    r.category, oneLine(r.message)];
            break;
        case Columns.application:
            g.columns = ["Id", "Time (UTC)", "Severity", "Source", "Message"];
            foreach (r; rows)
                g.rows ~= [r.id.to!string, shortTime(r.time), r.severity, r.category, oneLine(r.message)];
            break;
        }
        grid.show(g);
        immutable first = previous.length * pageSize;
        status.setText(rows.length
                ? format("Entries %s–%s of %s", first + 1, first + rows.length, total)
                : (previous.length ? "No older entries" : "No entries"));
        newer.setSensitive(previous.length > 0);
        older.setSensitive(rows.length == pageSize && first + rows.length < total);
    }

    private enum Columns {
        audit,
        event,
        application
    }

    private Columns columnSet() const {
        return info.kind == "audit" ? Columns.audit : info.kind == "event" ? Columns.event : Columns.application;
    }

    private void showDetails() {
        auto id = grid.selected("Id");
        foreach (r; rows)
            if (r.id.to!string == id)
                return showMessage(window, details(r), false);
    }

    private string details(LogRow r) {
        string[] lines = ["Time: " ~ r.time, "Severity: " ~ r.severity];
        void add(string label, string value) {
            if (value.length)
                lines ~= label ~ ": " ~ value;
        }

        add("Tenant", r.scope_);
        add(info.kind == "application" ? "Source" : "Category", r.category);
        if (info.kind == "audit") {
            add("User", r.actor);
            add("Address", r.address);
            add("Action", r.action);
            add("Target", r.target);
            lines ~= "Result: " ~ (r.success ? "ok" : "failed");
        }
        add("Message", r.message);
        return lines.join("\n");
    }

    private void editSettings() {
        auto current = info.settings;
        auto form = new FormDialog(window, info.title ~ " settings", "Save");
        form.flag("enabled", "Record entries", current.enabled);
        form.choice("minSeverity", "Minimum severity", ["debug", "info", "warning", "error"], current.minSeverity);
        form.text("retentionDays", "Keep for (days)", current.retentionDays.to!string);
        form.text("maxEntries", "Keep at most (entries)", current.maxEntries.to!string);
        if (info.available.length) {
            form.note("Recorded categories:");
            foreach (c; info.available) {
                immutable mandatory = info.mandatory.canFind(c);
                form.flag("cat:" ~ c, categoryLabel(info.kind, c) ~ (mandatory ? " (always recorded)" : ""),
                    mandatory || current.categories.canFind(c));
            }
        }
        if (info.kind == "audit")
            form.note("Changes to these settings are always recorded in the audit log, even when recording is off.");
        scope (exit)
            form.close();
        if (!form.run())
            return;
        run({
            LogSettingsData next;
            next.enabled = form.checked("enabled");
            next.minSeverity = form["minSeverity"];
            next.retentionDays = form["retentionDays"].strip.to!int;
            next.maxEntries = form["maxEntries"].strip.to!long;
            foreach (c; info.available)
                if (form.checked("cat:" ~ c))
                    next.categories ~= c;
            info.settings = client.updateLogSettings(info.kind, next);
            showMessage(window, info.title ~ " settings saved.", false);
            restart();
        });
    }
}

/// Erklärung einer Kategorie für die Einstellungen.
private string categoryLabel(string kind, string category) {
    static immutable string[string] audit = [
        "auth": "auth: sign-in, sign-out, failed sign-ins, own password",
        "users": "users: users, password resets, grants",
        "roles": "roles: custom roles",
        "network": "network: allowed networks",
        "tenants": "tenants: tenant management",
        "backups": "backups: create, download, upload, restore, delete, schedule",
        "replication": "replication: replica setup, full snapshots",
        "schema": "schema: CREATE and DROP TABLE",
        "data": "data: INSERT, UPDATE, DELETE (table and row count only)",
        "maintenance": "maintenance: checkpoint, delta merge",
        "logs": "logs: changes to log settings",
    ];
    static immutable string[string] event = [
        "server": "server: start, stop, first-time setup",
        "backups": "backups: scheduled backups",
        "replication": "replication: state changes and errors",
    ];
    auto table = kind == "audit" ? audit : event;
    if (auto label = category in table)
        return *label;
    return category;
}

/// 2026-11-08T10:00:00.123Z wird zu 2026-11-08 10:00:00.
private string shortTime(string iso) {
    import std.array : replace;

    return iso.length >= 19 ? iso[0 .. 19].replace("T", " ") : iso;
}

private string oneLine(string text) {
    import std.array : replace;

    return text.replace("\r", " ").replace("\n", " ");
}
