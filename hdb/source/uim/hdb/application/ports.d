module uim.hdb.application.ports;

import uim.hdb;

@safe:


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
/// Die Benutzerverwaltung wirkt immer nur im Mandanten des actors.
interface IAccessUseCase {
    /// `tenant` leer bedeutet default.
    /// `address` ist die IP-Adresse des Clients; schränkt der Mandant die Netze ein, muss sie darin liegen.
    LoginResult login(string tenant, string name, string password, string address);
    void logout(string token);
    /// Identität zu einem Token; anonym, wenn es ungültig, abgelaufen oder die Adresse nicht erlaubt ist.
    /// Rechte werden dabei neu aufgelöst, befristete Freigaben gelten also genau in ihrem Zeitraum.
    Principal authenticate(string token, string address);
    void changeOwnPassword(Principal actor, string current, string replacement);

    // Benutzer, Rollen und Tabellenfreigaben, alles mit dem Recht manageAccess und nur im Bereich des actors.
    // `role` ist ein Rollenname des Bereichs, leer bedeutet keine Rolle (dann gelten nur Tabellenfreigaben).
    UserInfo[] listUsers(Principal actor);
    UserInfo createUser(Principal actor, string name, string password, string role);
    UserInfo updateUser(Principal actor, string name, string role, bool active);
    /// Ersetzt alle Tabellenfreigaben des Benutzers.
    UserInfo setGrants(Principal actor, string name, TableGrant[] grants);
    void resetPassword(Principal actor, string name, string replacement);
    void deleteUser(Principal actor, string name);

    RoleInfo[] listRoles(Principal actor);
    /// Legt eine eigene Rolle an oder ändert sie; vordefinierte Rollen sind unveränderlich.
    RoleInfo saveRole(Principal actor, string name, string description, string[] permissions);
    /// Nur Rollen, die niemand mehr verwendet.
    void deleteRole(Principal actor, string name);
}

struct RoleInfo {
    string name, description;
    string[] permissions;
    bool builtin;
    size_t users; // Benutzer mit dieser Rolle im Bereich oder in einer Tabellenfreigabe
}

/// Ausgehender Port: eigene Rollen aller Bereiche. Vordefinierte Rollen werden nicht gespeichert.
interface IRoleStore {
    RoleDef[] load();
    void save(RoleDef[] roles);
}

/// Was die Mandantenverwaltung von der Benutzerverwaltung braucht. Ohne Rollenprüfung: nur TenantService sieht das,
/// und der prüft selbst auf Systemadministratoren.
interface ITenantAccounts {
    /// Legt den ersten Administrator eines Mandanten an. Prüft Name und Passwort, bevor etwas gespeichert wird.
    void provisionAdmin(string tenant, string name, string password);
    /// Beendet alle Sitzungen des Mandanten.
    void revokeTenant(string tenant);
    /// Löscht alle Benutzer des Mandanten und beendet ihre Sitzungen.
    void removeTenant(string tenant);
    size_t userCount(string tenant);
}

struct TenantInfo {
    string name, label;
    bool active;
    size_t users;
    string[] networks; // erlaubte Netze; leer: alle
}

/// Eingehender Port: Mandanten anlegen, ändern und löschen, nur für Systemadministratoren.
interface ITenantUseCase {
    TenantInfo[] listTenants(Principal actor);
    /// Legt den Mandanten mit leerer Datenbank und seinem ersten Administrator an.
    TenantInfo createTenant(Principal actor, string name, string label, string adminName, string adminPassword);
    /// Deaktivieren beendet alle Sitzungen des Mandanten; Daten und Benutzer bleiben erhalten.
    TenantInfo updateTenant(Principal actor, string name, string label, bool active);
    /// Löscht Benutzer, Daten und Sicherungen endgültig. Nur für deaktivierte Mandanten.
    void deleteTenant(Principal actor, string name);
    /// Setzt die erlaubten Netze eines Mandanten, etwa wenn sich dessen Administratoren ausgesperrt haben
    /// (Recht manageTenants).
    TenantInfo setTenantNetworks(Principal actor, string name, string[] networks);

