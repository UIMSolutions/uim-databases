module uim.hdb.domain.types.userinfo;

import uim.hdb;

/// Benutzer ohne Passwort-Hash: das, was Adapter sehen dürfen.
struct UserInfo {
    string name;
    HdbRole role;
    bool active;

    Json toJson() const {
        return Json.emptyObject
            .set("name", name)
            .set("role", role.to!string)
            .set("active", active);
    }
}