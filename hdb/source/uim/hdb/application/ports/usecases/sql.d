module uim.hdb.application.ports.usecases.sql;

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