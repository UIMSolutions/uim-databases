module uim.hdb.application.services.access;

import uim.hdb;
import core.time : Duration, hours, minutes, MonoTime;
import std.algorithm : all, any, canFind, count, filter, map, sort;
import std.conv : to;
import std.array : array;
import std.ascii : isAlphaNum;
import std.digest : toHexString;
import std.digest.sha : sha256Of;
import std.exception : enforce;
import std.string : strip, toLower;

/// Anmeldung, Sitzungen und Benutzerverwaltung. Sitzungen liegen nur im Speicher, ein Neustart meldet alle ab.
/// Die Rolle wird bei jeder Anfrage aus dem Benutzer gelesen, Änderungen wirken also sofort.
/// Benutzer gehören zu einem Mandanten: Namen sind nur dort eindeutig, und jede Verwaltung wirkt nur im Mandanten
/// des Anfragenden. Ist ein Mandant inaktiv, kann sich dort niemand anmelden und laufende Sitzungen enden.
final class AccessService : IAccessUseCase, ITenantAccounts {
    enum minPasswordLength = 12;
    private enum sessionLifetime = 12.hours;
    private enum maxFailures = 5; // Fehlversuche je Name, bevor er gesperrt wird
    private enum lockout = 1.minutes;
    private enum maxTrackedNames = 10_000;
    private enum maxConcurrentLogins = 4; // Passwort-Hashing ist teuer: schützt die Worker-Threads

    private struct Session {
        string user; // Schlüssel des Benutzers, siehe userKey
        MonoTime expires;
    }

    private struct Failures {
        int count;
        MonoTime lockedUntil;
    }

    private IUserStore store;
    private ICredentialCrypto crypto;
    private MonoTime delegate() now;
    private bool delegate(string) tenantActive;
    private HdbUser[string] users; // Schlüssel: userKey
    private IRoleStore roleStore;
    private RoleDef[string] customRoles; // Schlüssel: userKey(Bereich, Rollenname)
    private Session[string] sessions; // Schlüssel: SHA-256 des Tokens
    private Failures[string] failures;
    private string dummyHash; // unbekannte Namen kosten dieselbe Zeit wie bekannte
    private int loginsInFlight;

    /// `tenantActive` sagt, ob ein Mandant existiert und aktiv ist; ohne gelten alle als aktiv.
    /// Ohne `roleStore` gibt es eigene Rollen nur bis zum Neustart.
    this(IUserStore store, ICredentialCrypto crypto, MonoTime delegate() now = null,
        bool delegate(string) tenantActive = null, IRoleStore roleStore = null) {
        this.store = store;
        this.crypto = crypto;
        this.now = now !is null ? now : () => MonoTime.currTime;
        this.tenantActive = tenantActive !is null ? tenantActive : (string) => true;
        this.roleStore = roleStore !is null ? roleStore : new MemoryRoleStore;
        foreach (u; store.load())
            users[userKey(u.tenant, u.name)] = u;
        foreach (r; this.roleStore.load())
            customRoles[userKey(r.tenant, r.name)] = r;
        dummyHash = crypto.hashPassword(crypto.randomSecret());
    }

    /** 
     *  Create an administrator when a tenant has no users yet.
     *  If no password is specified, one is generated and returned so that it can be displayed once; otherwise, the result is empty.
     *
     *  @param tenant The tenant of the administrator.
     *  @param name The name of the administrator to create.
     *  @param password The password for the administrator. If empty, a random password is generated.
     *  @return The generated password if no password was specified and a user was created, otherwise an empty string.
    **/
    string bootstrap(string tenant, string name, string password) {
        if (userCount(tenant))
            return "";
        auto generated = password.length ? "" : crypto.randomSecret();
        auto normalized = validName(name);
        commit(HdbUser(normalized, crypto.hashPassword(password.length ? password : generated), "admin", true, tenant));
        return generated;
    }

    /// Wie bootstrap(tenant, ...) für den Mandanten default.
    string bootstrap(string name, string password) {
        return bootstrap(defaultTenant, name, password);
    }

