module uim.hdb.application.services.replication;

import uim.hdb;
import core.time : seconds;
import std.algorithm : max, min;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.exception : enforce;
import std.string : startsWith, strip;
import std.uuid : randomUUID;

/// Änderungsstrom einer Quelle: jede bestätigte Änderung bekommt eine fortlaufende Nummer und bleibt eine Weile
/// abrufbar. Er liegt nur im Speicher. Die Epoche wechselt bei jedem Start und jeder Wiederherstellung; ein Ziel mit
/// einer anderen Epoche oder einer zu alten Nummer braucht deshalb einen vollständigen Stand.
final class ChangeFeed : IChangeSink {
    private size_t retain;
    private string currentEpoch;
    private ulong last; // zuletzt vergebene Nummer
    private Change[] buffer; // aufsteigend und lückenlos, das letzte Element hat die Nummer last

    this(size_t retain = 10_000) {
        this.retain = max(retain, 1);
        currentEpoch = randomUUID().toString;
    }

    void committed(string[] statements) {
        synchronized (this) {
            buffer ~= Change(++last, statements.dup);
            if (buffer.length > retain + retain / 4) // gelegentlich kürzen statt bei jeder Änderung kopieren
                buffer = buffer[$ - retain .. $].dup;
        }
    }

    void replaced() {
        synchronized (this) {
            currentEpoch = randomUUID().toString;
            last = 0;
            buffer = null;
        }
    }

    string epoch() {
        synchronized (this)
            return currentEpoch;
    }

    ulong sequence() {
        synchronized (this)
            return last;
    }

    /// Älteste noch lieferbare Nummer; ohne gespeicherte Änderungen die nächste.
    ulong retainedFrom() {
        synchronized (this)
            return buffer.length ? buffer[0].sequence : last + 1;
    }

    /// Änderungen nach der Nummer `after`, höchstens `limit`.
    ChangeBatch since(string epoch, ulong after, size_t limit) {
        synchronized (this) {
            auto batch = ChangeBatch(currentEpoch, last);
            immutable first = buffer.length ? buffer[0].sequence : last + 1;
            if (epoch != currentEpoch || after > last || after + 1 < first) {
                batch.resync = true;
                return batch;
            }
            if (after == last)
                return batch;
            auto start = cast(size_t)(after + 1 - first);
            batch.changes = buffer[start .. min(buffer.length, start + max(limit, 1))].dup;
            return batch;
        }
    }
}

/// Replikation eines Mandanten, in beide Richtungen: als Quelle liefert sie Stand und Änderungen, als Ziel holt sie
/// beides von einer Quelle und spielt es ein. Ein Ziel ist für Schreibzugriffe gesperrt (siehe TenantDatabases), sonst
/// liefen die Stände auseinander. Ein Ziel ist zugleich Quelle: Ketten A -> B -> C funktionieren.
///
/// Nach einem Neustart des Ziels holt es immer erst einen vollständigen Stand: die Position wird nicht gespeichert,
/// weil sie sich nicht atomar mit den Daten speichern lässt.
final class TenantReplication {
    enum maxBatch = 500;
    private enum maxBatchesPerRun = 20; // danach kommen andere Mandanten an die Reihe
    private enum errorDelay = 5.seconds;

    private SqlService core;
    private ChangeFeed feed;
    private IReplicationConfigStore store;
    private IReplicationClient client;
    private SysTime delegate() now;

    private ReplicationConfig config;
    private string token;
    private bool positioned; // Daten und Position passen zur Quelle
    private string sourceEpoch;
    private ulong applied;
    private string state = "off";
    private string lastSync, lastError;
    private bool running;
    private SysTime nextRun;

    this(SqlService core, ChangeFeed feed, IReplicationConfigStore store, IReplicationClient client,
        SysTime delegate() now = null) {
        this.core = core;
        this.feed = feed;
        this.store = store;
        this.client = client;
        this.now = now !is null ? now : () => Clock.currTime(UTC());
        config = store.load();
        if (config.enabled)
            state = "connecting";
    }

    /// Ein Ziel nimmt keine Schreibzugriffe an.
    bool isReplica() const {
        return config.enabled;
    }

    string sourceUrl() const {
        return config.url;
    }

    // Quelle

    /// Stand und Position gehören zusammen: beide unter der Sperre des Kerns, also ohne Commit dazwischen.
    ReplicationSnapshot snapshot() {
        synchronized (core) {
            auto tables = core.snapshot();
            return ReplicationSnapshot(feed.epoch, feed.sequence, tables);
        }
    }

    ChangeBatch changes(string epoch, ulong since, size_t limit) {
        return feed.since(epoch, since, min(max(limit, 1), maxBatch));
    }

