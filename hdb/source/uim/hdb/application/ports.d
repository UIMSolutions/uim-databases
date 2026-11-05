module uim.hdb.application.ports;

import uim.hdb;
import uim.hdb.domain.entities.user;
import uim.hdb.domain.value;

struct QueryResult {
    string[] columns;
    Value[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}

/// Zustand des Delta-Merges im Hintergrund.
struct MergeStatus {
    bool running;
    size_t completed;
    string lastError;
}

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

/// Benutzer ohne Passwort-Hash: das, was Adapter sehen dürfen.
struct UserInfo {
    string name;
    Role role;
    bool active;
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
    UserInfo createUser(Principal actor, string name, string password, Role role);
    UserInfo updateUser(Principal actor, string name, Role role, bool active);
    void resetPassword(Principal actor, string name, string replacement);
    void deleteUser(Principal actor, string name);
}

/// Ausgehender Port: dauerhafte Ablage der Benutzer.
interface IUserStore {
    User[] load();
    void save(User[] users);
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