    /** 
     *  Attempt to log in with the given tenant, user name and password.
     *
     *  @param tenant The tenant of the user; empty means the default tenant.
     *  @param name The name of the user attempting to log in.
     *  @param password The password for the user.
     *  @return The result of the login attempt, including a session token if successful.
    **/
    LoginResult login(string tenant, string name, string password) {
        auto key = userKey(loginTenant(tenant), name.strip.toLower);
        auto locked = key in failures;
        enforce!AuthenticationRequired(locked is null || locked.lockedUntil <= now(),
            "Too many failed attempts, try again later");
        enforce!AuthenticationRequired(loginsInFlight < maxConcurrentLogins, "Too many logins in progress, try again");
        ++loginsInFlight;
        scope (exit)
            --loginsInFlight;

        auto user = key in users;
        immutable matches = crypto.verifyPassword(password, user !is null ? user.passwordHash : dummyHash);
        user = key in users; // das Hashing gibt die Kontrolle ab: der Benutzer kann inzwischen weg sein
        // Dieselbe Meldung für einen inaktiven Mandanten: sonst ließe sich erfragen, welche Mandanten es gibt
        if (user is null || !matches || !user.active || !tenantActive(user.tenant)) {
            recordFailure(key);
            throw new AuthenticationRequired("Invalid tenant, user name or password");
        }
        failures.remove(key);
        pruneSessions();
        auto token = crypto.randomSecret();
        sessions[digest(token)] = Session(key, now() + sessionLifetime);
        return LoginResult(token, principalOf(*user), sessionLifetime.total!"seconds");
    }

    /// Wie login(tenant, ...) im Mandanten default.
    LoginResult login(string name, string password) {
        return login("", name, password);
    }

    /** 
     *  Log out the session associated with the given token.
     *
     *  @param token The session token to log out.
    **/
    void logout(string token) {
        sessions.remove(digest(token));
    }

    /** 
     *  Authenticate the session associated with the given token.
     *
     *  @param token The session token to authenticate.
     *  @return The principal associated with the session, or an empty principal if authentication fails.
    **/
    Principal authenticate(string token) {
        if (token.length == 0)
            return Principal.init;
        auto id = digest(token);
        auto session = id in sessions;
        if (session is null)
            return Principal.init;
        auto user = session.user in users;
        if (session.expires <= now() || user is null || !user.active || !tenantActive(user.tenant)) {
            sessions.remove(id);
            return Principal.init;
        }
        return principalOf(*user);
    }

    /** 
     *  Change the password of the currently authenticated user.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param current The current password of the user.
     *  @param replacement The new password to set.
    **/
    void changeOwnPassword(Principal actor, string current, string replacement) {
        requireAuthenticated(actor);
        auto user = userKey(actor.tenant, actor.name) in users;
        enforce!AuthenticationRequired(user !is null);
        enforce(crypto.verifyPassword(current, user.passwordHash), "Current password is wrong");
        setPassword(*user, replacement);
    }

    /** 
     *  List all users in the tenant of the actor.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @return An array of user information for all users of the actor's tenant.
    **/
    UserInfo[] listUsers(Principal actor) {
        requirePermission(actor, Permission.manageAccess);
        auto result = users.values.filter!(u => u.tenant == actor.tenant).map!(u => info(u)).array;
        result.sort!((a, b) => a.name < b.name);
        return result;
    }

    /** 
     *  Create a new user in the tenant of the actor.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the new user.
     *  @param password The password for the new user.
     *  @param role The role to assign to the new user.
     *  @return The information of the newly created user.
    **/
    UserInfo createUser(Principal actor, string name, string password, string role) {
        requirePermission(actor, Permission.manageAccess);
        return info(addUser(actor.tenant, name, password, assignableRole(actor.tenant, role)));
    }

    /// Mit einer vordefinierten Rolle.
    UserInfo createUser(Principal actor, string name, string password, HdbRole role) {
        return createUser(actor, name, password, roleName(role));
    }

    /** 
     *  Update the role and active status of an existing user of the actor's tenant.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the user to update.
     *  @param role The new role to assign to the user.
     *  @param active The new active status of the user.
     *  @return The updated user information.
    **/
    UserInfo updateUser(Principal actor, string name, string role, bool active) {
        requirePermission(actor, Permission.manageAccess);
        auto user = find(actor.tenant, name);
        user.role = assignableRole(actor.tenant, role);
        user.active = active;
        auto next = users.dup;
        next[userKey(user.tenant, user.name)] = user;
        requireManager(user.tenant, next, customRoles);
        commit(user);
        if (!active)
            revokeSessions(userKey(user.tenant, user.name));
        return info(user);
    }

    /// Mit einer vordefinierten Rolle.
    UserInfo updateUser(Principal actor, string name, HdbRole role, bool active) {
        return updateUser(actor, name, roleName(role), active);
    }

