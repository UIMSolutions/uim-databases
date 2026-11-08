/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.gui.login;

import uim.hdb.presentation.gui.api;
import uim.hdb.presentation.gui.transport : CurlTransport;
import uim.hdb.presentation.gui.widgets;
import gtk.Window;

/// Fragt Server, Mandant, Benutzer und Passwort ab, bis die Anmeldung gelingt oder abgebrochen wird.
/// Gibt den angemeldeten Client zurück oder null.
HdbClient signIn(Window parent, string serverUrl, string tenant, string user) {
    while (true) {
        // Ein Einzelmandanten-Server fragt keinen Mandanten ab. Ist er nicht erreichbar, bleibt das Feld da;
        // der Fehler kommt dann bei der Anmeldung.
        auto info = ServerInfo.init;
        try
            info = new HdbClient(new CurlTransport, serverUrl).info();
        catch (Exception) {
        }
        auto form = new FormDialog(parent, "Sign in to hdb", "Sign in");
        form.text("url", "Server", serverUrl);
        if (info.tenantLogin)
            form.text("tenant", "Tenant", tenant);
        form.text("user", "User name", user)
            .text("password", "Password", "", true);
        if (info.tenantLogin)
            form.note(info.mode == "gateway"
                    ? "This server forwards each tenant to its database server. Leave the tenant empty for the default tenant."
                    : "Leave the tenant empty for the default tenant. System administrators use \"system\".");
        scope (exit)
            form.close();
        if (!form.run())
            return null;
        immutable changedServer = form["url"] != serverUrl;
        serverUrl = form["url"];
        tenant = info.tenantLogin ? form["tenant"] : "";
        user = form["user"];
        if (changedServer && !info.tenantLogin)
            continue; // anderer Server: dessen Betriebsart erst abfragen
        HdbClient client;
        if (guarded(parent, {
                client = new HdbClient(new CurlTransport, serverUrl);
                client.login(tenant, user, form["password"]);
            }))
            return client;
    }
}
