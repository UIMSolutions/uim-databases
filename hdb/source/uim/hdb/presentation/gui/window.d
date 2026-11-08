/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.gui.window;

import uim.hdb.presentation.gui.api;
import uim.hdb.presentation.gui.login : signIn;
import uim.hdb.presentation.gui.pages;
import uim.hdb.presentation.gui.widgets;
import gtk.Box;
import gtk.Button;
import gtk.HeaderBar;
import gtk.Main;
import gtk.MainWindow;
import gtk.Stack;
import gtk.StackSidebar;
import gtk.Widget;
import gtk.c.types : Orientation;

/// Hauptfenster: Seitenleiste mit den Bereichen, die die Rechte erlauben, und eine Kopfzeile mit Anmeldung,
/// Aktualisieren und Abmelden.
final class AdminWindow : MainWindow {
    private HdbClient client;
    private HeaderBar header;
    private Box content;
    private Page[string] pages;
    private Stack stack;
    private string serverUrl, tenant, user;

    this(string serverUrl) {
        super("hdb Admin");
        this.serverUrl = serverUrl;
        setDefaultSize(1100, 700);
        header = new HeaderBar();
        header.setShowCloseButton(true);
        header.setTitle("hdb Admin");
        header.packEnd(button("Sign out", &signOut));
        header.packEnd(button("Refresh", &refreshCurrent));
        setTitlebar(header);
        content = new Box(Orientation.HORIZONTAL, 0);
        add(content);
    }

    /// Anmelden und die Seiten aufbauen. false, wenn die Anmeldung abgebrochen wurde.
    bool start() {
        showAll();
        client = signIn(this, serverUrl, tenant, user);
        if (client is null)
            return false;
        serverUrl = client.serverUrl;
        tenant = client.me.tenant;
        user = client.me.name;
        build();
        return true;
    }

    private void build() {
        foreach (child; childrenOf(content))
            content.remove(child);
        pages = null;
        auto me = client.me;
        header.setSubtitle(me.name ~ " · " ~ me.tenant ~ (me.role.length ? " · " ~ me.role : "") ~ " · " ~ client.serverUrl);

        Page[] list;
        void delegate() expired = &sessionExpired;
        if (me.isSystem) {
            if (me.can("viewTenants"))
                list ~= new TenantsPage(client, this, expired);
        } else {
            list ~= new TablesPage(client, this, expired);
            list ~= new ConsolePage(client, this, expired);
            list ~= new StatsPage(client, this, expired);
            if (me.can("manageBackups"))
                list ~= new BackupsPage(client, this, expired);
        }
        if (me.can("manageAccess"))
            list ~= new UsersPage(client, this, expired);
        if (me.can("viewLogs")) {
            // Ältere Server kennen die Protokolle nicht (404): dann fehlen nur diese Seiten
            try
                foreach (info; client.logs())
                    list ~= new LogViewPage(client, this, expired, info);
            catch (ApiError e) {
                if (e.status != 404)
                    showMessage(this, "The logs can't be loaded: " ~ e.msg);
            }
        }

        stack = new Stack();
        foreach (page; list) {
            pages[page.title] = page;
            stack.addTitled(page.widget, page.title, page.title);
        }
        stack.addOnNotify((ParamSpec, ObjectG) { refreshCurrent(); }, "visible-child-name");
        auto sidebar = new StackSidebar();
        sidebar.setStack(stack);
        content.packStart(sidebar, false, false, 0);
        content.packStart(stack, true, true, 0);
        content.showAll();
        refreshCurrent();
    }

    private void refreshCurrent() {
        if (stack is null)
            return;
        if (auto page = stack.getVisibleChildName() in pages)
            page.refresh();
    }

    private void signOut() {
        if (client !is null)
            client.logout();
        restart("");
    }

    /// Der Server hat die Sitzung beendet (abgelaufen, Passwort geändert, Netz nicht erlaubt): neu anmelden.
    private void sessionExpired() {
        restart("Your session has ended. Please sign in again.");
    }

    private void restart(string message) {
        if (message.length)
            showMessage(this, message, false);
        auto next = signIn(this, serverUrl, tenant, user);
        if (next is null) {
            Main.quit();
            return;
        }
        client = next;
        serverUrl = client.serverUrl;
        tenant = client.me.tenant;
        user = client.me.name;
        build();
    }
}

private import gobject.ParamSpec;
private import gobject.ObjectG;

/// Startet den Client. Der Server kommt aus `--server=<url>` oder HDB_URL, sonst http://localhost:8080.
int runAdminClient(string[] args) {
    import std.algorithm : startsWith;
    import std.process : environment;

    Main.init(args);
    auto url = environment.get("HDB_URL", "http://localhost:8080");
    foreach (a; args[1 .. $])
        if (a.startsWith("--server="))
            url = a["--server=".length .. $];
    auto window = new AdminWindow(url);
    if (!window.start())
        return 0;
    Main.run();
    return 0;
}