    /// Ersetzt die Tabellenfreigaben. Jede Freigabe nennt eine Tabelle und eine Rolle des Mandanten, von der nur die
    /// Tabellenrechte gelten. Ob die Tabelle existiert, wird nicht geprüft: Freigaben dürfen vor dem Anlegen
    /// entstehen und gelten für eine später gleichnamig angelegte Tabelle wieder.
    UserInfo setGrants(Principal actor, string name, TableGrant[] grants) {
        requirePermission(actor, Permission.manageAccess);
        enforce(actor.tenant != systemTenant, "The system area has no tables");
        auto user = find(actor.tenant, name);
        TableGrant[] clean;
        bool[string] seen;
        foreach (g; grants) {
            auto table = g.table.strip.toLower;
            enforce(table.length && table.all!(c => isAlphaNum(c) || c == '_'), "Invalid table name: " ~ g.table);
            auto role = assignableRole(actor.tenant, g.role);
            enforce(role.length, "Choose a role for table " ~ table);
            enforce(!(rolePermissions(actor.tenant, role) & tablePermissions).empty,
                "Role " ~ role ~ " has no table permissions (select, insert, update, delete, drop)");
            auto key = table ~ "/" ~ role;
            if (key in seen)
                continue;
            seen[key] = true;
            clean ~= TableGrant(table, role);
        }
        clean.sort!((a, b) => a.table != b.table ? a.table < b.table : a.role < b.role);
        user.grants = clean;
        commit(user);
        return info(user);
    }

    /// Vordefinierte und eigene Rollen des Bereichs, mit der Zahl der Benutzer, die sie verwenden.
    RoleInfo[] listRoles(Principal actor) {
        requirePermission(actor, Permission.manageAccess);
        RoleInfo[] result;
        foreach (r; rolesOf(actor.tenant))
            result ~= RoleInfo(r.name, r.description, r.permissions.names, r.builtin, usersOfRole(actor.tenant, r.name));
        return result;
    }

    /// Legt eine eigene Rolle an oder ändert sie. Erlaubt sind nur Rechte des Bereichs: Serverrechte im Bereich
    /// system, sonst Mandantenrechte. Änderungen wirken sofort in allen Sitzungen.
    RoleInfo saveRole(Principal actor, string name, string description, string[] permissions) {
        requirePermission(actor, Permission.manageAccess);
        auto normalized = validRoleName(name);
        foreach (b; builtinRoles(actor.tenant))
            enforce(b.name != normalized, "Built-in roles can't be changed: " ~ normalized);
        auto set = PermissionSet.parse(permissions);
        enforce(set.subsetOf(allowedPermissions(actor.tenant)), actor.tenant == systemTenant
                ? "System roles can only contain viewTenants, manageTenants and manageAccess"
                : "Tenant roles can't contain viewTenants or manageTenants");
        enforce(description.strip.length <= 200, "Role descriptions have at most 200 characters");
        auto role = RoleDef(actor.tenant, normalized, description.strip, set, false);
        auto next = customRoles.dup;
        next[userKey(actor.tenant, normalized)] = role;
        requireManager(actor.tenant, users, next);
        roleStore.save(next.values);
        customRoles = next;
        return RoleInfo(role.name, role.description, set.names, false, usersOfRole(actor.tenant, normalized));
    }

    void deleteRole(Principal actor, string name) {
        requirePermission(actor, Permission.manageAccess);
        auto key = userKey(actor.tenant, name.strip.toLower);
        enforce((key in customRoles) !is null, "Role not found or built in: " ~ name);
        immutable inUse = usersOfRole(actor.tenant, name.strip.toLower);
        enforce(inUse == 0, "Role " ~ name ~ " is still used by " ~ inUse.to!string ~ " user(s)");
        auto next = customRoles.dup;
        next.remove(key);
        roleStore.save(next.values);
        customRoles = next;
    }

    /** 
     *  Reset the password of an existing user of the actor's tenant.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the user whose password is to be reset.
     *  @param replacement The new password to set.
    **/
    void resetPassword(Principal actor, string name, string replacement) {
        requirePermission(actor, Permission.manageAccess);
        setPassword(find(actor.tenant, name), replacement);
    }

    /** 
     *  Delete an existing user of the actor's tenant.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the user to delete.
    **/
    void deleteUser(Principal actor, string name) {
        requirePermission(actor, Permission.manageAccess);
        auto user = find(actor.tenant, name);
        auto key = userKey(user.tenant, user.name);
        auto remaining = users.dup;
        remaining.remove(key);
        requireManager(user.tenant, remaining, customRoles);
        store.save(remaining.values);
        users = remaining;
        revokeSessions(key);
    }

    // ITenantAccounts: ohne Rollenprüfung, die macht TenantService

    void provisionAdmin(string tenant, string name, string password) {
        addUser(tenant, name, password, "admin");
    }

