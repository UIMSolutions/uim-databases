module uim.hdb.application.access_service;

import uim.hdb.application.ports;
import uim.hdb.domain.entities.user;
import core.time : Duration, hours, minutes, MonoTime;
import std.algorithm : all, canFind, count, map, sort;
import std.array : array;
import std.ascii : isAlphaNum;
import std.digest : toHexString;
import std.digest.sha : sha256Of;
import std.exception : enforce;
import std.string : strip, toLower;

/// Anmeldung, Sitzungen und Benutzerverwaltung. Sitzungen liegen nur im Speicher, ein Neustart meldet alle ab.
/// Die Rolle wird bei jeder Anfrage aus dem Benutzer gelesen, Änderungen wirken also sofort.
final class AccessService : IAccessUseCase {
    enum minPasswordLength = 12;
    private enum sessionLifetime = 12.hours;
    private enum maxFailures = 5; // Fehlversuche je Name, bevor er gesperrt wird
    private enum lockout = 1.minutes;
    private enum maxTrackedNames = 10_000;
    private enum maxConcurrentLogins = 4; // Passwort-Hashing ist teuer: schützt die Worker-Threads

    private struct Session {
        string user;
        MonoTime expires;
    }

    private struct Failures {
        int count;
        MonoTime lockedUntil;
    }

    private IUserStore store;
    private ICredentialCrypto crypto;
    private MonoTime delegate() now;
    private User[string] users;
    private Session[string] sessions; // Schlüssel: SHA-256 des Tokens
    private Failures[string] failures;
    private string dummyHash; // unbekannte Namen kosten dieselbe Zeit wie bekannte
    private int loginsInFlight;

    this(IUserStore store, ICredentialCrypto crypto, MonoTime delegate() now = null) {
        this.store = store;
        this.crypto = crypto;
        this.now = now !is null ? now : () => MonoTime.currTime;
        foreach (u; store.load())
            users[u.name] = u;
        dummyHash = crypto.hashPassword(crypto.randomSecret());
    }

    /// Legt beim ersten Start den Administrator an. Ohne vorgegebenes Passwort wird eines erzeugt und
    /// zurückgegeben, damit es einmalig angezeigt werden kann; sonst ist das Ergebnis leer.
    string bootstrap(string name, string password) {
        if (users.length)
            return "";
        auto generated = password.length ? "" : crypto.randomSecret();
        auto normalized = validName(name);
        commit(User(normalized, crypto.hashPassword(password.length ? password : generated), Role.admin));
        return generated;
    }

    LoginResult login(string name, string password) {
        auto key = name.strip.toLower;
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
        if (user is null || !matches || !user.active) {
            recordFailure(key);
            throw new AuthenticationRequired("Invalid user name or password");
        }
        failures.remove(key);
        pruneSessions();
        auto token = crypto.randomSecret();
        sessions[digest(token)] = Session(user.name, now() + sessionLifetime);
        return LoginResult(token, principalOf(*user), sessionLifetime.total!"seconds");
    }

    void logout(string token) {
        sessions.remove(digest(token));
    }

    Principal authenticate(string token) {
        if (token.length == 0)
            return Principal.init;
        auto id = digest(token);
        auto session = id in sessions;
        if (session is null)
            return Principal.init;
        auto user = session.user in users;
        if (session.expires <= now() || user is null || !user.active) {
            sessions.remove(id);
            return Principal.init;
        }
        return principalOf(*user);
    }

    void changeOwnPassword(Principal actor, string current, string replacement) {
        requireRole(actor, Role.viewer);
        auto user = actor.name in users;
        enforce!AuthenticationRequired(user !is null);
        enforce(crypto.verifyPassword(current, user.passwordHash), "Current password is wrong");
        setPassword(*user, replacement);
    }

    UserInfo[] listUsers(Principal actor) {
        requireRole(actor, Role.admin);
        auto result = users.values.map!(u => info(u)).array;
        result.sort!((a, b) => a.name < b.name);
        return result;
    }

    UserInfo createUser(Principal actor, string name, string password, Role role) {
        requireRole(actor, Role.admin);
        auto normalized = validName(name);
        enforce((normalized in users) is null, "User already exists: " ~ normalized);
        validPassword(password);
        auto user = User(normalized, crypto.hashPassword(password), role);
        commit(user);
        return info(user);
    }

    UserInfo updateUser(Principal actor, string name, Role role, bool active) {
        requireRole(actor, Role.admin);
        auto user = find(name);
        if (role != Role.admin || !active)
            requireOtherAdmin(user);
        user.role = role;
        user.active = active;
        commit(user);
        if (!active)
            revokeSessions(user.name);
        return info(user);
    }

