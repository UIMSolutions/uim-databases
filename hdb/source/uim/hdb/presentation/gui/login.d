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
        auto form = new FormDialog(parent, "Sign in to hdb", "Sign in");
        form.text("url", "Server", serverUrl)
            .text("tenant", "Tenant", tenant)
            .text("user", "User name", user)
            .text("password", "Password", "", true)
            .note("Leave the tenant empty for the default tenant. System administrators use \"system\".");
        scope (exit)
            form.close();
        if (!form.run())
            return null;
        serverUrl = form["url"];
        tenant = form["tenant"];
        user = form["user"];
        HdbClient client;
        if (guarded(parent, {
                client = new HdbClient(new CurlTransport, serverUrl);
                client.login(tenant, user, form["password"]);
            }))
            return client;
    }
}