    void revokeTenant(string tenant) {
        string[] ids;
        foreach (id, s; sessions)
            if (auto user = s.user in users)
                if (user.tenant == tenant)
                    ids ~= id;
        foreach (id; ids)
            sessions.remove(id);
    }

    void removeTenant(string tenant) {
        revokeTenant(tenant);
        HdbUser[string] remaining;
        foreach (key, u; users)
            if (u.tenant != tenant)
                remaining[key] = u;
        store.save(remaining.values);
        users = remaining;
        RoleDef[string] roles;
        foreach (key, r; customRoles)
            if (r.tenant != tenant)
                roles[key] = r;
        roleStore.save(roles.values);
        customRoles = roles;
    }

    size_t userCount(string tenant) {
        return users.values.count!(u => u.tenant == tenant);
    }

    private HdbUser addUser(string tenant, string name, string password, string role) {
        auto normalized = validName(name);
        enforce((userKey(tenant, normalized) in users) is null, "User already exists: " ~ normalized);
        validPassword(password);
        auto user = HdbUser(normalized, crypto.hashPassword(password), role, true, tenant);
        commit(user);
        return user;
    }

    /** 
     *  Set the password for a user.
     *
     *  @param user The user whose password is to be set.
     *  @param replacement The new password to set.
    **/
    private void setPassword(HdbUser user, string replacement) {
        validPassword(replacement);
        user.passwordHash = crypto.hashPassword(replacement);
        commit(user);
        revokeSessions(userKey(user.tenant, user.name)); // gestohlene Sitzungen enden mit dem Passwort
    }

    /// First save, then take over from the storage: if writing fails, everything remains as it was.
    private void commit(HdbUser user) {
        auto next = users.dup;
        next[userKey(user.tenant, user.name)] = user;
        store.save(next.values);
        users = next;
    }

    private HdbUser find(string tenant, string name) {
        auto user = userKey(tenant, name.strip.toLower) in users;
        enforce(user !is null, "User not found: " ~ name);
        return *user;
    }

    /// Ohne aktiven Benutzer mit manageAccess ließe sich der Bereich nicht mehr verwalten. Geprüft wird der Stand nach
    /// der Änderung; nur die Rolle im Bereich zählt, Tabellenfreigaben geben dieses Recht nie.
    private void requireManager(string tenant, HdbUser[string] nextUsers, RoleDef[string] nextRoles) {
        foreach (u; nextUsers)
            if (u.tenant == tenant && u.active && resolve(tenant, u.role, nextRoles).has(Permission.manageAccess))
                return;
        throw new Exception("At least one active user must keep the manageAccess permission");
    }

    /// Rollen eines Bereichs: erst die vordefinierten, dann die eigenen nach Namen.
    private RoleDef[] rolesOf(string tenant) {
        RoleDef[] own;
        foreach (r; customRoles)
            if (r.tenant == tenant)
                own ~= r;
        own.sort!((a, b) => a.name < b.name);
        return builtinRoles(tenant) ~ own;
    }

    /// Rechte einer Rolle; eine unbekannte oder leere Rolle gibt keine.
    private PermissionSet rolePermissions(string tenant, string role) {
        return resolve(tenant, role, customRoles);
    }

    private static PermissionSet resolve(string tenant, string role, RoleDef[string] roles) {
        if (role.length == 0)
            return PermissionSet.init;
        foreach (b; builtinRoles(tenant))
            if (b.name == role)
                return b.permissions;
        auto custom = userKey(tenant, role) in roles;
        return custom !is null ? custom.permissions : PermissionSet.init;
    }

    /// Normalisierter Rollenname, der im Bereich existiert; leer bleibt leer (keine Rolle).
    private string assignableRole(string tenant, string role) {
        auto name = role.strip.toLower;
        if (name.length == 0)
            return "";
        foreach (r; rolesOf(tenant))
            if (r.name == name)
                return name;
        throw new Exception("Unknown role: " ~ role);
    }

    private size_t usersOfRole(string tenant, string role) {
        size_t n;
        foreach (u; users)
            if (u.tenant == tenant && (u.role == role || u.grants.any!(g => g.role == role)))
                ++n;
        return n;
    }

    /// Aufgelöste Rechte eines Benutzers: Rolle im Bereich plus Tabellenrechte aus den Freigaben.
    private Principal principalOf(HdbUser user) {
        Principal p;
        p.name = user.name;
        p.authenticated = true;
        p.tenant = user.tenant;
        p.role = user.role;
        p.permissions = rolePermissions(user.tenant, user.role) & allowedPermissions(user.tenant);
        foreach (g; user.grants) {
            auto granted = rolePermissions(user.tenant, g.role) & tablePermissions;
            if (!granted.empty)
                p.tables[g.table] = p.tables.get(g.table, PermissionSet.init) | granted;
        }
        return p;
    }

