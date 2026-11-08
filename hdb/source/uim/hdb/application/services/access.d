module uim.hdb.application.services.access;

import uim.hdb;
import core.time : Duration, hours, minutes, MonoTime;
import std.algorithm : all, canFind, count, filter, map, sort;
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
    private Session[string] sessions; // Schlüssel: SHA-256 des Tokens
    private Failures[string] failures;
    private string dummyHash; // unbekannte Namen kosten dieselbe Zeit wie bekannte
    private int loginsInFlight;

    /// `tenantActive` sagt, ob ein Mandant existiert und aktiv ist; ohne gelten alle als aktiv.
    this(IUserStore store, ICredentialCrypto crypto, MonoTime delegate() now = null,
        bool delegate(string) tenantActive = null) {
        this.store = store;
        this.crypto = crypto;
        this.now = now !is null ? now : () => MonoTime.currTime;
        this.tenantActive = tenantActive !is null ? tenantActive : (string) => true;
        foreach (u; store.load())
            users[userKey(u.tenant, u.name)] = u;
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
        commit(HdbUser(normalized, crypto.hashPassword(password.length ? password : generated), HdbRole.admin, true, tenant));
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
        requireRole(actor, HdbRole.viewer);
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
        requireRole(actor, HdbRole.admin);
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
    UserInfo createUser(Principal actor, string name, string password, HdbRole role) {
        requireRole(actor, HdbRole.admin);
        return info(addUser(actor.tenant, name, password, role));
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
    UserInfo updateUser(Principal actor, string name, HdbRole role, bool active) {
        requireRole(actor, HdbRole.admin);
        auto user = find(actor.tenant, name);
        if (role != HdbRole.admin || !active)
            requireOtherAdmin(user);
        user.role = role;
        user.active = active;
        commit(user);
        if (!active)
            revokeSessions(userKey(user.tenant, user.name));
        return info(user);
    }

    /** 
     *  Reset the password of an existing user of the actor's tenant.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the user whose password is to be reset.
     *  @param replacement The new password to set.
    **/
    void resetPassword(Principal actor, string name, string replacement) {
        requireRole(actor, HdbRole.admin);
        setPassword(find(actor.tenant, name), replacement);
    }

    /** 
     *  Delete an existing user of the actor's tenant.
     *
     *  @param actor The principal representing the currently authenticated user.
     *  @param name The name of the user to delete.
    **/
    void deleteUser(Principal actor, string name) {
        requireRole(actor, HdbRole.admin);
        auto user = find(actor.tenant, name);
        requireOtherAdmin(user);
        auto key = userKey(user.tenant, user.name);
        auto remaining = users.dup;
        remaining.remove(key);
        store.save(remaining.values);
        users = remaining;
        revokeSessions(key);
    }

    // ITenantAccounts: ohne Rollenprüfung, die macht TenantService

    void provisionAdmin(string tenant, string name, string password) {
        addUser(tenant, name, password, HdbRole.admin);
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
    }

    size_t userCount(string tenant) {
        return users.values.count!(u => u.tenant == tenant);
    }

    private HdbUser addUser(string tenant, string name, string password, HdbRole role) {
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

    /// Without an active administrator, the tenant could no longer be managed.
    private void requireOtherAdmin(HdbUser user) {
        if (user.role != HdbRole.admin || !user.active)
            return;
        enforce(users.values.count!(u => u.tenant == user.tenant && u.role == HdbRole.admin && u.active) > 1,
            "Cannot remove the last active admin");
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

private Principal principalOf(HdbUser user) {
    return Principal(user.name, user.role, true, user.tenant);
}

private UserInfo info(HdbUser user) {
    return UserInfo(user.name, user.role, user.active);
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
    assert(root.authenticated && root.role == HdbRole.admin);
    assert(!a.authenticate("forged").authenticated);
    assert(!a.authenticate("").authenticated);

    // Benutzerverwaltung nur für Administratoren
    auto long1 = "correct-horse-1";
    auto long2 = "correct-horse-2";
    a.createUser(root, "ed", long1, HdbRole.editor);
    auto ed = a.authenticate(a.login("ed", long1).token);
    assert(ed.role == HdbRole.editor);
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
    assert(a.authenticate(edSession).role == HdbRole.viewer);

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
    assert(restarted.login("ed", long2).principal.role == HdbRole.admin);
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
    assert(acme.tenant == "acme" && acme.role == HdbRole.admin);
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
    assert(a.authenticate(a.login("acme", "ed", pw).token).role == HdbRole.editor);
    assert(a.authenticate(a.login("globex", "ed", "globex-ed-password").token).role == HdbRole.viewer);

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
