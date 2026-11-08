module uim.hdb.application.usecases.secured_sql;

import uim.hdb;
import std.algorithm : filter;
import std.array : array;
import std.string : chomp, split, strip, toUpper;

/// Prüft jede Operation gegen die Rechte der anfragenden Identität. Alle eingehenden Adapter arbeiten nur hierüber.
/// Für Anweisungen prüft der Kern selbst an jeder Stelle, an der er eine Tabelle holt (siehe
/// SqlService.executeAuthorized): Tabellenrechte gelten so genau für die Tabellen, die eine Anweisung wirklich liest
/// oder ändert, auch bei Joins. Listen und Statistik zeigen nur Tabellen, auf denen die Identität ein Recht hat.
final class SecuredSqlUseCase : ISqlUseCase {
    private SqlService inner;
    private Principal delegate() current;
    private string openTransaction, transactionOwner; // der Kern erlaubt höchstens eine offene Transaktion

    this(SqlService inner, Principal delegate() current) {
        this.inner = inner;
        this.current = current;
    }

    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto principal = current();
        requireAuthenticated(principal);
        // Die Id steht in der "gesperrt"-Meldung und ist damit kein Geheimnis: die Bindung an den Besitzer zählt.
        if (txId.length && txId == openTransaction && transactionOwner != principal.name)
            throw new AccessDenied("Transaction belongs to another user");

        auto result = inner.executeAuthorized(txId, sql, (Permission p, string table) {
            // CREATE nennt die neue Tabelle, das Recht gilt aber nur für den ganzen Mandanten
            if (table.length && p != Permission.create)
                requirePermission(principal, p, table);
            else
                requirePermission(principal, p);
        });
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
        auto principal = current();
        requireAuthenticated(principal);
        return inner.listTables().filter!(t => principal.canSee(t)).array;
    }

    TableStats[] stats() {
        auto principal = current();
        requireAuthenticated(principal);
        return inner.stats().filter!(t => principal.canSee(t.table)).array;
    }

    MergeStatus mergeStatus() {
        requireAuthenticated(current());
        return inner.mergeStatus();
    }

    void checkpoint() {
        requirePermission(current(), Permission.maintain);
        inner.checkpoint();
    }

    void mergeDelta() {
        requirePermission(current(), Permission.maintain);
        inner.mergeDelta();
    }

    bool mergeDeltaAsync() {
        requirePermission(current(), Permission.maintain);
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

/// Tabellenrechte: geprüft wird für genau die Tabellen, die eine Anweisung liest oder ändert, auch bei Joins.
unittest {
    import std.algorithm : sort;
    import std.exception : assertThrown, collectException;

    auto core = new SqlService(new MemoryTableRepository);
    Principal who = Principal("a", HdbRole.admin, true);
    auto s = new SecuredSqlUseCase(core, () => who);
    s.execute("CREATE TABLE orders (id INTEGER, cid INTEGER, amt INTEGER)");
    s.execute("CREATE TABLE customers (id INTEGER, name VARCHAR)");
    s.execute("CREATE TABLE secret (id INTEGER, salary INTEGER)");
    s.execute("INSERT INTO orders VALUES (1, 1, 10)");
    s.execute("INSERT INTO customers VALUES (1, 'ACME')");
    s.execute("INSERT INTO secret VALUES (1, 99999)");

    // Ohne Rolle im Mandanten: select und insert auf orders, select auf customers
    Principal tina;
    tina.name = "tina";
    tina.authenticated = true;
    tina.tables["orders"] = PermissionSet.of(Permission.select, Permission.insert);
    tina.tables["customers"] = PermissionSet.of(Permission.select);
    who = tina;

    assert(s.listTables().sort.array == ["customers", "orders"]);
    assert(s.stats().length == 2);
    assert(s.execute("SELECT amt FROM orders").rows.length == 1);
    assert(s.execute("SELECT c.name, o.amt FROM orders o JOIN customers c ON o.cid = c.id").rows.length == 1);
    s.execute("INSERT INTO orders VALUES (2, 1, 5)");

    // Jede Tabelle eines Joins zählt, auch die rechte Seite eines LEFT JOIN
    assertThrown!AccessDenied(s.execute("SELECT o.amt FROM orders o JOIN secret x ON o.cid = x.id"));
    assertThrown!AccessDenied(s.execute("SELECT o.amt FROM orders o LEFT JOIN secret x ON o.cid = x.id"));
    assertThrown!AccessDenied(s.execute("SELECT * FROM secret"));
    // Ein String mit Tabellennamen ändert nichts: geprüft wird, was der Kern holt
    assert(s.execute("SELECT name FROM customers WHERE name = 'x FROM secret JOIN secret ON a = b'").rows.length == 0);

    // Ändern nur mit dem passenden Recht
    assertThrown!AccessDenied(s.execute("UPDATE orders SET amt = 0"));
    assertThrown!AccessDenied(s.execute("DELETE FROM orders"));
    assertThrown!AccessDenied(s.execute("INSERT INTO customers VALUES (2, 'x')"));
    assertThrown!AccessDenied(s.execute("DROP TABLE orders"));
    assertThrown!AccessDenied(s.execute("CREATE TABLE mine (a INTEGER)")); // create gilt nur im ganzen Mandanten
    assertThrown!AccessDenied(s.execute("BEGIN"));
    assertThrown!AccessDenied(s.checkpoint());

    // Ob eine fremde Tabelle existiert, verrät die Meldung nicht
    auto hidden = collectException!AccessDenied(s.execute("SELECT * FROM secret"));
    auto missing = collectException!AccessDenied(s.execute("SELECT * FROM nothere"));
    assert(hidden !is null && missing !is null);

    // Freigabe auf eine noch fehlende Tabelle gilt, sobald sie entsteht
    tina.tables["later"] = PermissionSet.of(Permission.select, Permission.drop);
    who = Principal("a", HdbRole.admin, true);
    s.execute("CREATE TABLE later (a INTEGER)");
    who = tina;
    assert(s.listTables().length == 3);
    s.execute("DROP TABLE later");

    // Rolle im Mandanten plus Freigabe: die Rechte addieren sich
    auto viewer = Principal("v", HdbRole.viewer, true);
    viewer.tables["orders"] = PermissionSet.of(Permission.delete_);
    who = viewer;
    assert(s.execute("SELECT * FROM secret").rows.length == 1);
    s.execute("DELETE FROM orders WHERE id = 2");
    assertThrown!AccessDenied(s.execute("DELETE FROM customers"));

    // Transaktionen brauchen transact; darin gelten die Tabellenrechte weiter
    auto editor = Principal("e", HdbRole.editor, true);
    who = editor;
    auto tx = s.execute("BEGIN").transaction;
    s.executeIn(tx, "UPDATE secret SET salary = 1");
    s.executeIn(tx, "ROLLBACK");
    assertThrown!AccessDenied(s.execute("DROP TABLE secret"));

    // Interne Wege (Protokoll, Replikation) prüfen nichts: execute direkt am Kern geht
    assert(core.execute("SELECT * FROM secret").rows.length == 1);
}