    /// Erlaubte Netze des eigenen Mandanten (Recht manageAccess im Mandanten).
    string[] ownNetworks(Principal actor);
    /// Setzt die erlaubten Netze des eigenen Mandanten. `clientAddress` ist die Adresse der Anfrage: eine Liste,
    /// die sie ausschließt, wird abgelehnt, damit sich niemand selbst aussperrt.
    string[] setOwnNetworks(Principal actor, string[] networks, string clientAddress);
}

/// Ausgehender Port: Liste der Mandanten.
interface ITenantStore {
    Tenant[] load();
    void save(Tenant[] tenants);
}

/// Die Ablagen einer Mandanten-Datenbank.
struct TenantStorage {
    ITableRepository tables;
    IStatementLog log;
    IBackupStore backups;
    IReplicationConfigStore replication;
}

/// Ausgehender Port: getrennte Ablage je Mandant (Tabellen, Protokoll, Sicherungen).
interface ITenantStorage {
    TenantStorage open(string tenant);
    bool exists(string tenant);
    /// Löscht alle Daten und Sicherungen des Mandanten endgültig.
    void purge(string tenant);
}

/// Ausgehender Port des Kerns: erfährt jede bestätigte Änderung, in der Reihenfolge der Commits.
/// Wird unter der Sperre des Kerns aufgerufen und darf deshalb nicht blockieren.
interface IChangeSink {
    /// Schreibende Anweisungen einer Änderung: eine einzelne Anweisung oder alle einer Transaktion.
    void committed(string[] statements);
    /// Der ganze Stand wurde ersetzt (Wiederherstellung): einzelne Änderungen reichen nicht mehr.
    void replaced();
}

/// Eine bestätigte Änderung im Änderungsstrom einer Quelle.
struct Change {
    ulong sequence;
    string[] statements;
}

/// Antwort auf eine Abfrage des Änderungsstroms. `resync`: die Position ist nicht mehr lieferbar
/// (andere Epoche oder zu alt), das Ziel braucht einen vollständigen Stand.
struct ChangeBatch {
    string epoch;
    ulong sequence; // letzte vergebene Nummer der Quelle
    bool resync;
    Change[] changes;
}

/// Vollständiger Stand einer Quelle samt Position im Änderungsstrom.
struct ReplicationSnapshot {
    string epoch;
    ulong sequence;
    TableSnapshot[] tables; // über HTTP im Sicherungsformat, siehe encodeSnapshot
}

/// Woher ein Ziel seine Daten bezieht. `password` verlässt den Server nie über eine API.
struct ReplicationConfig {
    bool enabled;
    string url; // Basis-URL der Quelle, etwa https://primary:8080
    string tenant; // Mandant auf der Quelle
    string user;
    string password;
    int intervalSeconds = 2;
}

/// Zustand der Replikation eines Mandanten, für die Oberflächen.
struct ReplicationStatus {
    // als Quelle
    string epoch;
    ulong sequence;
    ulong retainedFrom; // älteste noch lieferbare Nummer
    // als Ziel
    bool replica;
    string url, sourceTenant, user;
    int intervalSeconds;
    string state; // off, connecting, syncing, streaming oder error
    string sourceEpoch;
    ulong appliedSequence;
    string lastSync, lastError; // ISO-Zeit in UTC
}

/// Eingehender Port: Replikation eines Mandanten. Lesen des Stroms braucht die Rolle viewer, alles andere admin.
interface IReplicationUseCase {
    ReplicationSnapshot replicationSnapshot();
    ChangeBatch replicationChanges(string epoch, ulong since, size_t max);
    ReplicationStatus replicationStatus();
    /// Macht den Mandanten zum Ziel der Quelle; er ist danach für Schreibzugriffe gesperrt.
    /// Ein leeres Passwort behält das bisherige.
    ReplicationStatus configureReplica(ReplicationConfig config);
    /// Löst die Verbindung: der Mandant behält seinen Stand und ist wieder beschreibbar.
    ReplicationStatus stopReplica();
    /// Holt beim nächsten Lauf einen vollständigen Stand.
    ReplicationStatus resyncReplica();
}

/// Ausgehender Port: Zugriff eines Ziels auf seine Quelle.
interface IReplicationClient {
    /// Wirft, wenn die URL nicht verwendet werden darf (Schema, erlaubte Hosts).
    void validate(string url);
    /// Gibt ein Token zurück; wirft AuthenticationRequired bei falschen Zugangsdaten.
    string login(string url, string tenant, string user, string password);
    ReplicationSnapshot snapshot(string url, string token);
    ChangeBatch changes(string url, string token, string epoch, ulong since, size_t max);
}

