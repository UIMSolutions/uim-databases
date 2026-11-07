module uim.hdb.application.ports;

import uim.hdb;


/// Eingehender Port: was die Anwendung anbietet.
interface ISqlUseCase {
    QueryResult execute(string sql);
    /// Führt die Anweisung in der Transaktion txId aus (BEGIN, COMMIT, ROLLBACK sind normale Anweisungen).
    QueryResult executeIn(string txId, string sql);
    string[] listTables();
    void checkpoint();
    /// Synchroner Delta-Merge (inkl. Entfernen gelöschter Zeilen).
    void mergeDelta();
    /// Startet den Delta-Merge im Hintergrund; false, wenn schon einer läuft.
    bool mergeDeltaAsync();
    MergeStatus mergeStatus();
    TableStats[] stats();
}



struct LoginResult {
    string token;
    Principal principal;
    long expiresInSeconds;
}

/// Eingehender Port: Anmeldung und Benutzerverwaltung. `actor` ist die anfragende Identität.
interface IAccessUseCase {
    LoginResult login(string name, string password);
    void logout(string token);
    /// Identität zu einem Token; anonym, wenn es ungültig oder abgelaufen ist.
    Principal authenticate(string token);
    void changeOwnPassword(Principal actor, string current, string replacement);

    UserInfo[] listUsers(Principal actor);
    UserInfo createUser(Principal actor, string name, string password, HdbRole role);
    UserInfo updateUser(Principal actor, string name, HdbRole role, bool active);
    void resetPassword(Principal actor, string name, string replacement);
    void deleteUser(Principal actor, string name);
}

/// Stand einer Tabelle: alles, was eine Sicherung braucht.
struct TableSnapshot {
    string name;
    TableStorage storage;
    ColumnDef[] columns;
    Value[][] rows;
}

struct BackupInfo {
    string name, label, created;
    ulong size;
    long tables, rows;
    bool readable = true;
    string kind = "manual"; // manual, scheduled, safety oder uploaded
}

/// Zeitplan und Aufbewahrung. Nur Sicherungen der Arten scheduled und safety werden automatisch gelöscht.
struct BackupSchedule {
    bool enabled = true;
    int intervalHours = 24;
    int keepScheduled = 7;
    int keepSafety = 5;
    string lastRun, lastError; // ISO-Zeit in UTC; leer, wenn es das noch nicht gab
    string nextRun; // berechnet, wird nicht gespeichert
}

/// Die angeforderte Sicherung gibt es nicht (HTTP 404).
class BackupNotFound : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Eingehender Port: Sichern und Wiederherstellen, nur für die Rolle admin.
interface IBackupUseCase {
    BackupInfo[] list();
    BackupInfo create(string label);
    /// Ersetzt alle Tabellen durch die Sicherung; gibt die vorher angelegte Sicherheitskopie zurück.
    BackupInfo restore(string name);
    void remove(string name);
    /// Inhalt der Sicherungsdatei.
    string download(string name);
    /// Prüft eine hochgeladene Sicherung vollständig und legt sie ab.
    BackupInfo upload(string content);
    BackupSchedule schedule();
    BackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety);
}

/// Für den Zeitgeber der Anwendung. Läuft ohne Anfrage und damit ohne Identität, deshalb getrennt von IBackupUseCase:
/// kein eingehender Adapter bekommt diesen Weg an der Rollenprüfung vorbei zu sehen.
interface IBackupScheduler {
    /// Legt eine fällige Sicherung an; gibt eine Fehlermeldung zurück oder null.
    string tick();
}

/// Ausgehender Port: Ablage der Sicherungen.
interface IBackupStore {
    BackupInfo[] list();
    BackupInfo save(string label, TableSnapshot[] tables);
    /// Liest und prüft eine Sicherung; wirft bei beschädigtem Inhalt.
    TableSnapshot[] load(string name);
    string read(string name);
    BackupInfo store(string content);
    void remove(string name);
    BackupSchedule loadSchedule();
    void saveSchedule(BackupSchedule schedule);
}

/// Was die Sicherung vom Kern braucht. Nur BackupService sieht das: die Rechte prüft er selbst.
interface IDatabaseSnapshots {
    TableSnapshot[] snapshot();
    /// Ersetzt alle Tabellen. Prüft erst alles und ändert dann; bei offener Transaktion wird abgelehnt.
    void restore(TableSnapshot[] tables);
}

/// Ausgehender Port: dauerhafte Ablage der Benutzer.
interface IUserStore {
    HdbUser[] load();
    void save(HdbUser[] users);
}

/// Ausgehender Port: Kryptografie für Passwörter und Tokens.
interface ICredentialCrypto {
    string hashPassword(string password);
    bool verifyPassword(string password, string stored);
    /// Zufälliges, URL-sicheres Geheimnis.
    string randomSecret();
}

/// Ausgehender Port: was die Anwendung von der Infrastruktur braucht.
interface ITableRepository {
    bool exists(string name);
    ColumnTable get(string name);
    void save(ColumnTable table);
    void remove(string name);
    string[] list();
}

/// Optional für Repositories, die selbst auf die Platte schreiben. save und remove ändern dort nur den Speicher,
/// erst flush macht den Stand einer Tabelle dauerhaft. Der Kern ruft es am Commit-Punkt auf, also
/// nach jeder Anweisung oder beim COMMIT. Gibt es die Tabelle nicht mehr, verschwindet auch ihre Datei.
interface IDurableTableRepository {
    void flush(string name);
}

/// Ausgehender Port: dauerhaftes Anweisungsprotokoll (Write-Ahead-Log).
interface IStatementLog {
    void append(string statement);
    /// Mehrere Zeilen in einem Schreibvorgang (für Transaktionsgruppen).
    void appendAll(string[] statements);
    string[] readAll();
    /// Ersetzt das gesamte Protokoll atomar (Checkpoint).
    void replaceAll(string[] statements);
}