    private void revokeSessions(string key) {
        string[] ids;
        foreach (id, s; sessions)
            if (s.user == key)
                ids ~= id;
        foreach (id; ids)
            sessions.remove(id);
    }

    private void pruneSessions() {
        string[] ids;
        immutable t = now();
        foreach (id, s; sessions)
            if (s.expires <= t)
                ids ~= id;
        foreach (id; ids)
            sessions.remove(id);
    }

    private void recordFailure(string key) {
        if (failures.length >= maxTrackedNames && (key in failures) is null)
            pruneFailures();
        auto entry = failures.get(key, Failures.init);
        if (++entry.count >= maxFailures) {
            entry.count = 0;
            entry.lockedUntil = now() + lockout;
        }
        failures[key] = entry;
    }

    private void pruneFailures() {
        string[] keys;
        immutable t = now();
        foreach (k, f; failures)
            if (f.lockedUntil <= t)
                keys ~= k;
        foreach (k; keys)
            failures.remove(k);
    }
}

/// Weder Mandanten- noch Benutzernamen enthalten '/': der Schlüssel ist eindeutig.
private string userKey(string tenant, string name) {
    return tenant ~ "/" ~ name;
}

private UserInfo info(HdbUser user) {
    return UserInfo(user.name, user.role, user.active, user.tenant, user.grants.dup);
}

private string digest(string token) {
    return sha256Of(token).toHexString.idup;
}

private string validName(string name) {
    auto normalized = name.strip.toLower;
    enforce(normalized.length >= 1 && normalized.length <= 64
            && normalized.all!(c => isAlphaNum(c) || c == '_' || c == '-' || c == '.'),
        "User names use 1 to 64 letters, digits, '_', '-' or '.'");
    return normalized;
}

private void validPassword(string password) {
    enforce(password.length >= AccessService.minPasswordLength, "Passwords need at least 12 characters");
}

