module uim.hdb.application.services.backup;

import uim.hdb;
import core.time : Duration, hours, minutes;
import std.algorithm : canFind, filter;
import std.array : array, replace;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.exception : enforce;
import std.string : strip, toLower;

@safe:

/// Sichern und Wiederherstellen. Die Rolle wird hier geprüft: jeder eingehende Adapter ist damit abgedeckt,
/// ohne Identität wird abgelehnt. Benutzer gehören nicht zur Sicherung: eine Wiederherstellung soll weder aussperren
/// noch alte Passwörter zurückbringen, und die Dateien bleiben frei von Passwort-Hashes.
final class BackupService : IBackupUseCase, IBackupScheduler {
    private enum retryDelay = 5.minutes; // nach einem Fehler nicht bei jedem Takt erneut versuchen
    private enum scheduledLabel = "scheduled";
    private enum safetyLabel = "before-restore";

    private IDatabaseSnapshots database;
    private IBackupStore store;
    private Principal delegate() @safe current;
    private SysTime delegate() @safe now;
    private SysTime retryAfter;

    this(IDatabaseSnapshots database, IBackupStore store, Principal delegate() @safe current, SysTime delegate() @safe now = null) {
        this.database = database;
        this.store = store;
        this.current = current;
        this.now = now !is null ? now : () => Clock.currTime(UTC());
    }

    BackupInfo[] list() {
        requirePermission(current(), Permission.manageBackups);
        return store.list();
    }

    BackupInfo create(string label) {
        requirePermission(current(), Permission.manageBackups);
        // Diese Namen löscht die Aufbewahrung: eine eigene Sicherung darf nie darunter fallen
        auto normalized = label.strip.toLower.replace(" ", "-");
        enforce(normalized != scheduledLabel && normalized != safetyLabel, "This label is reserved: " ~ label);
        return store.save(label, database.snapshot());
    }

    /// Reihenfolge: Sicherung prüfen, Sicherheitskopie anlegen, ersetzen, im Fehlerfall zurückspielen.
    /// Die Sicherheitskopie bleibt liegen, damit sich auch eine erfolgreiche Wiederherstellung rückgängig machen lässt.
    BackupInfo restore(string name) {
        requirePermission(current(), Permission.manageBackups);
        auto target = store.load(name);
        auto previous = database.snapshot();
        auto safety = store.save(safetyLabel, previous);
        try
            database.restore(target);
        catch (Exception e) {
            try
                database.restore(previous);
            catch (Exception) {
                throw new Exception("Restore failed and the previous state could not be put back. Restore "
                    ~ safety.name ~ " manually. Cause: " ~ e.msg);
            }
            throw new Exception("Restore failed, the previous state was put back: " ~ e.msg);
        }
        // Die Wiederherstellung ist gelungen: Aufräumen darf sie nicht mehr als Fehler melden
        try
            prune("safety", store.loadSchedule().keepSafety);
        catch (Exception) {
        }
        return safety;
    }

    void remove(string name) {
        requirePermission(current(), Permission.manageBackups);
        store.remove(name);
    }

    string download(string name) {
        requirePermission(current(), Permission.manageBackups);
        return store.read(name);
    }

    BackupInfo upload(string content) {
        requirePermission(current(), Permission.manageBackups);
        return store.store(content);
    }

    BackupSchedule schedule() {
        requirePermission(current(), Permission.manageBackups);
        return withNextRun(store.loadSchedule());
    }

    BackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety) {
        requirePermission(current(), Permission.manageBackups);
        enforce(intervalHours >= 1 && intervalHours <= 8760, "The interval must be between 1 and 8760 hours");
        enforce(keepScheduled >= 1 && keepScheduled <= 1000, "Keep between 1 and 1000 scheduled backups");
        enforce(keepSafety >= 1 && keepSafety <= 1000, "Keep between 1 and 1000 safety backups");
        auto s = store.loadSchedule();
        s.enabled = enabled;
        s.intervalHours = intervalHours;
        s.keepScheduled = keepScheduled;
        s.keepSafety = keepSafety;
        store.saveSchedule(s);
        retryAfter = SysTime.init; // eine neue Einstellung soll nicht auf die Wartezeit eines alten Fehlers warten
        prune("scheduled", keepScheduled);
        prune("safety", keepSafety);
        return withNextRun(s);
    }

    /// Gelöscht wird erst nach einer erfolgreichen neuen Sicherung: ein voller Datenträger kostet keine alten Stände.
    string tick() {
        auto s = store.loadSchedule();
        auto time = now();
        time.fracSecs = typeof(time.fracSecs).zero;
        if (!s.enabled || time < retryAfter || (s.lastRun.length && time < dueAfter(s)))
            return null;
        try {
            auto tables = database.snapshot();
            if (tables.length == 0)
                return null; // nichts zu sichern, die Frist beginnt mit der ersten Tabelle
            store.save(scheduledLabel, tables);
            s.lastRun = time.toISOExtString;
            s.lastError = "";
            store.saveSchedule(s);
            prune("scheduled", s.keepScheduled);
            return null;
        } catch (Exception e) {
            retryAfter = time + retryDelay;
            s.lastError = e.msg;
            try
                store.saveSchedule(s);
            catch (Exception) {
            }
            return e.msg;
        }
    }

    private SysTime dueAfter(BackupSchedule s) {
        return SysTime.fromISOExtString(s.lastRun) + s.intervalHours.hours;
    }

    private BackupSchedule withNextRun(BackupSchedule s) {
        s.nextRun = !s.enabled ? "" : s.lastRun.length ? dueAfter(s).toISOExtString : "";
        return s;
    }

    /// Die Liste ist nach Name sortiert, also neueste zuerst.
    private void prune(string kind, int keep) {
        auto matching = store.list().filter!(b => b.kind == kind).array;
        if (matching.length > keep)
            foreach (b; matching[keep .. $])
                store.remove(b.name);
    }
}