    void resetPassword(Principal actor, string name, string replacement) {
        requireRole(actor, Role.admin);
        setPassword(find(name), replacement);
    }

    void deleteUser(Principal actor, string name) {
        requireRole(actor, Role.admin);
        auto user = find(name);
        requireOtherAdmin(user);
        auto remaining = users.dup;
        remaining.remove(user.name);
        store.save(remaining.values);
        users = remaining;
        revokeSessions(user.name);
    }

    private void setPassword(User user, string replacement) {
        validPassword(replacement);
        user.passwordHash = crypto.hashPassword(replacement);
        commit(user);
        revokeSessions(user.name); // gestohlene Sitzungen enden mit dem Passwort
    }

    /// Erst speichern, dann im Speicher übernehmen: schlägt das Schreiben fehl, bleibt alles beim Alten.
    private void commit(User user) {
        auto next = users.dup;
        next[user.name] = user;
        store.save(next.values);
        users = next;
    }

    private User find(string name) {
        auto user = name.strip.toLower in users;
        enforce(user !is null, "User not found: " ~ name);
        return *user;
    }

    /// Ohne aktiven Administrator ließe sich das System nicht mehr verwalten.
    private void requireOtherAdmin(User user) {
        if (user.role != Role.admin || !user.active)
            return;
        enforce(users.values.count!(u => u.role == Role.admin && u.active) > 1, "Cannot remove the last active admin");
    }

    private void revokeSessions(string name) {
        string[] ids;
        foreach (id, s; sessions)
            if (s.user == name)
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

private Principal principalOf(User user) {
    return Principal(user.name, user.role, true);
}

private UserInfo info(User user) {
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
        User[] saved;
        bool failing;
        User[] load() {
            return saved;
        }

        void save(User[] users) {
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
    assert(root.authenticated && root.role == Role.admin);
    assert(!a.authenticate("forged").authenticated);
    assert(!a.authenticate("").authenticated);

    // Benutzerverwaltung nur für Administratoren
    auto long1 = "correct-horse-1";
    auto long2 = "correct-horse-2";
    a.createUser(root, "ed", long1, Role.editor);
    auto ed = a.authenticate(a.login("ed", long1).token);
    assert(ed.role == Role.editor);
    assertThrown!AccessDenied(a.listUsers(ed));
    assertThrown!AccessDenied(a.createUser(ed, "x", long1, Role.admin));
    assertThrown!AccessDenied(a.updateUser(ed, "ed", Role.admin, true)); // keine Selbstbeförderung
    assertThrown!AccessDenied(a.resetPassword(ed, "admin", long2));
    assertThrown!AccessDenied(a.deleteUser(ed, "admin"));
    assertThrown!AuthenticationRequired(a.listUsers(Principal.init));

    assertThrown(a.createUser(root, "ed", long1, Role.viewer)); // doppelt
    assertThrown(a.createUser(root, "bad name", long1, Role.viewer));
    assertThrown(a.createUser(root, "shorty", "short", Role.viewer));
    assert(a.listUsers(root).map!(u => u.name).array == ["admin", "ed"]);

    // Rollenänderung wirkt in laufenden Sitzungen sofort
    auto edSession = a.login("ed", long1).token;
    a.updateUser(root, "ed", Role.viewer, true);
    assert(a.authenticate(edSession).role == Role.viewer);

    // Deaktivieren beendet Sitzungen und verhindert die Anmeldung
    a.updateUser(root, "ed", Role.viewer, false);
    assert(!a.authenticate(edSession).authenticated);
    assertThrown!AuthenticationRequired(a.login("ed", long1));
    a.updateUser(root, "ed", Role.editor, true);

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
    assertThrown(a.updateUser(root, "admin", Role.editor, true));
    assertThrown(a.updateUser(root, "admin", Role.admin, false));
    a.updateUser(root, "ed", Role.admin, true);
    a.updateUser(root, "admin", Role.viewer, true);
    a.updateUser(a.authenticate(a.login("ed", long2).token), "admin", Role.admin, true);

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
    assertThrown(a.createUser(root, "lost", long1, Role.viewer));
    store.failing = false;
    assert(!a.listUsers(root).map!(u => u.name).canFind("lost"));

    // Benutzer überstehen einen Neustart, Sitzungen nicht
    token = a.login("ed", long2).token;
    auto restarted = new AccessService(store, new FakeCrypto, () => clock);
    assert(!restarted.authenticate(token).authenticated);
    assert(restarted.login("ed", long2).principal.role == Role.admin);
}