unittest {
    import std.exception : assertNotThrown, assertThrown;
    import core.time : seconds;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        bool failing;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            if (failing)
                throw new Exception("disk full");
            saved = users.dup;
        }
    }

    static class FakeCrypto : ICredentialCrypto {
        int n;
        string hashPassword(string p) {
            return "h:" ~ p;
        }

        bool verifyPassword(string p, string stored) {
            return stored == "h:" ~ p;
        }

        string randomSecret() {
            import std.conv : to;

            return "secret" ~ (++n).to!string;
        }
    }

    auto clock = MonoTime.currTime;
    auto store = new MemStore;
    auto a = new AccessService(store, new FakeCrypto, () => clock);

    // Erster Start: Passwort erzeugen; danach ändert bootstrap nichts mehr
    auto generated = a.bootstrap("Admin", "");
    assert(generated.length);
    assert(a.bootstrap("other", "x") == "");
    assert(store.saved.length == 1 && store.saved[0].name == "admin" && store.saved[0].passwordHash != generated);

    auto session = a.login("ADMIN", generated);
    auto root = a.authenticate(session.token);
    assert(root.authenticated && root.role == "admin");
    assert(!a.authenticate("forged").authenticated);
    assert(!a.authenticate("").authenticated);

    // Benutzerverwaltung nur für Administratoren
    auto long1 = "correct-horse-1";
    auto long2 = "correct-horse-2";
    a.createUser(root, "ed", long1, HdbRole.editor);
    auto ed = a.authenticate(a.login("ed", long1).token);
    assert(ed.role == "editor");
    assertThrown!AccessDenied(a.listUsers(ed));
    assertThrown!AccessDenied(a.createUser(ed, "x", long1, HdbRole.admin));
    assertThrown!AccessDenied(a.updateUser(ed, "ed", HdbRole.admin, true)); // keine Selbstbeförderung
    assertThrown!AccessDenied(a.resetPassword(ed, "admin", long2));
    assertThrown!AccessDenied(a.deleteUser(ed, "admin"));
    assertThrown!AuthenticationRequired(a.listUsers(Principal.init));

    assertThrown(a.createUser(root, "ed", long1, HdbRole.viewer)); // doppelt
    assertThrown(a.createUser(root, "bad name", long1, HdbRole.viewer));
    assertThrown(a.createUser(root, "shorty", "short", HdbRole.viewer));
    assert(a.listUsers(root).map!(u => u.name).array == ["admin", "ed"]);

    // Rollenänderung wirkt in laufenden Sitzungen sofort
    auto edSession = a.login("ed", long1).token;
    a.updateUser(root, "ed", HdbRole.viewer, true);
    assert(a.authenticate(edSession).role == "viewer");

    // Deaktivieren beendet Sitzungen und verhindert die Anmeldung
    a.updateUser(root, "ed", HdbRole.viewer, false);
    assert(!a.authenticate(edSession).authenticated);
    assertThrown!AuthenticationRequired(a.login("ed", long1));
    a.updateUser(root, "ed", HdbRole.editor, true);

    // Passwortwechsel beendet Sitzungen; das alte Passwort gilt nicht mehr
    edSession = a.login("ed", long1).token;
    auto edNow = a.authenticate(edSession);
    assertThrown(a.changeOwnPassword(edNow, "wrong", long2));
    assertThrown(a.changeOwnPassword(edNow, long1, "short"));
    a.changeOwnPassword(edNow, long1, long2);
    assert(!a.authenticate(edSession).authenticated);
    assertThrown!AuthenticationRequired(a.login("ed", long1));
    a.login("ed", long2);

    // Der letzte aktive Administrator bleibt erhalten
    assertThrown(a.deleteUser(root, "admin"));
    assertThrown(a.updateUser(root, "admin", HdbRole.editor, true));
    assertThrown(a.updateUser(root, "admin", HdbRole.admin, false));
    a.updateUser(root, "ed", HdbRole.admin, true);
    a.updateUser(root, "admin", HdbRole.viewer, true);
    a.updateUser(a.authenticate(a.login("ed", long2).token), "admin", HdbRole.admin, true);

    // Sperre nach Fehlversuchen, auch für unbekannte Namen; danach geht es wieder
    foreach (i; 0 .. 5)
        assertThrown!AuthenticationRequired(a.login("ed", "nope"));
    assertThrown!AuthenticationRequired(a.login("ed", long2));
    clock += 61.seconds;
    assertNotThrown(a.login("ed", long2));
    foreach (i; 0 .. 5)
        assertThrown!AuthenticationRequired(a.login("ghost", "nope"));

    // Sitzungen laufen ab
    auto token = a.login("ed", long2).token;
    clock += 13 * 3600.seconds;
    assert(!a.authenticate(token).authenticated);

    // Schlägt das Speichern fehl, bleibt der Zustand unverändert
    root = a.authenticate(a.login("ed", long2).token);
    store.failing = true;
    assertThrown(a.createUser(root, "lost", long1, HdbRole.viewer));
    store.failing = false;
    assert(!a.listUsers(root).map!(u => u.name).canFind("lost"));

    // Benutzer überstehen einen Neustart, Sitzungen nicht
    token = a.login("ed", long2).token;
    auto restarted = new AccessService(store, new FakeCrypto, () => clock);
    assert(!restarted.authenticate(token).authenticated);
    assert(restarted.login("ed", long2).principal.role == "admin");
}