    ReplicationStatus status() {
        ReplicationStatus s;
        s.epoch = feed.epoch;
        s.sequence = feed.sequence;
        s.retainedFrom = feed.retainedFrom;
        s.replica = config.enabled;
        s.url = config.url;
        s.sourceTenant = config.tenant;
        s.user = config.user;
        s.intervalSeconds = config.intervalSeconds;
        s.state = state;
        s.sourceEpoch = sourceEpoch;
        s.appliedSequence = applied;
        s.lastSync = lastSync;
        s.lastError = lastError;
        return s;
    }

    // Ziel

    /// Prüft alles, bevor gespeichert wird. Ein leeres Passwort behält das bisherige, aber nur für dieselbe
    /// Quelle und denselben Benutzer: ein gespeichertes Passwort geht nie an einen anderen Server.
    ReplicationStatus configure(ReplicationConfig next) {
        enforce(client !is null, "Replication is not available on this server");
        next.url = next.url.strip;
        while (next.url.length && next.url[$ - 1] == '/')
            next.url = next.url[0 .. $ - 1];
        enforce(next.url.startsWith("http://") || next.url.startsWith("https://"),
            "The source URL must start with http:// or https://");
        client.validate(next.url);
        next.tenant = next.tenant.strip.length ? validTenantName(next.tenant) : defaultTenant;
        enforce(next.tenant != systemTenant, "The system area has no data to replicate");
        next.user = next.user.strip;
        enforce(next.user.length, "Enter the user name for the source");
        enforce(next.intervalSeconds >= 1 && next.intervalSeconds <= 3600, "The interval must be between 1 and 3600 seconds");
        if (next.password.length == 0) {
            enforce(config.password.length && config.url == next.url && config.tenant == next.tenant
                    && config.user == next.user, "Enter the password for the source");
            next.password = config.password;
        }
        next.enabled = true;
        store.save(next);
        config = next;
        token = null;
        positioned = false;
        state = "connecting";
        lastError = null;
        nextRun = SysTime.init;
        return status();
    }

    /// Der Mandant behält seinen Stand und ist wieder beschreibbar.
    ReplicationStatus stop() {
        auto next = config;
        next.enabled = false;
        store.save(next);
        config = next;
        token = null;
        positioned = false;
        state = "off";
        return status();
    }

    ReplicationStatus resync() {
        positioned = false;
        nextRun = SysTime.init;
        return status();
    }

    /// Ein Lauf: anmelden, falls nötig vollständigen Stand holen, dann Änderungen einspielen.
    /// Gibt eine Fehlermeldung zurück, wenn ein Fehler neu auftritt, sonst null; derselbe Fehler wird nicht wiederholt.
    string tick() {
        if (!config.enabled || running || now() < nextRun)
            return null;
        running = true;
        scope (exit)
            running = false;
        try {
            try
                pull();
            catch (AuthenticationRequired) {
                token = null; // abgelaufene Sitzung: einmal neu anmelden
                pull();
            }
            lastError = null;
            nextRun = now() + config.intervalSeconds.seconds;
            return null;
        } catch (Exception e) {
            immutable repeated = state == "error" && lastError == e.msg;
            state = "error";
            lastError = e.msg;
            nextRun = now() + max(config.intervalSeconds.seconds, errorDelay);
            return repeated ? null : e.msg;
        }
    }

    private void pull() {
        if (token.length == 0)
            token = client.login(config.url, config.tenant, config.user, config.password);
        foreach (round; 0 .. maxBatchesPerRun) {
            if (!positioned)
                fullSync();
            auto batch = client.changes(config.url, token, sourceEpoch, applied, maxBatch);
            if (!config.enabled)
                return; // während des Abrufs gestoppt
            if (batch.resync) {
                positioned = false;
                continue;
            }
            foreach (change; batch.changes)
                apply(change);
            state = "streaming";
            lastSync = now().toISOExtString;
            if (batch.changes.length < maxBatch)
                return;
        }
    }

    private void fullSync() {
        state = "syncing";
        auto snap = client.snapshot(config.url, token);
        enforce(config.enabled, "Replication was stopped");
        core.restore(snap.tables); // meldet replaced: eigene Ziele holen danach ebenfalls einen vollständigen Stand
        sourceEpoch = snap.epoch;
        applied = snap.sequence;
        positioned = true;
        state = "streaming";
        lastSync = now().toISOExtString;
    }

