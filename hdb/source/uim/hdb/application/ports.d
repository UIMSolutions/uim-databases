module uim.hdb.application.ports;

import uim.hdb.domain.table;
import uim.hdb.domain.value;

struct QueryResult
{
    string[] columns;
    Value[][] rows;
    long affected;
    string message;
    string transaction; // gesetzt von BEGIN
}

/// Zustand des Delta-Merges im Hintergrund.
struct MergeStatus
{
    bool running;
    size_t completed;
    string lastError;
}

/// Eingehender Port: was die Anwendung anbietet.
interface ISqlUseCase
{
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

/// Ausgehender Port: was die Anwendung von der Infrastruktur braucht.
interface ITableRepository
{
    bool exists(string name);
    ColumnTable get(string name);
    void save(ColumnTable table);
    void remove(string name);
    string[] list();
}

/// Ausgehender Port: dauerhaftes Anweisungsprotokoll (Write-Ahead-Log).
interface IStatementLog
{
    void append(string statement);
    /// Mehrere Zeilen in einem Schreibvorgang (für Transaktionsgruppen).
    void appendAll(string[] statements);
    string[] readAll();
    /// Ersetzt das gesamte Protokoll atomar (Checkpoint).
    void replaceAll(string[] statements);
}