/// Mandanten: gleiche Namen in verschiedenen Mandanten, Verwaltung nur im eigenen, inaktive Mandanten gesperrt.
unittest {
    import std.exception : assertThrown;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.dup;
        }
    }

    static class FakeCrypto : ICredentialCrypto {
        int n;
        string hashPassword(string p) {
            return "h:" ~ p;
        }

        bool verifyPassword(string p, string stored) {
            return stored == "h:" ~ p;
        }

        string randomSecret() {
            import std.conv : to;

            return "secret" ~ (++n).to!string;
        }
    }

    bool[string] active = ["default": true, "acme": true, "globex": true];
    auto store = new MemStore;
    auto a = new AccessService(store, new FakeCrypto, null, (string t) => t == systemTenant || active.get(t, false));
    auto pw = "correct-horse-1";
    a.bootstrap(defaultTenant, "admin", pw);
    a.provisionAdmin("acme", "admin", "acme-password-1");
    a.provisionAdmin("globex", "admin", "globex-password1");
    assert(a.bootstrap("acme", "other", "") == ""); // acme hat schon Benutzer
    assert(a.userCount("acme") == 1 && a.userCount("nobody") == 0);

    // Gleicher Name, verschiedene Mandanten: das Passwort des einen öffnet nicht den anderen
    auto acme = a.authenticate(a.login("ACME", "admin", "acme-password-1").token);
    assert(acme.tenant == "acme" && acme.role == "admin");
    assertThrown!AuthenticationRequired(a.login("acme", "admin", pw));
    assert(a.authenticate(a.login("", "admin", pw).token).tenant == defaultTenant);
    assert(a.authenticate(a.login("admin", pw).token).tenant == defaultTenant);
    assertThrown!AuthenticationRequired(a.login("unknown", "admin", pw));

    // Verwaltung nur im eigenen Mandanten
    a.createUser(acme, "ed", pw, HdbRole.editor);
    assert(a.listUsers(acme).map!(u => u.name).array == ["admin", "ed"]);
    auto globex = a.authenticate(a.login("globex", "admin", "globex-password1").token);
    assert(a.listUsers(globex).map!(u => u.name).array == ["admin"]);
    assertThrown(a.updateUser(globex, "ed", HdbRole.admin, true));
    assertThrown(a.resetPassword(globex, "ed", "stolen-password"));
    assertThrown(a.deleteUser(globex, "ed"));
    a.createUser(globex, "ed", "globex-ed-password", HdbRole.viewer); // gleicher Name, anderer Mandant
    assert(a.authenticate(a.login("acme", "ed", pw).token).role == "editor");
    assert(a.authenticate(a.login("globex", "ed", "globex-ed-password").token).role == "viewer");

    // Der letzte Administrator zählt je Mandant
    assertThrown(a.deleteUser(globex, "admin"));

    // Ein inaktiver Mandant: Sitzungen enden, Anmeldung scheitert, andere Mandanten laufen weiter
    auto edSession = a.login("acme", "ed", pw).token;
    active["acme"] = false;
    assert(!a.authenticate(edSession).authenticated);
    assertThrown!AuthenticationRequired(a.login("acme", "ed", pw));
    assert(a.authenticate(a.login("globex", "admin", "globex-password1").token).authenticated);
    active["acme"] = true;
    edSession = a.login("acme", "ed", pw).token;
    a.revokeTenant("acme");
    assert(!a.authenticate(edSession).authenticated);

    // Mandant entfernen: alle Benutzer weg, die anderen bleiben, auch dauerhaft
    edSession = a.login("acme", "ed", pw).token;
    a.removeTenant("acme");
    assert(!a.authenticate(edSession).authenticated && a.userCount("acme") == 0);
    assert(a.userCount("globex") == 2 && a.userCount(defaultTenant) == 1);
    auto restarted = new AccessService(store, new FakeCrypto);
    assert(restarted.userCount("acme") == 0 && restarted.userCount("globex") == 2);
    assert(restarted.login("globex", "ed", "globex-ed-password").principal.tenant == "globex");
}

/// Eigene Rollen nur im Speicher.
final class MemoryRoleStore : IRoleStore {
    private RoleDef[] roles;

    RoleDef[] load() {
        return roles.dup;
    }

    void save(RoleDef[] next) {
        roles = next.dup;
    }
}

