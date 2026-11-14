/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.userinfo;

import uim.hdb;

mixin(ShowModule!());

@safe:

/// Benutzer ohne Passwort-Hash: das, was Adapter sehen dürfen.
struct UserInfo {
    string name;
    string role; // Rolle im Mandanten, leer: keine
    bool active;
    string tenant;
    TableGrant[] grants;

    Json toJson() const {
        return Json.emptyObject
            .set("name", name)
            .set("role", role)
            .set("active", active)
            .set("tenant", tenant);
    }
}