    /// Eine Änderung der Quelle, als Ganzes: mehrere Anweisungen in einer Transaktion. Scheitert sie oder passt die
    /// Nummer nicht, holt der nächste Lauf einen vollständigen Stand.
    private void apply(Change change) {
        if (change.sequence != applied + 1) {
            positioned = false;
            throw new Exception("Gap in the change stream, a full sync follows");
        }
        try {
            if (change.statements.length == 1)
                core.execute(change.statements[0]);
            else {
                auto tx = core.execute("BEGIN").transaction;
                try {
                    foreach (statement; change.statements)
                        core.executeIn(tx, statement);
                    core.executeIn(tx, "COMMIT");
                } catch (Exception e) {
                    try
                        core.executeIn(tx, "ROLLBACK");
                    catch (Exception) {
                    }
                    throw e;
                }
            }
        } catch (Exception e) {
            positioned = false;
            throw new Exception("Change " ~ change.sequence.to!string ~ " could not be applied, a full sync follows: " ~ e.msg);
        }
        applied = change.sequence;
    }
}

/// Einstellungen nur im Speicher, für Ablagen ohne Dateien.
final class MemoryReplicationConfigStore : IReplicationConfigStore {
    private ReplicationConfig config;

    ReplicationConfig load() {
        return config;
    }

    void save(ReplicationConfig next) {
        config = next;
    }
}

unittest {
    import std.algorithm : map;
    import std.array : array;

    auto feed = new ChangeFeed(4);
    auto epoch = feed.epoch;
    assert(feed.since(epoch, 0, 10).changes.length == 0 && !feed.since(epoch, 0, 10).resync);
    foreach (i; 1 .. 4)
        feed.committed(["S" ~ i.to!string]);
    auto batch = feed.since(epoch, 0, 10);
    assert(batch.sequence == 3 && batch.changes.map!(c => c.sequence).array == [1, 2, 3]);
    assert(feed.since(epoch, 1, 1).changes.map!(c => c.statements[0]).array == ["S2"]);
    assert(feed.since(epoch, 3, 10).changes.length == 0);
    assert(feed.since("other", 0, 10).resync);
    assert(feed.since(epoch, 9, 10).resync); // weiter als die Quelle

    // Alte Änderungen fallen heraus: wer zu weit zurückliegt, braucht einen vollständigen Stand
    foreach (i; 4 .. 11)
        feed.committed(["S" ~ i.to!string]);
    assert(feed.sequence == 10 && feed.retainedFrom >= 6 && feed.retainedFrom <= 7);
    assert(feed.since(epoch, 1, 10).resync);
    assert(feed.since(epoch, 8, 10).changes.map!(c => c.sequence).array == [9, 10]);

    // Wiederherstellung: neue Epoche, Zählung beginnt neu
    feed.replaced();
    assert(feed.epoch != epoch && feed.sequence == 0 && feed.since(epoch, 10, 10).resync);
}