/// RBAC: eigene Rollen je Bereich, Tabellenfreigaben, Serverrollen und die Regel, dass jemand verwalten können muss.
unittest {
    import std.exception : assertThrown;

    static class MemStore : IUserStore {
        HdbUser[] saved;
        HdbUser[] load() {
            return saved;
        }

        void save(HdbUser[] users) {
            saved = users.dup;
        }
    }

    static class FakeCrypto : ICredentialCrypto {
        string hashPassword(string p) {
            return "h:" ~ p;
        }

        bool verifyPassword(string p, string stored) {
            return stored == "h:" ~ p;
        }

        string randomSecret() {
            return "secret";
        }
    }

    auto users = new MemStore;
    auto roles = new MemoryRoleStore;
    auto a = new AccessService(users, new FakeCrypto, null, null, roles);
    auto pw = "correct-horse-1";
    a.bootstrap(defaultTenant, "admin", pw);
    a.bootstrap(systemTenant, "root", pw);
    auto admin = a.authenticate(a.login("", "admin", pw).token);
    auto root = a.authenticate(a.login("system", "root", pw).token);

    // Vordefinierte Rollen sind da und unveränderlich
    assert(a.listRoles(admin).map!(r => r.name).array == ["viewer", "editor", "admin"]);
    assertThrown(a.saveRole(admin, "admin", "", ["select"]));
    assertThrown(a.deleteRole(admin, "viewer"));

    // Eigene Rolle: nur Rechte des Bereichs
    auto clerk = a.saveRole(admin, "Clerk", "Enters orders", ["select", "insert"]);
    assert(clerk.name == "clerk" && clerk.permissions == ["select", "insert"] && !clerk.builtin);
    assertThrown(a.saveRole(admin, "boss", "", ["manageTenants"]));
    assertThrown(a.saveRole(admin, "x", "", ["fly"]));
    assertThrown(a.saveRole(root, "ops", "", ["select"]));
    a.saveRole(root, "ops", "Sees tenants", ["viewTenants"]);
    assert(roles.load().length == 2);

    // Benutzer mit eigener Rolle: Rechte gelten im ganzen Mandanten
    a.createUser(admin, "carl", pw, "clerk");
    auto carl = a.authenticate(a.login("", "carl", pw).token);
    assert(carl.role == "clerk" && carl.can(Permission.insert) && !carl.can(Permission.delete_));
    assertThrown(a.createUser(admin, "x", pw, "nope"));
    assertThrown(a.createUser(admin, "x", pw, "ops")); // Rolle eines anderen Bereichs

    // Ohne Rolle, nur mit Tabellenfreigaben
    a.createUser(admin, "tina", pw, "");
    auto tina = a.authenticate(a.login("", "tina", pw).token);
    assert(!tina.can(Permission.select) && tina.tables.length == 0 && tina.role == "");
    a.setGrants(admin, "tina", [TableGrant("Orders", "clerk"), TableGrant("audit", "viewer"), TableGrant("orders", "clerk")]);
    tina = a.authenticate(a.login("", "tina", pw).token);
    assert(tina.can(Permission.insert, "orders") && tina.can(Permission.select, "audit") && !tina.can(Permission.insert, "audit"));
    assert(!tina.can(Permission.select, "secret") && !tina.can(Permission.select));
    assert(!tina.tables["audit"].has(Permission.replicate)); // nur Tabellenrechte gelten
    assert(a.listUsers(admin).filter!(u => u.name == "tina").front.grants.length == 2); // doppelte entfernt

    // Nur Tabellenrechte: eine Rolle ohne solche ist als Freigabe sinnlos
    a.saveRole(admin, "maint", "", ["maintain"]);
    assertThrown(a.setGrants(admin, "tina", [TableGrant("orders", "maint")]));
    assertThrown(a.setGrants(admin, "tina", [TableGrant("a;b", "clerk")]));
    assertThrown(a.setGrants(admin, "tina", [TableGrant("orders", "")]));
    assertThrown(a.setGrants(root, "root", [TableGrant("orders", "admin")])); // keine Tabellen im Bereich system

    // Rollenänderung wirkt sofort in laufenden Sitzungen
    auto tinaSession = a.login("", "tina", pw).token;
    a.saveRole(admin, "clerk", "Enters and fixes orders", ["select", "insert", "update"]);
    assert(a.authenticate(tinaSession).can(Permission.update, "orders"));

    // Löschen nur ungenutzter Rollen
    assertThrown(a.deleteRole(admin, "clerk"));
    assert(a.listRoles(admin).filter!(r => r.name == "clerk").front.users == 2);
    a.deleteRole(admin, "maint");

    // Jemand muss den Bereich verwalten können: auch eine Rollenänderung darf das nicht verhindern
    a.saveRole(admin, "access", "", ["manageAccess"]);
    a.createUser(admin, "ann", pw, "access");
    a.updateUser(admin, "admin", "viewer", true);
    auto ann = a.authenticate(a.login("", "ann", pw).token);
    assertThrown(a.saveRole(ann, "access", "", ["select"])); // letzter Weg zu manageAccess
    assertThrown(a.updateUser(ann, "ann", "viewer", true));
    assertThrown(a.deleteUser(ann, "ann"));
    a.updateUser(ann, "admin", "admin", true);
    a.saveRole(ann, "access", "", ["select"]);

    // Rechte ohne manageAccess: keine Verwaltung
    assertThrown!AccessDenied(a.listRoles(carl));
    assertThrown!AccessDenied(a.setGrants(carl, "carl", [TableGrant("orders", "admin")]));

    // Serverrollen: eigene Rolle mit viewTenants, aber ohne manageTenants
    a.createUser(root, "olga", pw, "ops");
    auto olga = a.authenticate(a.login("system", "olga", pw).token);
    assert(olga.can(Permission.viewTenants) && !olga.can(Permission.manageTenants) && !olga.can(Permission.manageAccess));

    // Mandanten sehen ihre Rollen gegenseitig nicht; Entfernen eines Mandanten entfernt seine Rollen
    a.provisionAdmin("acme", "admin", pw);
    auto acme = a.authenticate(a.login("acme", "admin", pw).token);
    assert(!a.listRoles(acme).canFind!(r => r.name == "clerk"));
    a.saveRole(acme, "clerk", "", ["select"]);
    a.removeTenant("acme");
    assert(roles.load().all!(r => r.tenant != "acme"));
    assert(a.listRoles(admin).canFind!(r => r.name == "clerk"));

    // Alles übersteht einen Neustart
    auto restarted = new AccessService(users, new FakeCrypto, null, null, roles);
    auto again = restarted.authenticate(restarted.login("", "tina", pw).token);
    assert(again.can(Permission.update, "orders") && !again.can(Permission.select, "secret"));
}
