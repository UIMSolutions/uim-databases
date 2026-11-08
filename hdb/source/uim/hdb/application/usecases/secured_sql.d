module uim.hdb.application.usecases.secured_sql;

import uim.hdb;
import std.string : chomp, split, strip, toUpper;

/// Checks each operation against the role of the requesting identity. All incoming adapters operate
/// solely on this basis, so there is no way to bypass the authorization system. Without an identity, the request is rejected.

final class SecuredSqlUseCase : ISqlUseCase {
    private ISqlUseCase inner;
    private Principal delegate() current;
    private string openTransaction, transactionOwner; // der Kern erlaubt höchstens eine offene Transaktion

    this(ISqlUseCase inner, Principal delegate() current) {
        this.inner = inner;
        this.current = current;
    }

    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto principal = current();
        requireRole(principal, requiredRole(sql));
        // Die Id steht in der "gesperrt"-Meldung und ist damit kein Geheimnis: die Bindung an den Besitzer zählt.
        if (txId.length && txId == openTransaction && transactionOwner != principal.name)
            throw new AccessDenied("Transaction belongs to another user");

        auto result = inner.executeIn(txId, sql);
        if (result.transaction.length) {
            openTransaction = result.transaction;
            transactionOwner = principal.name;
        } else {
            auto words = sql.strip.chomp(";").strip.split();
            if (words.length && (words[0].toUpper == "COMMIT" || words[0].toUpper == "ROLLBACK"))
                openTransaction = transactionOwner = "";
        }
        return result;
    }

    string[] listTables() {
        requireRole(current(), HdbRole.viewer);
        return inner.listTables();
    }

    TableStats[] stats() {
        requireRole(current(), HdbRole.viewer);
        return inner.stats();
    }

    MergeStatus mergeStatus() {
        requireRole(current(), HdbRole.viewer);
        return inner.mergeStatus();
    }

    void checkpoint() {
        requireRole(current(), HdbRole.admin);
        inner.checkpoint();
    }

    void mergeDelta() {
        requireRole(current(), HdbRole.admin);
        inner.mergeDelta();
    }

    bool mergeDeltaAsync() {
        requireRole(current(), HdbRole.admin);
        return inner.mergeDeltaAsync();
    }
}
///
unittest {
    import uim.hdb;
    import std.exception : assertThrown;

    static class Repo : ITableRepository {
        ColumnTable[string] m;
        bool exists(string n) {
            return (n in m) !is null;
        }

        ColumnTable get(string n) {
            return m[n];
        }

        void save(ColumnTable t) {
            m[t.name] = t;
        }

        void remove(string n) {
            m.remove(n);
        }

        string[] list() {
            return m.keys;
        }
    }

    Principal who;
    auto s = new SecuredSqlUseCase(new SqlService(new Repo), () => who);
    auto admin = Principal("a", HdbRole.admin, true);
    auto editor = Principal("e", HdbRole.editor, true);
    auto editor2 = Principal("e2", HdbRole.editor, true);
    auto viewer = Principal("v", HdbRole.viewer, true);

    // anonym: alles abgelehnt, auch Lesen
    assertThrown!AuthenticationRequired(s.listTables());
    assertThrown!AuthenticationRequired(s.execute("SELECT 1"));

    who = admin;
    s.execute("CREATE TABLE t (k INTEGER)");

    who = editor;
    s.execute("INSERT INTO t VALUES (1)");
    assertThrown!AccessDenied(s.execute("DROP TABLE t"));
    assertThrown!AccessDenied(s.execute("CREATE TABLE u (k INTEGER)"));
    assertThrown!AccessDenied(s.checkpoint());
    assertThrown!AccessDenied(s.mergeDeltaAsync());

    who = viewer;
    assert(s.execute("select k from t;").rows.length == 1);
    assert(s.stats().length == 1);
    assertThrown!AccessDenied(s.execute("DELETE FROM t"));
    assertThrown!AccessDenied(s.execute("BEGIN")); // BEGIN sperrt die Datenbank für alle

    // Eine fremde Transaktion lässt sich nicht übernehmen, auch nicht mit bekannter Id
    who = editor;
    auto tx = s.execute("BEGIN").transaction;
    who = editor2;
    assertThrown!AccessDenied(s.executeIn(tx, "DELETE FROM t"));
    assertThrown!AccessDenied(s.executeIn(tx, "COMMIT"));
    who = viewer;
    assertThrown!AccessDenied(s.executeIn(tx, "SELECT k FROM t"));
    who = editor;
    s.executeIn(tx, "ROLLBACK;");
    who = editor2;
    auto tx2 = s.execute("BEGIN").transaction;
    s.executeIn(tx2, "COMMIT");
}