/// Quelle und Ziel im Speicher, verbunden über einen Client, der direkt die Quelle aufruft.
unittest {
    import std.exception : assertThrown;

    static class Direct : IReplicationClient {
        TenantReplication source;
        string password = "pw";
        bool down;
        int logins;
        void validate(string url) {
            enforce(url != "http://forbidden", "Host not allowed");
        }

        string login(string url, string tenant, string user, string password) {
            enforce(!down, "connection refused");
            if (password != this.password)
                throw new AuthenticationRequired("Invalid tenant, user name or password");
            ++logins;
            return "token";
        }

        ReplicationSnapshot snapshot(string url, string token) {
            enforce(!down, "connection refused");
            return source.snapshot();
        }

        ChangeBatch changes(string url, string token, string epoch, ulong since, size_t limit) {
            enforce(!down, "connection refused");
            return source.changes(epoch, since, limit);
        }
    }

    auto clock = SysTime(0, UTC());
    auto primaryCore = new SqlService(new MemoryTableRepository);
    auto primaryFeed = new ChangeFeed(100);
    primaryCore.changeSink(primaryFeed);
    auto primary = new TenantReplication(primaryCore, primaryFeed, new MemoryReplicationConfigStore, null, () => clock);
    auto client = new Direct;
    client.source = primary;

    auto replicaCore = new SqlService(new MemoryTableRepository);
    auto replicaFeed = new ChangeFeed(100);
    replicaCore.changeSink(replicaFeed);
    auto configs = new MemoryReplicationConfigStore;
    auto replica = new TenantReplication(replicaCore, replicaFeed, configs, client, () => clock);

    long count(SqlService s, string table) {
        return s.execute("SELECT COUNT(*) FROM " ~ table).rows[0][0].get!long;
    }

    // Bestehende Daten kommen mit dem vollständigen Stand
    primaryCore.execute("CREATE TABLE t (id INTEGER, n VARCHAR)");
    primaryCore.execute("INSERT INTO t VALUES (1, 'a')");
    assert(primaryFeed.sequence == 2);

    assertThrown(replica.configure(ReplicationConfig(true, "ftp://x", "", "u", "pw")));
    assertThrown(replica.configure(ReplicationConfig(true, "http://forbidden", "", "u", "pw")));
    assertThrown(replica.configure(ReplicationConfig(true, "http://p", "system", "u", "pw")));
    assertThrown(replica.configure(ReplicationConfig(true, "http://p", "", "u", ""))); // Passwort fehlt
    auto s = replica.configure(ReplicationConfig(true, "http://p/", "", "u", "pw", 2));
    assert(s.replica && s.url == "http://p" && s.sourceTenant == defaultTenant && s.state == "connecting");
    assert(configs.load().enabled && replica.isReplica);

    assert(replica.tick() is null);
    assert(count(replicaCore, "t") == 1 && replica.status().state == "streaming");
    assert(replica.status().appliedSequence == 2 && replica.status().sourceEpoch == primaryFeed.epoch);

    // Einzelne Änderungen und Transaktionen, auch für mehrere Anweisungen
    primaryCore.execute("INSERT INTO t VALUES (2, 'b')");
    auto tx = primaryCore.execute("BEGIN").transaction;
    primaryCore.executeIn(tx, "UPDATE t SET n = 'x' WHERE id = 1");
    primaryCore.executeIn(tx, "DELETE FROM t WHERE id = 2");
    primaryCore.executeIn(tx, "COMMIT");
    tx = primaryCore.execute("BEGIN").transaction;
    primaryCore.executeIn(tx, "INSERT INTO t VALUES (3, 'gone')");
    primaryCore.executeIn(tx, "ROLLBACK"); // erscheint nie im Strom
    assert(primaryFeed.sequence == 4);
    assert(replica.tick() is null); // noch nicht fällig
    clock += 2.seconds;
    assert(replica.tick() is null);
    assert(replicaCore.execute("SELECT n FROM t").rows.length == 1);
    assert(replicaCore.execute("SELECT n FROM t WHERE id = 1").rows[0][0].get!string == "x");
    assert(replica.status().appliedSequence == 4);

    // Ein Ziel ist selbst Quelle: seine eingespielten Änderungen stehen in seinem Strom
    assert(replicaFeed.sequence == 2);

    // Die Quelle stellt wieder her: neue Epoche, das Ziel holt einen vollständigen Stand
    auto saved = primaryCore.snapshot();
    primaryCore.execute("INSERT INTO t VALUES (5, 'later')");
    primaryCore.restore(saved);
    clock += 2.seconds;
    assert(replica.tick() is null);
    assert(count(replicaCore, "t") == 1 && replica.status().sourceEpoch == primaryFeed.epoch);

    // Ausfall: einmal melden, dann ruhig weiter versuchen, danach aufholen
    client.down = true;
    primaryCore.execute("INSERT INTO t VALUES (6, 'f')");
    clock += 2.seconds;
    assert(replica.tick() == "connection refused");
    assert(replica.status().state == "error");
    clock += 5.seconds;
    assert(replica.tick() is null); // derselbe Fehler wird nicht wiederholt
    client.down = false;
    clock += 5.seconds;
    assert(replica.tick() is null && count(replicaCore, "t") == 2 && replica.status().state == "streaming");

    // Abgelaufene Sitzung: neu anmelden; falsches Passwort: Fehler
    replica.token = "";
    primaryCore.execute("INSERT INTO t VALUES (7, 'g')");
    clock += 2.seconds;
    assert(replica.tick() is null && count(replicaCore, "t") == 3);
    client.password = "changed";
    replica.token = "";
    clock += 2.seconds;
    assert(replica.tick() == "Invalid tenant, user name or password");
    client.password = "pw";

    // Lokal abweichender Stand: die Änderung scheitert, es folgt ein vollständiger Stand
    replicaCore.execute("DROP TABLE t");
    primaryCore.execute("INSERT INTO t VALUES (8, 'h')");
    clock += 10.seconds;
    assert(replica.tick() !is null);
    clock += 10.seconds;
    assert(replica.tick() is null && count(replicaCore, "t") == 4);

    // Das Passwort bleibt nur für dieselbe Quelle erhalten
    assert(replica.configure(ReplicationConfig(true, "http://p", "default", "u", "", 5)).intervalSeconds == 5);
    assertThrown(replica.configure(ReplicationConfig(true, "http://other", "default", "u", "")));
    assert(configs.load().password == "pw");

    // Stoppen: Daten bleiben, keine Abrufe mehr
    assert(!replica.stop().replica && !configs.load().enabled && !replica.isReplica);
    primaryCore.execute("INSERT INTO t VALUES (9, 'i')");
    clock += 60.seconds;
    assert(replica.tick() is null && count(replicaCore, "t") == 4);
}