/// Ausgehender Port: Einstellungen der Replikation eines Mandanten.
interface IReplicationConfigStore {
    ReplicationConfig load();
    void save(ReplicationConfig config);
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

// --- Protokolle: Audit, Anwendung, Ereignisse ---

/// Was eine Aktion für das Audit-Protokoll hinterlässt. Passwörter und Werte aus Zeilen gehören nie hinein.
struct AuditRecord {
    string scope_; // Mandant des Handelnden; bei einer fehlgeschlagenen Anmeldung der angegebene Mandant
    string actor;
    string address;
    string category; // siehe auditCategories
    string action; // etwa login, createUser, restoreBackup
    string target; // betroffenes Objekt: Benutzer, Tabelle, Sicherung, Mandant
    bool success = true;
    string message; // bei Misserfolg der Grund
}

/// Ausgehender Port der Anwendungsdienste: nimmt Audit-Einträge an. Darf nie werfen: ein volles Protokoll soll
/// keine Anmeldung und keine Änderung verhindern.
interface IAuditTrail {
    void audit(AuditRecord record) nothrow;
}

/// Ausgehender Port: nimmt Betriebsereignisse an. Darf nie werfen.
interface IEventLog {
    void event(string scope_, string category, LogSeverity severity, string message) nothrow;
}

/// Suche in einem Protokoll. Leere Felder filtern nicht.
struct LogQuery {
    LogKind kind;
    string scope_; // nur im Bereich des Servers wählbar; sonst immer der eigene Bereich
    LogSeverity minSeverity = LogSeverity.debug_;
    string category;
    string actor;
    string text; // Teilstring in Aktion, Ziel oder Meldung, ohne Groß- und Kleinschreibung
    string from, until; // ISO 8601; from einschließlich, until ausschließlich
    size_t limit = 200;
    ulong before; // nur Einträge mit kleinerer Id (Blättern); 0: ab dem neuesten
}

/// Treffer, neueste zuerst. `total`: alle Treffer ohne limit und before.
struct LogPage {
    LogEntry[] entries;
    size_t total;
}

/// Ein Protokoll, wie es eine Anmeldung sieht.
struct LogInfo {
    LogKind kind;
    LogSettings settings;
    bool editable; // Recht manageLogs
}

/// Eingehender Port: Protokolle lesen und einstellen. Lesen braucht viewLogs, Einstellen manageLogs. Jeder
/// Bereich hat eigene Einstellungen; das Anwendungsprotokoll gehört dem Bereich des Servers.
interface ILogUseCase {
    /// Die Protokolle, die `actor` lesen darf.
    LogInfo[] logs(Principal actor);
    LogPage read(Principal actor, LogQuery query);
    LogSettings settings(Principal actor, LogKind kind);
    /// Ändert die Einstellungen des eigenen Bereichs. Wird immer im Audit-Protokoll vermerkt.
    LogSettings configure(Principal actor, LogKind kind, LogSettings next, string address);
}

/// Ausgehender Port: Ablage der Einträge.
interface ILogStore {
    /// Vergibt die Id und gibt den gespeicherten Eintrag zurück.
    LogEntry append(LogEntry entry);
    /// Durchsucht eine Art vom neuesten zum ältesten Eintrag.
    LogPage find(LogKind kind, scope bool delegate(ref const LogEntry) @safe match, ulong before, size_t limit);
    /// Löscht je Bereich Einträge einer Art, die vor `cutoff` liegen oder über die neuesten `maxEntries`
    /// hinausgehen. Gibt die Anzahl gelöschter Einträge zurück.
    size_t prune(LogKind kind, scope LogRetention delegate(string scope_) @safe retentionOf);
}

/// Aufbewahrung eines Protokolls in einem Bereich. `cutoff` im Format von logTime.
struct LogRetention {
    string cutoff;
    size_t maxEntries;
}

/// Ausgehender Port: Einstellungen der Protokolle je Bereich.
interface ILogSettingsStore {
    LogPolicy[string] load();
    void save(LogPolicy[string] policies);
}
