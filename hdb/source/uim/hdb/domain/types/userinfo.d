module uim.hdb.domain.types.userinfo;

import uim.hdb;

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