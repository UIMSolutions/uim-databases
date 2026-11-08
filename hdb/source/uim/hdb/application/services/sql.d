module uim.hdb.application.services.sql;

import uim.hdb;
import std.algorithm : all, canFind, map, sort, startsWith, endsWith, SwapStrategy;
import std.ascii : isDigit;
import std.array : array, join, split;
import std.conv : to;
import std.exception : enforce;
import std.range : iota;
import std.regex : ctRegex, matchFirst, splitter;
import std.string : chomp, icmp, indexOf, replace, strip, toLower, toUpper;
import std.uuid : randomUUID;
import core.thread : Thread;
import core.time : MonoTime, msecs, seconds;

/// Mini-SQL: CREATE TABLE, INSERT, SELECT (Spalten, *, COUNT(*), SUM(x)) mit einfachem WHERE.
final class SqlService : ISqlUseCase, IDatabaseSnapshots {
    private ITableRepository repo;
    private IDurableTableRepository durable; // null, wenn das Repository nur im Speicher arbeitet
    private IStatementLog log;
    private size_t pending;
    private enum checkpointEvery = 1000;
    private enum idleTimeout = 30.seconds; // offene Transaktionen ohne Aktivität werden zurückgerollt
    size_t pushedDownFilters; // Anzahl vorgezogener WHERE-Bedingungen (Diagnose)
    private Transaction tx; // höchstens eine offene Transaktion (globale Sperre)
    private bool mergeRunning; // ein Merge-Thread läuft (nur unter der Sperre lesen/schreiben)
    private size_t mergesCompleted;
    private string lastMergeError;
    private bool recovering; // beim Einspielen des Logs keine Hintergrund-Merges starten
    private IChangeSink sink; // erfährt bestätigte Änderungen (Replikation); null: niemand

    /// Empfänger aller bestätigten Änderungen, für alle Speicherarten. Das Einspielen des Logs beim Start meldet nichts.
    void changeSink(IChangeSink sink) {
        synchronized (this)
            this.sink = sink;
    }

    this(ITableRepository repo, IStatementLog log = null) {
        this.repo = repo;
        this.durable = cast(IDurableTableRepository) repo;
        this.log = log;
    }

    /// Spielt das Protokoll beim Start ein. Nur vollständige BEGIN..COMMIT-Gruppen werden übernommen;
    /// ein unvollständiger Rest (Absturz beim Commit) wird verworfen und das Log neu geschrieben.
    void recover() {
        if (log is null)
            return;
        synchronized (this) {
            recovering = true;
            scope (exit)
                recovering = false;
            // Tabellen aus eigenen Dateien sind schon geladen. Ihr Name kann im Log noch aus der Zeit
            // stehen, in der eine gleichnamige Speicher-Tabelle existierte: diese Zeilen gelten nicht mehr.
            bool[string] loaded;
            foreach (name; repo.list())
                if (repo.get(name).storage != TableStorage.memory)
                    loaded[name.toLower] = true;
            void replay(string stmt) {
                if ((targetTable(stmt).toLower in loaded) is null)
                    run(stmt);
            }

            bool inTx, dirty;
            string[] buf;
            foreach (stmt; log.readAll()) {
                auto u = stmt.strip.toUpper;
                if (u == "BEGIN") {
                    dirty = dirty || inTx;
                    inTx = true;
                    buf = null;
                } else if (u == "COMMIT") {
                    foreach (b; buf)
                        replay(b);
                    inTx = false;
                    buf = null;
                } else if (inTx)
                    buf ~= stmt;
                else
                    replay(stmt);
            }
            if (inTx || dirty)
                checkpoint();
        }
    }

    /// Delta-Merge und Kompaktierung für alle Tabellen, synchron (Start, Tests): entfernt gelöschte Zeilen und baut
    /// das Main neu auf. Die Sperre wird nur zum Einfrieren und zum Umschalten gehalten, nicht für den Aufbau.
    void mergeDelta() {
        waitForMerge();
        synchronized (this)
            requireIdle();
        mergeCycle(true);
    }

    /// Startet den Delta-Merge im Hintergrund und kehrt sofort zurück (false: es läuft schon einer).
    bool mergeDeltaAsync() {
        synchronized (this)
            requireIdle();
        return startMerge(true); // ausdrücklich angefordert: auch kleine Mengen gelöschter Zeilen entfernen
    }

    MergeStatus mergeStatus() {
        synchronized (this)
            return MergeStatus(mergeRunning, mergesCompleted, lastMergeError);
    }

    /// Hintergrund-Thread für einen Merge-Zyklus. Er nimmt die Sperre nur kurz in Phase 1 und 3.
    private bool startMerge(bool force = false) {
        synchronized (this) {
            if (mergeRunning)
                return false;
            mergeRunning = true;
        }
        auto worker = new Thread({
            bool ok = true;
            try
                mergeCycle(force);
            catch (Throwable e) {
                ok = false;
                synchronized (this)
                    lastMergeError = e.msg;
            }
            synchronized (this) {
                mergeRunning = false;
                if (ok)
                    ++mergesCompleted;
            }
        });
        worker.isDaemon = true; // hält den Prozess beim Beenden nicht auf
        try
            worker.start();
        catch (Throwable e) {
            synchronized (this)
                mergeRunning = false;
            throw e;
        }
        return true;
    }

    private void waitForMerge() {
        while (true) {
            synchronized (this)
                if (!mergeRunning)
                    return;
            Thread.sleep(5.msecs);
        }
    }

    /// Nach Änderungen: lohnt sich ein Merge, läuft er im Hintergrund an (nicht während des Einspielens des Logs).
    private void scheduleMergeIfNeeded(ColumnTable t) {
        if (!recovering && (t.needsMerge() || t.needsCompaction()))
            startMerge();
    }

    /// Ein Wartungszyklus über alle Tabellen in drei Phasen (siehe domain/column.d und domain/table.d):
    /// Einfrieren und Umschalten unter der Sperre, der teure Aufbau dazwischen ohne.
    /// Eine Tabelle wird entweder kompaktiert (gelöschte Zeilen entfernen, sonst nur bei `force` oder ab der
    /// Schwelle) oder spaltenweise gemergt; läuft dort schon etwas, wird sie übersprungen.
    private void mergeCycle(bool force = false) {
        MergeTask[] merges;
        CompactionTask[] compactions;
        synchronized (this) {
            foreach (name; repo.list()) {
                auto t = repo.get(name);
                if (t.isCompacting)
                    continue;
                if (force || t.needsCompaction())
                    if (auto cj = t.beginCompaction()) {
                        compactions ~= CompactionTask(t, cj);
                        continue; // die Kompaktierung mergt auch das Delta
                    }
                foreach (c; t.columns)
                    if (auto job = c.beginMerge())
                        merges ~= MergeTask(c, job);
            }
        }
        if (merges.length == 0 && compactions.length == 0)
            return;
        scope (failure) {
            synchronized (this) {
                foreach (task; merges)
                    task.column.abortMerge(task.job);
                foreach (task; compactions)
                    task.table.abortCompaction(task.job);
            }
        }
        foreach (task; merges)
            task.job.run();
        foreach (task; compactions)
            task.job.run();
        synchronized (this) {
            foreach (task; merges)
                task.column.finishMerge(task.job);
            foreach (task; compactions)
                task.table.finishCompaction(task.job);
        }
    }

    TableStats[] stats() {
        synchronized (this) {
            requireIdle();
            TableStats[] result;
            foreach (name; repo.list())
                result ~= repo.get(name).stats();
            return result;
        }
    }

    /// Schreibt den aktuellen Stand als kompaktes Protokoll neu.
    void checkpoint() {
        if (log is null)
            return;
        synchronized (this) {
            requireIdle();
            string[] stmts;
            foreach (name; repo.list()) {
                auto t = repo.get(name);
                if (t.storage != TableStorage.memory)
                    continue; // liegt in einer eigenen Datei
                stmts ~= dumpCreate(t);
                foreach (r; t.liveRows())
                    stmts ~= dumpRow(t, r);
            }
            log.replaceAll(stmts);
            pending = 0;
        }
    }

    /// Konsistenter Stand aller Tabellen: unter der Sperre und ohne offene Transaktion.
    TableSnapshot[] snapshot() {
        synchronized (this) {
            requireIdle();
            TableSnapshot[] result;
            foreach (name; repo.list()) {
                auto t = repo.get(name);
                TableSnapshot s = TableSnapshot(t.name, t.storage, t.defs.dup);
                foreach (r; t.liveRows()) {
                    auto row = new Value[t.defs.length];
                    foreach (c; 0 .. t.defs.length)
                        row[c] = t.value(c, r);
                    s.rows ~= row;
                }
                result ~= s;
            }
            return result;
        }
    }

    void restore(TableSnapshot[] tables) {
        // Erst alles aufbauen und prüfen: ein Fehler hier lässt die Datenbank unberührt.
        // Der Name wird in File- und Json-Tabellen zum Dateinamen und kann aus einer hochgeladenen Datei stammen.
        ColumnTable[] fresh;
        bool[string] seen;
        foreach (s; tables) {
            enforce(!matchFirst(s.name, ctRegex!(`^\w+$`)).empty, "Ungültiger Tabellenname: " ~ s.name);
            enforce((s.name.toLower in seen) is null, "Tabelle ist doppelt: " ~ s.name);
            enforce(s.storage == TableStorage.memory || durable !is null, "Dieses Repository unterstützt nur MEMORY");
            enforce(s.columns.length > 0, "Tabelle ohne Spalten: " ~ s.name);
            seen[s.name.toLower] = true;
            foreach (c; s.columns)
                enforce(!matchFirst(c.name, ctRegex!(`^\w+$`)).empty, "Ungültiger Spaltenname: " ~ c.name);
            auto t = new ColumnTable(s.name, s.columns.dup, s.storage);
            foreach (row; s.rows)
                t.insert(row);
            fresh ~= t;
        }

        synchronized (this) {
            requireIdle();
            foreach (name; repo.list()) {
                repo.remove(name);
                if (durable !is null)
                    durable.flush(name);
            }
            foreach (t; fresh) {
                repo.save(t);
                if (t.storage != TableStorage.memory)
                    durable.flush(t.name);
            }
            checkpoint(); // das Log enthält danach genau die wiederhergestellten Speicher-Tabellen
            if (sink !is null)
                sink.replaced();
        }
        mergeDeltaAsync();
    }

    string[] listTables() {
        synchronized (this) {
            requireIdle();
            return repo.list();
        }
    }

    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto s = sql.strip.chomp(";").strip;
        enforce(s.length, "Leeres Statement");
        synchronized (this) {
            expireIfIdle();
            auto verb = s.split()[0].toUpper;
            if (verb == "BEGIN")
                return beginTx();
            if (verb == "COMMIT" || verb == "ROLLBACK") {
                enforce(tx !is null && tx.id == txId,
                    "Keine passende offene Transaktion (abgelaufen oder beendet?): " ~ txId);
                return verb == "COMMIT" ? commitTx() : rollbackTx();
            }

            // Eine offene Transaktion sperrt die Datenbank für alle anderen (serialisierbar, kein Warten).
            if (tx !is null)
                enforce(txId == tx.id, "Datenbank durch Transaktion " ~ tx.id ~ " gesperrt");
            else
                enforce(txId.length == 0, "Unbekannte oder beendete Transaktion: " ~ txId);

            immutable writes = verb == "CREATE" || verb == "DROP" || verb == "INSERT" || verb == "UPDATE" || verb == "DELETE";
            auto target = writes ? targetTable(s) : "";
            immutable storageBefore = storageOf(target); // nach DROP ist die Tabelle weg
            auto res = run(s);
            if (writes) {
                immutable storage = verb == "CREATE" ? storageOf(target) : storageBefore;
                if (storage != TableStorage.memory) {
                    // eigene Datei, kein Log: jede Tabelle hat genau eine dauerhafte Quelle
                    if (tx !is null) {
                        tx.flushes[target.toLower] = target;
                        ++tx.fileWrites;
                    } else
                        durable.flush(target);
                } else if (tx !is null)
                    tx.stmts ~= s;
                else if (log !is null) {
                    log.append(s);
                    if (++pending >= checkpointEvery)
                        checkpoint();
                }
                // Erst nach dem dauerhaften Schreiben: gemeldet wird nur, was einen Neustart übersteht
                if (tx !is null)
                    tx.changes ~= s;
                else if (sink !is null)
                    sink.committed([s]);
            }
            if (tx !is null)
                tx.lastActive = MonoTime.currTime;
            return res;
        }
    }

    private QueryResult beginTx() {
        enforce(tx is null, "Es läuft bereits eine Transaktion: " ~ tx.id);
        tx = new Transaction;
        tx.id = randomUUID().toString();
        tx.lastActive = MonoTime.currTime;
        return QueryResult(null, null, 0, "Transaktion gestartet", tx.id);
    }

    /// Schreibt alle Anweisungen als eine BEGIN..COMMIT-Gruppe ins Log; schlägt das fehl, wird zurückgerollt.
    private QueryResult commitTx() {
        auto logged = tx.stmts.length;
        auto n = logged + tx.fileWrites;
        try {
            foreach (name; tx.flushes)
                durable.flush(name);
            if (log !is null && logged > 0)
                log.appendAll(["BEGIN"] ~ tx.stmts ~ ["COMMIT"]);
        } catch (Exception e) {
            auto names = tx.flushes.values;
            undo();
            foreach (name; names) // schon geschriebene Dateien auf den alten Stand zurückbringen
                try
                    durable.flush(name);
                catch (Exception) {
                }
            throw e;
        }
        pending += logged;
        if (sink !is null && tx.changes.length)
            sink.committed(tx.changes);
        tx = null;
        if (log !is null && pending >= checkpointEvery)
            checkpoint();
        return QueryResult(null, null, 0, "Transaktion abgeschlossen (" ~ n.to!string ~ " Anweisung(en))");
    }

    private QueryResult rollbackTx() {
        undo();
        return QueryResult(null, null, 0, "Transaktion zurückgerollt");
    }

    /// Stellt die vor der ersten Änderung angelegten Tabellen-Snapshots wieder her und entfernt neue Tabellen.
    private void undo() {
        foreach (key, name; tx.created)
            repo.remove(name);
        foreach (key, snap; tx.before)
            repo.save(snap);
        tx = null;
    }

    private void expireIfIdle() {
        if (tx !is null && MonoTime.currTime - tx.lastActive > idleTimeout)
            undo();
    }

    private void requireIdle() {
        expireIfIdle();
        enforce(tx is null, "Datenbank durch Transaktion " ~ tx.id ~ " gesperrt");
    }

    /// Vor der ersten Änderung einer Tabelle in einer Transaktion einen Snapshot anlegen.
    private void touch(ColumnTable t) {
        if (tx is null)
            return;
        auto key = t.name.toLower;
        if (key in tx.created || key in tx.before)
            return;
        tx.before[key] = t.clone();
    }

    private TableStorage storageOf(string name) {
        return name.length && repo.exists(name) ? repo.get(name).storage : TableStorage.memory;
    }

    private QueryResult run(string s) {
        switch (s.split()[0].toUpper) {
        case "CREATE":
            return createTable(s);
        case "DROP":
            return dropTable(s);
        case "INSERT":
            return insertInto(s);
        case "UPDATE":
            return updateRows(s);
        case "DELETE":
            return deleteRows(s);
        case "SELECT":
            return select(s);
        default:
            throw new Exception("Nicht unterstütztes Statement");
        }
    }

    private QueryResult createTable(string s) {
        auto m = matchFirst(s, ctRegex!(`^CREATE\s+TABLE\s+(\w+)\s*\((.*)\)(?:\s+USING\s+(\w+))?$`, "is"));
        enforce(!m.empty, "Syntax: CREATE TABLE name (spalte TYP, ...) [USING MEMORY|FILE|JSON]");
        immutable storage = m[3].length ? parseStorage(m[3]) : TableStorage.memory;
        enforce(storage == TableStorage.memory || durable !is null, "Dieses Repository unterstützt nur MEMORY");
        enforce(!repo.exists(m[1]), "Tabelle existiert bereits");
        ColumnDef[] defs;
        foreach (part; splitList(m[2])) {
            auto p = part.strip.split();
            enforce(p.length == 2, "Ungültige Spaltendefinition: " ~ part);
            defs ~= ColumnDef(p[0], columnTypeOf(p[1]));
        }
        repo.save(new ColumnTable(m[1], defs, storage));
        if (tx !is null)
            tx.created[m[1].toLower] = m[1];
        return QueryResult(null, null, 0, "Tabelle " ~ m[1] ~ " angelegt");
    }

    /// Entfernt die Tabelle; in einer Transaktion stellt der Snapshot sie beim Rollback wieder her.
    private QueryResult dropTable(string s) {
        auto m = matchFirst(s, ctRegex!(`^DROP\s+TABLE\s+(\w+)$`, "i"));
        enforce(!m.empty, "Syntax: DROP TABLE name");
        enforce(repo.exists(m[1]), "Tabelle nicht gefunden: " ~ m[1]);
        touch(repo.get(m[1]));
        repo.remove(m[1]);
        return QueryResult(null, null, 0, "Tabelle " ~ m[1] ~ " gelöscht");
    }

    private QueryResult insertInto(string s) {
        auto m = matchFirst(s, ctRegex!(`^INSERT\s+INTO\s+(\w+)\s+VALUES\s*\((.*)\)$`, "is"));
        enforce(!m.empty, "Syntax: INSERT INTO name VALUES (...)");
        auto t = repo.get(m[1]);
        touch(t);
        auto lits = splitList(m[2]);
        enforce(lits.length == t.defs.length, "Spaltenanzahl passt nicht");
        Value[] row;
        foreach (i, l; lits)
            row ~= parseLiteral(t.defs[i].type, l);
        t.insert(row);
        scheduleMergeIfNeeded(t);
        return QueryResult(null, null, 1, "1 Zeile eingefügt");
    }

    /// UPDATE = alte Version löschen + neue Version ans Ende (Delta) einfügen (insert-only wie in HANA).
    private QueryResult updateRows(string s) {
        auto masked = maskLiterals(s);
        auto m = originalCaptures(matchFirst(masked, ctRegex!(
                `^UPDATE\s+(\w+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$`, "is")), masked, s);
        enforce(m.length, "Syntax: UPDATE name SET spalte = wert [, ...] [WHERE bedingung (AND/OR, Klammern)]");
        auto t = repo.get(m[1]);
        touch(t);

        auto newVals = new Value[t.defs.length];
        auto isSet = new bool[t.defs.length];
        foreach (part; splitList(m[2])) {
            auto eq = part.indexOf('=');
            enforce(eq > 0, "Zuweisung erwartet: spalte = wert");
            auto ci = t.indexOf(part[0 .. eq].strip);
            newVals[ci] = parseLiteral(t.defs[ci].type, part[eq + 1 .. $]);
            isSet[ci] = true;
        }

        auto hits = rowsFor(t, whereCond(m[3]));
        Value[][] fresh;
        foreach (r; hits) {
            Value[] row;
            foreach (ci; 0 .. t.defs.length)
                row ~= isSet[ci] ? newVals[ci] : t.value(ci, r);
            fresh ~= row;
        }
        foreach (r; hits)
            t.markDeleted(r);
        foreach (row; fresh)
            t.insert(row);
        scheduleMergeIfNeeded(t);
        return QueryResult(null, null, cast(long)hits.length, hits.length.to!string ~ " Zeile(n) geändert");
    }

    private QueryResult deleteRows(string s) {
        auto m = matchFirst(s, ctRegex!(
                `^DELETE\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+))?$`, "is"));
        enforce(!m.empty, "Syntax: DELETE FROM name [WHERE bedingung (AND/OR, Klammern)]");
        auto t = repo.get(m[1]);
        touch(t);
        auto hits = rowsFor(t, whereCond(m[2]));
        foreach (r; hits)
            t.markDeleted(r);
        scheduleMergeIfNeeded(t);
        return QueryResult(null, null, cast(long)hits.length, hits.length.to!string ~ " Zeile(n) gelöscht");
    }

    /// FROM-Klausel: einfache Tabelle oder Hash-Joins zu einer temporären Tabelle mit Spalten "alias.spalte".
    /// WHERE-Pushdown: Die WHERE-Bedingung wird in ihre UND-Teile zerlegt. Ein Teil, dessen Spalten alle zu einer
    /// Tabelle gehören, die der Join nicht mit NULL auffüllt (erste Tabelle oder INNER-Join-Tabelle), wird vor dem
    /// Kopieren und Joinen ausgewertet. Alles andere bleibt als `residual` und gilt nach dem Join.
    private ColumnTable resolveFrom(string fromClause, Cond cond, out Cond residual) {
        string[] parts;
        bool[] isLeft; // Art des i-ten Joins (gehört zu parts[i + 1])
        auto rest = fromClause;
        auto joinRe = ctRegex!(`\s+((?:INNER|LEFT(?:\s+OUTER)?)\s+)?JOIN\s+`, "i");
        while (true) {
            auto sm = matchFirst(rest, joinRe);
            if (sm.empty) {
                parts ~= rest;
                break;
            }
            parts ~= sm.pre;
            isLeft ~= sm[1].toUpper.startsWith("LEFT");
            rest = sm.post;
        }
        auto first = matchFirst(parts[0].strip, ctRegex!(`^(\w+)(?:\s+(?:AS\s+)?(\w+))?$`, "i"));
        enforce(!first.empty, "Ungültige FROM-Klausel: " ~ fromClause);
        if (parts.length == 1 && first[2].length == 0) {
            residual = cond; // einfache Tabelle: die Bedingung läuft direkt darauf
            return repo.get(first[1]);
        }

        FromItem[] items;
        items ~= FromItem(repo.get(first[1]), first[2].length ? first[2] : first[1], "", "", false);
        foreach (pi, part; parts[1 .. $]) {
            auto jm = matchFirst(part.strip, ctRegex!(
                    `^(\w+)(?:\s+(?:AS\s+)?(\w+))?\s+ON\s+([\w.]+)\s*=\s*([\w.]+)$`, "i"));
            enforce(!jm.empty, "Syntax: JOIN tabelle [alias] ON spalte = spalte");
            auto al = jm[2].length ? jm[2] : jm[1];
            foreach (it; items)
                enforce(icmp(it.al, al) != 0, "Alias doppelt (bei Self-Join Alias vergeben): " ~ al);
            items ~= FromItem(repo.get(jm[1]), al, jm[3], jm[4], isLeft[pi]);
        }

        // Zeilen je Tabelle: alle lebenden, danach eingeschränkt durch die vorgezogenen UND-Teile
        auto rows = new size_t[][items.length];
        foreach (i, it; items)
            rows[i] = it.table.liveRows();
        Cond[] remaining;
        foreach (conj; conjuncts(cond)) {
            size_t target = size_t.max;
            auto plain = toPlain(conj, items, target);
            if (plain is null) {
                remaining ~= conj;
                continue;
            }
            rows[target] = intersectSorted(rows[target], rowsFor(items[target].table, plain));
            ++pushedDownFilters;
        }
        residual = remaining.length == 0 ? null : (remaining.length == 1 ? remaining[0] : Cond.node(Cond.Kind.and, remaining));

        auto current = qualified(items[0].table, items[0].al, rows[0]);
        foreach (i; 1 .. items.length) {
            auto right = qualified(items[i].table, items[i].al, rows[i]);
            size_t li, ri;
            if (!(tryIndex(current, items[i].onA, li) && tryIndex(right, items[i].onB, ri)))
                enforce(tryIndex(current, items[i].onB, li) && tryIndex(right, items[i].onA, ri),
                    "ON-Bedingung passt nicht zu den Tabellen: " ~ items[i].onA ~ " = " ~ items[i]
                        .onB);
            enforce(current.defs[li].type == right.defs[ri].type, "ON: Spaltentypen passen nicht zusammen");
            current = hashJoin(current, li, right, ri, items[i].leftJoin);
        }
        return current;
    }

    /// Zeilen (aufsteigend) der Tabelle, die die Bedingung erfüllen; null = alle lebenden Zeilen.
    /// AND = Schnittmenge, OR = Vereinigung. Ohne NOT ist das auch bei NULL exakt (nur "wahr" zählt).
    private size_t[] rowsFor(ColumnTable t, Cond c) {
        if (c is null)
            return t.liveRows();
        final switch (c.kind) {
        case Cond.Kind.leaf:
            return matching(t, c.col, c.op, c.args);
        case Cond.Kind.and: {
                auto r = rowsFor(t, c.kids[0]);
                foreach (k; c.kids[1 .. $]) {
                    if (r.length == 0)
                        break;
                    r = intersectSorted(r, rowsFor(t, k));
                }
                return r;
            }
        case Cond.Kind.or: {
                auto r = rowsFor(t, c.kids[0]);
                foreach (k; c.kids[1 .. $])
                    r = unionSorted(r, rowsFor(t, k));
                return r;
            }
        }
    }

    /// Kopie der Bedingung mit unqualifizierten Spaltennamen für die Basistabelle, wenn alle Blätter zu genau
    /// einer vorziehbaren Tabelle gehören; sonst null.
    private Cond toPlain(Cond c, FromItem[] items, ref size_t target) {
        if (c.kind == Cond.Kind.leaf) {
            string plain;
            auto t = pushTarget(items, c.col, plain);
            if (t == size_t.max || (target != size_t.max && target != t))
                return null;
            target = t;
            return Cond.leaf(plain, c.op, c.args);
        }
        Cond[] kids;
        foreach (k; c.kids) {
            auto pk = toPlain(k, items, target);
            if (pk is null)
                return null;
            kids ~= pk;
        }
        return Cond.node(c.kind, kids);
    }

    /// Welche Tabelle darf die WHERE-Bedingung vorab filtern? size_t.max = keine (dann gilt sie nach dem Join).
    /// Nicht vorgezogen wird bei mehrdeutigen/unbekannten Spalten und bei LEFT-JOIN-Tabellen, denn deren
    /// Spalten werden mit NULL aufgefüllt (z.B. `WHERE o.id IS NULL` würde sonst andere Zeilen liefern).
    private size_t pushTarget(FromItem[] items, string whereCol, out string plain) {
        if (whereCol.length == 0)
            return size_t.max;
        size_t found = size_t.max;
        size_t dummy;
        auto dot = whereCol.indexOf('.');
        if (dot > 0) {
            auto qual = whereCol[0 .. dot];
            plain = whereCol[dot + 1 .. $];
            foreach (i, it; items)
                if (icmp(it.al, qual) == 0) {
                    found = i;
                    break;
                }
            if (found == size_t.max || !tryIndex(items[found].table, plain, dummy))
                return size_t.max;
        } else {
            plain = whereCol;
            foreach (i, it; items) {
                if (!tryIndex(it.table, plain, dummy))
                    continue;
                if (found != size_t.max)
                    return size_t.max; // in mehreren Tabellen vorhanden
                found = i;
            }
            if (found == size_t.max)
                return size_t.max;
        }
        return (found == 0 || !items[found].leftJoin) ? found : size_t.max;
    }

    private QueryResult select(string s) {
        bool distinct;
        auto dm = matchFirst(s, ctRegex!(`^SELECT\s+DISTINCT\s+`, "i"));
        if (!dm.empty) {
            distinct = true;
            s = "SELECT " ~ dm.post;
        }
        auto masked = maskLiterals(s);
        auto m = originalCaptures(matchFirst(masked, ctRegex!(
                `^SELECT\s+(.+?)\s+FROM\s+(.+?)(?:\s+WHERE\s+(.+?))?(?:\s+GROUP\s+BY\s+([\w.]+(?:\s*,\s*[\w.]+)*))?(?:\s+HAVING\s+(.+?))?(?:\s+ORDER\s+BY\s+(.+?))?(?:\s+LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?)?$`, "is")), masked, s);
        enforce(m.length,
            "Syntax: SELECT [DISTINCT] ... FROM name [alias] [[INNER|LEFT] JOIN name [alias] ON a = b ...] [WHERE bedingung (AND/OR, Klammern)] [GROUP BY spalte [, spalte ...]] [HAVING ausdruck op wert] "
                ~ "[ORDER BY spalte [ASC|DESC], ...] [LIMIT n [OFFSET m]]");
        Cond residual;
        auto t = resolveFrom(m[2].strip, whereCond(m[3]), residual);
        auto hits = rowsFor(t, residual);
        auto proj = m[1].strip;
        auto order = m[6].strip;

        immutable groupedQuery = m[4].length || m[5].length || hasAggregate(t, proj);
        if (distinct && !groupedQuery) {
            // SELECT DISTINCT a, b  ==  GROUP BY a, b (Gruppierung über die Dictionary-Ids)
            auto cols = proj == "*" ? t.defs.map!(d => d.name).join(", ") : proj;
            return aggregate(t, hits, cols, cols, "", order, m[7], m[8]);
        }
        if (groupedQuery)
            return aggregate(t, hits, proj, m[4], m[5].strip, order, m[7], m[8], distinct);

        hits = window(sortRows(t, hits, order), m[7], m[8]);
        size_t[] cols = proj == "*"
            ? iota(t.defs.length).array : splitList(proj).map!(c => t.indexOf(c.strip)).array;

        QueryResult res;
        res.columns = cols.map!(i => t.defs[i].name).array;
        foreach (r; hits)
            res.rows ~= cols.map!(c => t.value(c, r)).array;
        return res;
    }

    /// Aggregation mit oder ohne GROUP BY (ohne GROUP BY gibt es genau eine Gruppe).
    private QueryResult aggregate(ColumnTable t, size_t[] hits, string proj, string groupText,
        string having, string order, string limit, string offset, bool distinct = false) {
        // GROUP BY spalte [, spalte ...]: Tabellenspalten (Duplikate zählen einmal)
        size_t[] groupIdx;
        if (groupText.strip.length)
            foreach (g; splitList(groupText)) {
                auto gcolIdx = t.indexOf(g.strip);
                if (!groupIdx.canFind(gcolIdx))
                    groupIdx ~= gcolIdx;
            }
        immutable grouped = groupIdx.length > 0;

        /// Tabellenspalte einer Gruppierungsspalte (auch qualifiziert/unqualifiziert), sonst size_t.max
        size_t keyColumn(string name) {
            foreach (gi; groupIdx)
                if (refersTo(t, name, gi))
                    return gi;
            return size_t.max;
        }

        AggItem[] items;
        foreach (raw; splitList(proj)) {
            auto item = raw.strip;
            AggItem a;
            if (parseAgg(t, item, a))
                items ~= a;
            else {
                auto kc = keyColumn(item);
                enforce(kc != size_t.max,
                    "Erlaubt sind nur Gruppierungsspalten (GROUP BY) und Aggregate: " ~ item);
                items ~= AggItem(AggKind.key, kc, t.defs[kc].name, item);
            }
        }

        // HAVING: Aggregat oder Gruppierungsspalte; fehlt der Ausdruck im SELECT, wird er versteckt berechnet
        size_t havingIdx = size_t.max;
        string havingOp, havingLit;
        if (having.length) {
            auto hm = matchFirst(having, ctRegex!(
                    `^(.+?)\s*(<=|>=|!=|=|<|>|\bIS\s+NOT\b|\bIS\b)\s*(.+)$`, "is"));
            enforce(!hm.empty, "Syntax: HAVING ausdruck op wert");
            auto left = hm[1].strip;
            AggItem h;
            if (!parseAgg(t, left, h)) {
                auto kc = keyColumn(left);
                enforce(kc != size_t.max,
                    "HAVING erlaubt nur Aggregate oder Gruppierungsspalten: " ~ left);
                h = AggItem(AggKind.key, kc, t.defs[kc].name, left);
            }
            foreach (i, it; items)
                if (it.kind == h.kind && it.col == h.col && it.distinct == h.distinct) {
                    havingIdx = i;
                    break;
                }
            if (havingIdx == size_t.max) {
                h.hidden = true;
                havingIdx = items.length;
                items ~= h;
            }
            havingOp = hm[2];
            havingLit = hm[3];
        }
        // Position jeder Schlüsselspalte in der Liste der Gruppierungsspalten
        auto keyPos = new size_t[items.length];
        foreach (ii, it; items)
            if (it.kind == AggKind.key)
                foreach (c, gi; groupIdx)
                    if (gi == it.col)
                        keyPos[ii] = c;

        // Gruppen bestimmen: je Gruppierungsspalte eine dichte Id pro DISTINCT-Wert (Main und Delta); je Treffer
        // werden die Ids zu einem Schlüssel kombiniert (gemischte Basis), nicht die Werte verglichen.
        size_t groupCount = 1;
        auto rowGroup = new size_t[hits.length]; // Gruppe je Treffer (ohne GROUP BY alles Gruppe 0)
        Value[][] groupKeys; // Schlüsselwerte je Gruppe, Reihenfolge wie groupIdx
        if (grouped) {
            auto keyToId = new size_t[][groupIdx.length];
            auto idValues = new Value[][groupIdx.length];
            foreach (c, gi; groupIdx) {
                auto col = t.columns[gi];
                size_t[Value] idOf;
                keyToId[c] = new size_t[col.keySpace];
                foreach (k; 0 .. col.keySpace) {
                    auto v = col.keyValue(k);
                    if (auto p = v in idOf)
                        keyToId[c][k] = *p;
                    else {
                        keyToId[c][k] = idValues[c].length;
                        idOf[v] = idValues[c].length;
                        idValues[c] ~= v;
                    }
                }
            }

            size_t[ulong] groupOf; // kombinierter Schlüssel -> Gruppe
            groupCount = 0;
            foreach (i, r; hits) {
                ulong combined = 0;
                foreach (c, gi; groupIdx) {
                    immutable base = idValues[c].length;
                    enforce(combined < ulong.max / base, "GROUP BY: zu viele Kombinationen");
                    combined = combined * base + keyToId[c][t.columns[gi].keyAt(r)];
                }
                size_t g;
                if (auto p = combined in groupOf)
                    g = *p;
                else {
                    g = groupCount++;
                    groupOf[combined] = g;
                    Value[] key;
                    foreach (gi; groupIdx)
                        key ~= t.columns[gi].get(r);
                    groupKeys ~= key;
                }
                rowGroup[i] = g;
            }
        }

        auto counts = new long[groupCount];
        auto sums = new double[][items.length];
        auto best = new Value[][items.length];
        auto has = new bool[][items.length];
        auto nn = new long[][items.length]; // Anzahl Nicht-NULL-Werte
        foreach (i; 0 .. items.length) {
            sums[i] = new double[groupCount];
            sums[i][] = 0.0; // D initialisiert double mit NaN
            best[i] = new Value[groupCount];
            has[i] = new bool[groupCount];
            nn[i] = new long[groupCount];
        }

        // COUNT/SUM/AVG(DISTINCT x): je Wert eine dichte Id (Main und Delta können denselben Wert enthalten)
        auto denseId = new size_t[][items.length];
        auto seen = new bool[size_t][][items.length]; // seen[Item][Gruppe][Wert-Id]
        foreach (ii, it; items) {
            if (!it.distinct)
                continue;
            auto col = t.columns[it.col];
            size_t[Value] idOf;
            denseId[ii] = new size_t[col.keySpace];
            foreach (k; 0 .. col.keySpace) {
                auto v = col.keyValue(k);
                if (auto p = v in idOf)
                    denseId[ii][k] = *p;
                else {
                    immutable nid = idOf.length;
                    denseId[ii][k] = nid;
                    idOf[v] = nid;
                }
            }
            seen[ii] = new bool[size_t][groupCount];
        }

        foreach (hi, r; hits) {
            immutable g = rowGroup[hi];
            ++counts[g];
            foreach (ii, it; items) {
                if (it.kind == AggKind.key || it.kind == AggKind.count)
                    continue;
                auto v = t.value(it.col, r);
                if (isNull(v))
                    continue;
                if (it.distinct) {
                    immutable id = denseId[ii][t.columns[it.col].keyAt(r)];
                    if (id in seen[ii][g])
                        continue;
                    seen[ii][g][id] = true;
                }
                ++nn[ii][g];
                if (it.kind == AggKind.sum || it.kind == AggKind.avg)
                    sums[ii][g] += toDouble(v);
                else if (it.kind == AggKind.min || it.kind == AggKind.max) {
                    if (!has[ii][g] || (it.kind == AggKind.min ? valueLess(v, best[ii][g]) : valueLess(best[ii][g], v))) {
                        best[ii][g] = v;
                        has[ii][g] = true;
                    }
                }
            }
        }

        // ohne ORDER BY sind die Gruppen nach ihren Schlüsselwerten sortiert (spaltenweise, NULL zuerst)
        size_t[] groupsOut;
        if (grouped) {
            groupsOut = iota(groupCount).array;
            groupsOut.sort!((a, b) => lessKeys(groupKeys[a], groupKeys[b]));
        } else
            groupsOut = [0];

        Value cell(size_t ii, size_t g) {
            final switch (items[ii].kind) {
            case AggKind.key:
                return groupKeys[g][keyPos[ii]];
            case AggKind.count:
                return Value(counts[g]);
            case AggKind.countCol:
                return Value(nn[ii][g]);
            case AggKind.sum:
                return nn[ii][g] ? Value(sums[ii][g]) : nullValue;
            case AggKind.avg:
                return nn[ii][g] ? Value(sums[ii][g] / nn[ii][g]) : nullValue;
            case AggKind.min:
            case AggKind.max:
                return has[ii][g] ? best[ii][g] : nullValue;
            }
        }

        if (havingIdx != size_t.max) {
            ColumnType lt;
            final switch (items[havingIdx].kind) {
            case AggKind.count:
            case AggKind.countCol:
                lt = ColumnType.integer;
                break;
            case AggKind.sum:
            case AggKind.avg:
                lt = ColumnType.decimal;
                break;
            case AggKind.key:
            case AggKind.min:
            case AggKind.max:
                lt = t.defs[items[havingIdx].col].type;
                break;
            }
            auto needle = parseLiteral(lt, havingLit);
            size_t[] kept;
            foreach (g; groupsOut)
                if (compareOp(havingOp, cell(havingIdx, g), needle))
                    kept ~= g;
            groupsOut = kept;
        }

        AggItem[] vis;
        foreach (it; items)
            if (!it.hidden)
                vis ~= it;

        QueryResult res;
        foreach (it; vis)
            res.columns ~= it.label;
        foreach (g; groupsOut) {
            Value[] row;
            foreach (ii, it; items)
                if (!it.hidden)
                    row ~= cell(ii, g);
            res.rows ~= row;
        }

        if (distinct)
            res.rows = dedupeRows(res.rows);

        if (order.length) {
            size_t resolve(string name) {
                if (name.length && name.all!isDigit) {
                    auto n = name.to!size_t;
                    enforce(n >= 1 && n <= vis.length, "ORDER BY: ungültige Position " ~ name);
                    return n - 1;
                }
                foreach (i, it; vis)
                    if (icmp(it.label, name) == 0 || icmp(it.source, name) == 0
                        || (it.kind == AggKind.key && refersTo(t, name, it.col)))
                        return i;
                throw new Exception("ORDER BY: unbekannte Spalte " ~ name);
            }

            auto keys = parseOrder(order, &resolve);
            res.rows.sort!((x, y) => lessResult(keys, x, y), SwapStrategy.stable);
        }
        res.rows = window(res.rows, limit, offset);
        return res;
    }

    private size_t[] sortRows(ColumnTable t, size_t[] hits, string order) {
        if (order.length == 0)
            return hits;
        auto keys = parseOrder(order, (string n) => t.indexOf(n));
        hits.sort!((x, y) => lessRows(t, keys, x, y), SwapStrategy.stable);
        return hits;
    }

    /// Wertet ein Blatt der WHERE-Bedingung pro DISTINCT-Wert aus. NULL ist nie ein Treffer, auch nicht bei
    /// NOT IN / NOT BETWEEN / NOT LIKE (SQL-Dreiwertlogik: "unbekannt" zählt nicht als wahr).
    private size_t[] matching(ColumnTable t, string col, string op, string[] args) {
        auto ci = t.indexOf(col);
        auto type = t.defs[ci].type;
        auto opU = op.toUpper.split().join(" ");
        bool delegate(Value) pred;

        if (opU == "IS" || opU == "IS NOT") {
            enforce(args[0].strip.toUpper == "NULL", "Nach IS [NOT] muss NULL folgen");
            immutable wantNull = opU == "IS";
            pred = (Value v) => isNull(v) == wantNull;
        } else if (opU == "IN" || opU == "NOT IN") {
            Value[] list;
            bool hasNull;
            foreach (a; args) {
                auto lit = parseLiteral(type, a);
                if (isNull(lit))
                    hasNull = true;
                else
                    list ~= lit;
            }
            immutable negate = opU == "NOT IN";
            pred = (Value v) {
                if (isNull(v))
                    return false;
                bool found;
                foreach (x; list)
                    if (compareValues(x, v) == 0) {
                        found = true;
                        break;
                    }
                // x NOT IN (..., NULL) ist nie wahr
                return negate ? (!found && !hasNull) : found;
            };
        } else if (opU == "BETWEEN" || opU == "NOT BETWEEN") {
            auto lo = parseLiteral(type, args[0]);
            auto hi = parseLiteral(type, args[1]);
            immutable negate = opU == "NOT BETWEEN";
            pred = (Value v) {
                if (isNull(v))
                    return false;
                if (!negate)
                    return !isNull(lo) && !isNull(hi)
                        && compareValues(v, lo) >= 0 && compareValues(v, hi) <= 0;
                return (!isNull(hi) && compareValues(v, hi) > 0)
                    || (!isNull(lo) && compareValues(v, lo) < 0);
            };
        } else if (opU == "LIKE" || opU == "NOT LIKE") {
            enforce(isTextual(type), "LIKE gibt es nur für Textspalten");
            auto pat = parseLiteral(ColumnType.text, args[0]); // ein Muster ist selbst kein gültiger Wert des Typs
            immutable negate = opU == "NOT LIKE";
            if (isNull(pat))
                pred = (Value v) => false;
            else {
                dstring p;
                bool[] literal;
                compileLike((*pat.peek!string).to!dstring, args.length > 1 ? likeEscape(args[1]) : dchar.max, p, literal);
                pred = (Value v) {
                    if (isNull(v))
                        return false;
                    immutable m = likeMatch((*v.peek!string).to!dstring, p, literal);
                    return negate ? !m : m;
                };
            }
        } else {
            auto needle = parseLiteral(type, args[0]);
            pred = (Value v) => compareOp(opU, v, needle);
        }
        return t.filterLive(t.columns[ci].scan(pred));
    }
}

/// Ersetzt den Inhalt von 'Textliteralen' Byte für Byte, damit darin stehende Schlüsselwörter wie WHERE
/// nicht als Klauseln erkannt werden. Die Länge bleibt gleich, Treffer lassen sich aufs Original übertragen.
private string maskLiterals(string s) {
    auto masked = s.dup;
    bool quoted;
    foreach (ref c; masked) {
        if (c == '\'')
            quoted = !quoted;
        else if (quoted)
            c = '_';
    }
    return masked.idup;
}

/// Gruppen eines Treffers auf `masked` als Ausschnitte von `original`; leer, wenn nichts passte.
private string[] originalCaptures(C)(C m, string masked, string original) {
    string[] result;
    foreach (i; 0 .. m.length) {
        immutable start = m[i].ptr - masked.ptr;
        result ~= m[i].length ? original[start .. start + m[i].length] : "";
    }
    return result;
}

/// Tabelle, die eine schreibende Anweisung ändert; leer bei allem anderen.
private string targetTable(string s) {
    auto m = matchFirst(s, ctRegex!(`^\s*(?:CREATE\s+TABLE|DROP\s+TABLE|INSERT\s+INTO|DELETE\s+FROM|UPDATE)\s+(\w+)`, "i"));
    return m.empty ? "" : m[1];
}

/// Komma-Trennung, die Kommas in 'Textliteralen' ignoriert.
private string[] splitList(string s) {
    string[] result;
    string cur;
    bool quoted;
    foreach (c; s) {
        if (c == '\'')
            quoted = !quoted;
        if (c == ',' && !quoted) {
            result ~= cur;
            cur = "";
        } else
            cur ~= c;
    }
    result ~= cur;
    return result;
}

private string dumpCreate(ColumnTable t) {
    string[] cols;
    foreach (d; t.defs)
        cols ~= d.name ~ " " ~ typeName(d.type);
    return "CREATE TABLE " ~ t.name ~ " (" ~ cols.join(", ") ~ ")";
}

private string dumpRow(ColumnTable t, size_t row) {
    string[] lits;
    foreach (ci, d; t.defs)
        lits ~= toSqlLiteral(t.value(ci, row));
    return "INSERT INTO " ~ t.name ~ " VALUES (" ~ lits.join(", ") ~ ")";
}

private enum AggKind {
    key,
    count,
    countCol,
    sum,
    avg,
    min,
    max
}

private struct AggItem {
    AggKind kind;
    size_t col;
    string label; // Spaltenname im Ergebnis, z.B. SUM(amount)
    string source; // Ausdruck wie im SELECT angegeben
    bool hidden; // nur für HAVING berechnet, nicht im Ergebnis
    bool distinct; // COUNT/SUM/AVG(DISTINCT x)
}

private struct SortKey {
    size_t col;
    bool desc;
}

/// Erkennt COUNT(*), COUNT(x), SUM(x), AVG(x), MIN(x), MAX(x); bei COUNT/SUM/AVG auch mit DISTINCT.
private bool parseAgg(ColumnTable t, string item, out AggItem a) {
    auto m = matchFirst(item.strip, ctRegex!(
            `^(COUNT|SUM|AVG|MIN|MAX)\s*\(\s*(DISTINCT\s+)?(.+?)\s*\)$`, "is"));
    if (m.empty)
        return false;
    auto fn = m[1].toUpper;
    immutable distinct = m[2].length > 0;
    auto arg = m[3].strip;
    if (arg == "*") {
        enforce(fn == "COUNT" && !distinct, fn ~ "(" ~ (distinct ? "DISTINCT " : "") ~ "*) wird nicht unterstützt");
        a = AggItem(AggKind.count, 0, "COUNT", item);
        return true;
    }
    auto ci = t.indexOf(arg);
    AggKind kind;
    switch (fn) {
    case "COUNT":
        kind = AggKind.countCol;
        break;
    case "SUM":
        kind = AggKind.sum;
        break;
    case "AVG":
        kind = AggKind.avg;
        break;
    case "MIN":
        kind = AggKind.min;
        break;
    default:
        kind = AggKind.max;
        break;
    }
    if (kind == AggKind.sum || kind == AggKind.avg)
        enforce(isNumeric(t.defs[ci].type), fn ~ " nur für numerische Spalten");
    // DISTINCT ändert MIN/MAX nicht
    immutable effective = distinct && kind != AggKind.min && kind != AggKind.max;
    a = AggItem(kind, ci, fn ~ "(" ~ (effective ? "DISTINCT " : "") ~ t.defs[ci].name ~ ")", item, false, effective);
    return true;
}

private bool hasAggregate(ColumnTable t, string proj) {
    foreach (raw; splitList(proj)) {
        AggItem a;
        if (parseAgg(t, raw.strip, a))
            return true;
    }
    return false;
}

private SortKey[] parseOrder(string order, size_t delegate(string) resolve) {
    SortKey[] keys;
    foreach (part; splitList(order)) {
        auto p = part.strip.split();
        enforce(p.length == 1 || p.length == 2, "Ungültige ORDER-BY-Angabe: " ~ part.strip);
        bool desc = false;
        if (p.length == 2) {
            auto d = p[1].toUpper;
            enforce(d == "ASC" || d == "DESC", "ORDER BY erwartet ASC oder DESC: " ~ p[1]);
            desc = d == "DESC";
        }
        keys ~= SortKey(resolve(p[0]), desc);
    }
    return keys;
}

private bool compareOp(string op, Value a, Value b) {
    if (isNull(a) || isNull(b))
        return false;
    immutable c = cmpValues(a, b);
    switch (op) {
    case "=":
        return c == 0;
    case "!=":
        return c != 0;
    case "<":
        return c < 0;
    case ">":
        return c > 0;
    case "<=":
        return c <= 0;
    case ">=":
        return c >= 0;
    default:
        throw new Exception("Unbekannter Operator: " ~ op);
    }
}

/// LIMIT n [OFFSET m] als Ausschnitt.
private T[] window(T)(T[] a, string limit, string offset) {
    if (limit.length == 0)
        return a;
    size_t off = offset.length ? offset.to!size_t : 0;
    size_t lim = limit.to!size_t;
    if (off >= a.length)
        return null;
    return a[off .. (lim > a.length - off ? a.length : off + lim)];
}

private int cmpValues(Value a, Value b) {
    return compareValues(a, b);
}

private bool lessRows(ColumnTable t, SortKey[] keys, size_t x, size_t y) {
    foreach (k; keys) {
        auto c = cmpValues(t.value(k.col, x), t.value(k.col, y));
        if (c != 0)
            return k.desc ? c > 0 : c < 0;
    }
    return false;
}

private bool lessResult(SortKey[] keys, Value[] x, Value[] y) {
    foreach (k; keys) {
        auto c = cmpValues(x[k.col], y[k.col]);
        if (c != 0)
            return k.desc ? c > 0 : c < 0;
    }
    return false;
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE o (c VARCHAR(10), a DECIMAL)");
    s.execute("INSERT INTO o VALUES ('x', 1.5)");
    s.execute("INSERT INTO o VALUES ('y', 2)");
    foreach (round; 0 .. 2) {
        if (round == 1)
            s.mergeDelta();
        auto r = s.execute("SELECT c, COUNT(*), SUM(a) FROM o GROUP BY c");
        assert(r.rows.length == 2);
        assert(r.rows[0][1] == Value(round == 0 ? 1L : 2L)); // 'x' hat nach Runde 0 eine Zeile mehr
        assert(r.rows[1][1] == Value(1L));
        if (round == 0)
            s.execute("INSERT INTO o VALUES ('x', 3)");
    }
    auto r = s.execute("SELECT c, COUNT(*), SUM(a) FROM o WHERE a >= 2 GROUP BY c");
    assert(r.rows.length == 2 && r.rows[0][2] == Value(3.0) && r.rows[1][2] == Value(2.0));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE p (n VARCHAR(10), q INTEGER, w DECIMAL)");
    s.execute("INSERT INTO p VALUES ('a', 3, 1.0)");
    s.execute("INSERT INTO p VALUES ('b', 1, 4.0)");
    s.execute("INSERT INTO p VALUES ('a', 2, 3.0)");

    auto r = s.execute("SELECT n FROM p ORDER BY q DESC");
    assert(r.rows.length == 3 && r.rows[0][0] == Value("a") && r.rows[2][0] == Value("b"));

    r = s.execute("SELECT n, MIN(q), MAX(q), AVG(w) FROM p GROUP BY n ORDER BY AVG(w) DESC");
    assert(r.rows[0][0] == Value("b") && r.rows[0][3] == Value(4.0));
    assert(r.rows[1][1] == Value(2L) && r.rows[1][2] == Value(3L) && r.rows[1][3] == Value(2.0));

    r = s.execute("SELECT MAX(n), COUNT(*) FROM p");
    assert(r.rows[0][0] == Value("b") && r.rows[0][1] == Value(3L));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE h (g VARCHAR(5), v INTEGER)");
    foreach (row; [
            "('a', 1)", "('a', 2)", "('a', 3)", "('b', 10)", "('c', 5)",
            "('c', 5)"
        ])
        s.execute("INSERT INTO h VALUES " ~ row);

    auto r = s.execute(
        "SELECT g, SUM(v) FROM h GROUP BY g HAVING COUNT(*) >= 2 ORDER BY SUM(v) DESC");
    assert(r.columns.length == 2 && r.rows.length == 2 && r.rows[0][0] == Value("c"));

    r = s.execute("SELECT g FROM h ORDER BY v DESC LIMIT 2 OFFSET 1");
    assert(r.rows.length == 2 && r.rows[0][0] == Value("c") && r.rows[1][0] == Value("c"));

    r = s.execute("SELECT g, COUNT(*) FROM h GROUP BY g HAVING g != 'b' LIMIT 1");
    assert(r.rows.length == 1 && r.rows[0][0] == Value("a"));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE u (k INTEGER, v VARCHAR(5))");
    foreach (i; 1 .. 6)
        s.execute("INSERT INTO u VALUES (" ~ i.to!string ~ ", 'x')");

    auto r = s.execute("DELETE FROM u WHERE k >= 4");
    assert(r.affected == 2);
    assert(s.execute("SELECT COUNT(*) FROM u").rows[0][0] == Value(3L));

    r = s.execute("UPDATE u SET v = 'y' WHERE k = 2");
    assert(r.affected == 1);
    r = s.execute("SELECT k, v FROM u ORDER BY k");
    assert(r.rows.length == 3 && r.rows[0][1] == Value("x") && r.rows[1][1] == Value("y"));

    s.mergeDelta(); // entfernt die gelöschten Zeilen physisch
    r = s.execute("SELECT k FROM u ORDER BY k DESC");
    assert(r.rows.length == 3 && r.rows[0][0] == Value(3L));

    assert(s.execute("DELETE FROM u").affected == 3);
    assert(s.execute("SELECT COUNT(*) FROM u").rows[0][0] == Value(0L));
}

private bool tryIndex(ColumnTable t, string name, out size_t idx) {
    try {
        idx = t.indexOf(name);
        return true;
    } catch (Exception)
        return false;
}

private bool refersTo(ColumnTable t, string name, size_t idx) {
    size_t i;
    return tryIndex(t, name, i) && i == idx;
}

/// Kopie der lebenden Zeilen mit Spaltennamen "alias.spalte".
private ColumnTable qualified(ColumnTable src, string al, size_t[] rows) {
    ColumnDef[] defs;
    foreach (d; src.defs)
        defs ~= ColumnDef(al ~ "." ~ d.name, d.type);
    auto t = new ColumnTable("(" ~ al ~ ")", defs);
    foreach (r; rows) {
        Value[] row;
        foreach (ci; 0 .. src.defs.length)
            row ~= src.value(ci, r);
        t.insert(row);
    }
    return t;
}

/// Equi-Hash-Join (INNER oder LEFT): Hash-Tabelle über die rechte Seite, Probe mit der linken.
/// NULL-Schlüssel passen auf nichts; bei LEFT bekommen unpassende linke Zeilen NULL auf der rechten Seite.
private ColumnTable hashJoin(ColumnTable left, size_t li, ColumnTable right, size_t ri, bool leftOuter) {
    size_t[][Value] index;
    foreach (r; right.liveRows()) {
        auto key = right.value(ri, r);
        if (!isNull(key))
            index[key] ~= r;
    }

    auto result = new ColumnTable("(join)", left.defs.dup ~ right.defs.dup);
    foreach (lr; left.liveRows()) {
        auto key = left.value(li, lr);
        size_t[]* matches;
        if (!isNull(key))
            matches = key in index;

        Value[] leftPart;
        foreach (ci; 0 .. left.defs.length)
            leftPart ~= left.value(ci, lr);

        if (matches !is null) {
            foreach (rr; *matches) {
                auto row = leftPart.dup;
                foreach (ci; 0 .. right.defs.length)
                    row ~= right.value(ci, rr);
                result.insert(row);
            }
        } else if (leftOuter) {
            auto row = leftPart.dup;
            foreach (ci; 0 .. right.defs.length)
                row ~= nullValue;
            result.insert(row);
        }
    }
    result.mergeDelta();
    return result;
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE cu (id INTEGER, name VARCHAR(10))");
    s.execute("CREATE TABLE od (id INTEGER, cid INTEGER, amt DECIMAL)");
    foreach (row; ["(1, 'ann')", "(2, 'bob')", "(3, 'cy')"])
        s.execute("INSERT INTO cu VALUES " ~ row);
    foreach (row; [
            "(10, 1, 5.0)", "(11, 1, 7.0)", "(12, 2, 1.0)", "(13, 9, 2.0)"
        ])
        s.execute("INSERT INTO od VALUES " ~ row);

    auto r = s.execute("SELECT c.name, SUM(o.amt) FROM cu c JOIN od o ON c.id = o.cid "
            ~ "GROUP BY c.name ORDER BY SUM(o.amt) DESC");
    assert(r.rows.length == 2 && r.rows[0][0] == Value("ann") && r.rows[0][1] == Value(12.0));

    r = s.execute("SELECT name, amt FROM cu JOIN od ON cu.id = od.cid WHERE amt >= 2 ORDER BY amt");
    assert(r.rows.length == 2 && r.rows[0][1] == Value(5.0) && r.rows[1][1] == Value(7.0));

    r = s.execute("SELECT COUNT(*) FROM cu JOIN od ON cu.id = od.cid");
    assert(r.rows[0][0] == Value(3L));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE cu (id INTEGER, name VARCHAR(10))");
    s.execute("CREATE TABLE od (id INTEGER, cid INTEGER, amt DECIMAL)");
    foreach (row; ["(1, 'ann')", "(2, 'bob')", "(3, 'cy')"])
        s.execute("INSERT INTO cu VALUES " ~ row);
    foreach (row; [
            "(10, 1, 5.0)", "(11, 1, 7.0)", "(12, 2, 1.0)", "(13, 9, 2.0)"
        ])
        s.execute("INSERT INTO od VALUES " ~ row);

    auto r = s.execute(
        "SELECT c.name, COUNT(o.id) FROM cu c LEFT JOIN od o ON c.id = o.cid "
            ~ "GROUP BY c.name ORDER BY c.name");
    assert(r.rows.length == 3 && r.rows[2][0] == Value("cy") && r.rows[2][1] == Value(0L));
    assert(r.rows[0][1] == Value(2L));

    r = s.execute("SELECT c.name FROM cu c LEFT JOIN od o ON c.id = o.cid WHERE o.id IS NULL");
    assert(r.rows.length == 1 && r.rows[0][0] == Value("cy"));

    r = s.execute("SELECT SUM(o.amt) FROM cu c LEFT JOIN od o ON c.id = o.cid WHERE c.name = 'cy'");
    assert(r.rows.length == 1 && isNull(r.rows[0][0]));

    s.execute("INSERT INTO cu VALUES (4, NULL)");
    r = s.execute("SELECT COUNT(*), COUNT(name) FROM cu");
    assert(r.rows[0][0] == Value(4L) && r.rows[0][1] == Value(3L));
    r = s.execute("SELECT id FROM cu WHERE name IS NOT NULL ORDER BY id");
    assert(r.rows.length == 3);
    r = s.execute("SELECT id FROM cu ORDER BY name");
    assert(r.rows[0][0] == Value(4L)); // NULL sortiert zuerst
}

private final class Transaction {
    string id;
    MonoTime lastActive;
    ColumnTable[string] before; // Snapshots geänderter Tabellen (Schlüssel: kleingeschriebener Name)
    string[string] created; // in der Transaktion angelegte Tabellen
    string[] stmts; // schreibende Anweisungen für das Log
    string[string] flushes; // Tabellen mit eigener Datei, die beim COMMIT geschrieben werden
    size_t fileWrites; // Anweisungen auf diesen Tabellen
    string[] changes; // alle schreibenden Anweisungen, für den Änderungsstrom
}

unittest {
    static class FakeRepo : ITableRepository {
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

    static class MemLog : IStatementLog {
        string[] lines;
        void append(string st) {
            lines ~= st;
        }

        void appendAll(string[] a) {
            lines ~= a;
        }

        string[] readAll() {
            return lines.dup;
        }

        void replaceAll(string[] a) {
            lines = a.dup;
        }
    }

    auto log = new MemLog;
    auto s = new SqlService(new FakeRepo, log);
    s.execute("CREATE TABLE a (k INTEGER)");
    s.execute("INSERT INTO a VALUES (1)");

    // ROLLBACK: Änderungen und neue Tabellen verschwinden, andere Sitzungen sind ausgesperrt
    auto tx = s.execute("BEGIN").transaction;
    assert(tx.length > 0);
    s.executeIn(tx, "INSERT INTO a VALUES (2)");
    s.executeIn(tx, "UPDATE a SET k = 10 WHERE k = 1");
    s.executeIn(tx, "CREATE TABLE tmp (x INTEGER)");
    assert(s.executeIn(tx, "SELECT COUNT(*) FROM a").rows[0][0] == Value(2L));
    bool blocked;
    try
        s.execute("SELECT COUNT(*) FROM a");
    catch (Exception)
        blocked = true;
    assert(blocked);
    s.executeIn(tx, "ROLLBACK");
    assert(s.execute("SELECT COUNT(*) FROM a").rows[0][0] == Value(1L));
    assert(s.execute("SELECT k FROM a").rows[0][0] == Value(1L));
    s.execute("CREATE TABLE tmp (x INTEGER)"); // wäre sonst "existiert bereits"

    // COMMIT: sichtbar und als Gruppe im Log; die alte Transaktions-ID ist danach ungültig
    tx = s.execute("BEGIN").transaction;
    s.executeIn(tx, "INSERT INTO a VALUES (5)");
    s.executeIn(tx, "COMMIT");
    assert(s.execute("SELECT COUNT(*) FROM a").rows[0][0] == Value(2L));
    bool stale;
    try
        s.executeIn(tx, "SELECT COUNT(*) FROM a");
    catch (Exception)
        stale = true;
    assert(stale);

    // Wiederherstellung: unvollständige Gruppe am Ende wird verworfen
    log.lines ~= ["BEGIN", "INSERT INTO a VALUES (99)"];
    auto s2 = new SqlService(new FakeRepo, log);
    s2.recover();
    assert(s2.execute("SELECT COUNT(*) FROM a").rows[0][0] == Value(2L));
    assert(s2.execute("SELECT COUNT(*) FROM a WHERE k = 99").rows[0][0] == Value(0L));
}

private struct FromItem {
    ColumnTable table;
    string al; // Alias (sonst Tabellenname)
    string onA, onB; // ON-Bedingung des Joins (leer bei der ersten Tabelle)
    bool leftJoin; // mit LEFT JOIN angebunden
}

unittest {
    import std.exception : assertThrown;

    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE cu (id INTEGER, name VARCHAR(10))");
    s.execute("CREATE TABLE od (id INTEGER, cid INTEGER, amt DECIMAL)");
    foreach (row; ["(1, 'ann')", "(2, 'bob')", "(3, 'cy')"])
        s.execute("INSERT INTO cu VALUES " ~ row);
    foreach (row; [
            "(10, 1, 5.0)", "(11, 1, 7.0)", "(12, 2, 1.0)", "(13, 9, 2.0)"
        ])
        s.execute("INSERT INTO od VALUES " ~ row);

    // INNER JOIN: Filter auf die rechte Seite wird vorgezogen
    auto before = s.pushedDownFilters;
    auto r = s.execute(
        "SELECT c.name, o.amt FROM cu c JOIN od o ON c.id = o.cid WHERE o.amt >= 5 ORDER BY o.amt");
    assert(s.pushedDownFilters == before + 1);
    assert(r.rows.length == 2 && r.rows[0][1] == Value(5.0) && r.rows[1][1] == Value(7.0));

    // LEFT JOIN: Filter auf die linke Seite wird vorgezogen
    before = s.pushedDownFilters;
    r = s.execute("SELECT c.name FROM cu c LEFT JOIN od o ON c.id = o.cid WHERE c.name = 'cy'");
    assert(s.pushedDownFilters == before + 1 && r.rows.length == 1);

    // LEFT JOIN: Filter auf die NULL-ergänzte Seite darf NICHT vorgezogen werden
    before = s.pushedDownFilters;
    r = s.execute("SELECT c.name FROM cu c LEFT JOIN od o ON c.id = o.cid WHERE o.id IS NULL");
    assert(s.pushedDownFilters == before && r.rows.length == 1 && r.rows[0][0] == Value("cy"));

    // unqualifiziert und eindeutig (amt gibt es nur in od)
    before = s.pushedDownFilters;
    r = s.execute("SELECT name FROM cu JOIN od ON cu.id = od.cid WHERE amt > 1");
    assert(s.pushedDownFilters == before + 1 && r.rows.length == 2);

    // mehrdeutig (id gibt es in beiden): kein Pushdown, Fehler nach dem Join
    before = s.pushedDownFilters;
    assertThrown(s.execute("SELECT name FROM cu JOIN od ON cu.id = od.cid WHERE id = 1"));
    assert(s.pushedDownFilters == before);

    // einzelne Tabelle mit Alias: es werden nur die Treffer kopiert
    before = s.pushedDownFilters;
    r = s.execute("SELECT o.id FROM od o WHERE o.amt < 3 ORDER BY o.id");
    assert(s.pushedDownFilters == before + 1 && r.rows.length == 2 && r.rows[0][0] == Value(12L));
}

/// WHERE-Bedingung als Baum: Blätter vergleichen eine Spalte mit einem Literal, AND/OR verknüpfen.
private final class Cond {
    enum Kind {
        leaf,
        and,
        or
    }

    Kind kind;
    string col, op; // nur bei Blättern
    string[] args; // Literale: eines bei Vergleichen, mehrere bei IN und BETWEEN
    Cond[] kids; // nur bei AND/OR

    static Cond leaf(string col, string op, string[] args) {
        auto c = new Cond;
        c.kind = Kind.leaf;
        c.col = col;
        c.op = op;
        c.args = args;
        return c;
    }

    static Cond node(Kind kind, Cond[] kids) {
        auto c = new Cond;
        c.kind = kind;
        c.kids = kids;
        return c;
    }
}

/// Oberste UND-Teile einer Bedingung (ein OR oder Blatt ist ein einziger Teil).
private Cond[] conjuncts(Cond c) {
    if (c is null)
        return null;
    return c.kind == Cond.Kind.and ? c.kids : [c];
}

private Cond whereCond(string text) {
    return text.strip.length ? parseWhere(text) : null;
}

private size_t[] intersectSorted(size_t[] a, size_t[] b) {
    size_t[] r;
    size_t i, j;
    while (i < a.length && j < b.length) {
        if (a[i] < b[j])
            ++i;
        else if (a[i] > b[j])
            ++j;
        else {
            r ~= a[i];
            ++i;
            ++j;
        }
    }
    return r;
}

private size_t[] unionSorted(size_t[] a, size_t[] b) {
    size_t[] r;
    size_t i, j;
    while (i < a.length || j < b.length) {
        if (j == b.length)
            r ~= a[i++];
        else if (i == a.length)
            r ~= b[j++];
        else if (a[i] < b[j])
            r ~= a[i++];
        else if (a[i] > b[j])
            r ~= b[j++];
        else {
            r ~= a[i];
            ++i;
            ++j;
        }
    }
    return r;
}

private enum TokKind {
    word,
    str,
    op,
    open,
    close,
    comma
}

private struct Token {
    TokKind kind;
    string text;
}

/// Zerlegt eine WHERE-Bedingung; Textliterale ('...' mit '' als Escape) und Binärliterale (X'...') bleiben unangetastet.
private Token[] tokenize(string s) {
    Token[] r;
    size_t i = 0;
    while (i < s.length) {
        immutable c = s[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            ++i;
        } else if (c == '(') {
            r ~= Token(TokKind.open, "(");
            ++i;
        } else if (c == ')') {
            r ~= Token(TokKind.close, ")");
            ++i;
        } else if (c == ',') {
            r ~= Token(TokKind.comma, ",");
            ++i;
        } else if (c == '\'' || ((c == 'X' || c == 'x') && i + 1 < s.length && s[i + 1] == '\'')) {
            size_t j = (c == '\'' ? i : i + 1) + 1;
            while (true) {
                enforce(j < s.length, "Textliteral in WHERE nicht abgeschlossen");
                if (s[j] == '\'') {
                    if (j + 1 < s.length && s[j + 1] == '\'') {
                        j += 2;
                        continue;
                    }
                    break;
                }
                ++j;
            }
            r ~= Token(TokKind.str, s[i .. j + 1]);
            i = j + 1;
        } else if (c == '<' || c == '>' || c == '=' || c == '!') {
            string op;
            if (i + 1 < s.length && (s[i + 1] == '=' || (c == '<' && s[i + 1] == '>'))) {
                op = s[i .. i + 2];
                i += 2;
            } else {
                op = s[i .. i + 1];
                ++i;
            }
            if (op == "<>")
                op = "!=";
            enforce(op != "!", "Ungültiger Operator in WHERE: !");
            r ~= Token(TokKind.op, op);
        } else {
            size_t j = i;
            while (j < s.length && !" \t\r\n(),'<>=!".canFind(s[j]))
                ++j;
            r ~= Token(TokKind.word, s[i .. j]);
            i = j;
        }
    }
    return r;
}

private bool isWord(Token t, string w) {
    return t.kind == TokKind.word && icmp(t.text, w) == 0;
}

/// WHERE := UND-Ausdruck { OR UND-Ausdruck }; UND-Ausdruck := Primär { AND Primär };
/// Primär := '(' WHERE ')' | spalte op wert | spalte IS [NOT] NULL. AND bindet stärker als OR.
private Cond parseWhere(string text) {
    auto toks = tokenize(text);
    size_t pos = 0;
    auto c = parseOr(toks, pos);
    enforce(pos == toks.length, "Unerwartetes Token in WHERE: " ~ toks[pos].text);
    return c;
}

private Cond parseOr(Token[] toks, ref size_t pos) {
    Cond[] kids = [parseAnd(toks, pos)];
    while (pos < toks.length && isWord(toks[pos], "OR")) {
        ++pos;
        kids ~= parseAnd(toks, pos);
    }
    return kids.length == 1 ? kids[0] : Cond.node(Cond.Kind.or, kids);
}

private Cond parseAnd(Token[] toks, ref size_t pos) {
    Cond[] kids = [parsePrimary(toks, pos)];
    while (pos < toks.length && isWord(toks[pos], "AND")) {
        ++pos;
        kids ~= parsePrimary(toks, pos);
    }
    return kids.length == 1 ? kids[0] : Cond.node(Cond.Kind.and, kids);
}

private Cond parsePrimary(Token[] toks, ref size_t pos) {
    enforce(pos < toks.length, "WHERE: Bedingung erwartet");
    if (toks[pos].kind == TokKind.open) {
        ++pos;
        auto c = parseOr(toks, pos);
        enforce(pos < toks.length && toks[pos].kind == TokKind.close, "WHERE: ')' fehlt");
        ++pos;
        return c;
    }
    enforce(toks[pos].kind == TokKind.word, "WHERE: Spaltenname erwartet statt " ~ toks[pos].text);
    auto col = toks[pos++].text;
    enforce(pos < toks.length, "WHERE: Operator erwartet nach " ~ col);

    if (toks[pos].kind == TokKind.op) {
        auto op = toks[pos++].text;
        return Cond.leaf(col, op, [parseValue(toks, pos, col)]);
    }
    if (isWord(toks[pos], "IS")) {
        ++pos;
        string op = "IS";
        if (pos < toks.length && isWord(toks[pos], "NOT")) {
            ++pos;
            op = "IS NOT";
        }
        return Cond.leaf(col, op, [parseValue(toks, pos, col)]);
    }

    bool negated = false;
    if (isWord(toks[pos], "NOT")) {
        negated = true;
        ++pos;
        enforce(pos < toks.length, "WHERE: IN, BETWEEN oder LIKE erwartet nach NOT");
    }
    enforce(toks[pos].kind == TokKind.word, "WHERE: Operator erwartet statt " ~ toks[pos].text);
    auto kw = toks[pos++].text.toUpper;
    immutable prefix = negated ? "NOT " : "";
    switch (kw) {
    case "IN": {
            enforce(pos < toks.length && toks[pos].kind == TokKind.open, "WHERE: '(' nach IN erwartet");
            ++pos;
            string[] list;
            while (true) {
                list ~= parseValue(toks, pos, col);
                enforce(pos < toks.length, "WHERE: ')' fehlt");
                if (toks[pos].kind == TokKind.comma) {
                    ++pos;
                    continue;
                }
                enforce(toks[pos].kind == TokKind.close, "WHERE: ',' oder ')' erwartet");
                ++pos;
                break;
            }
            return Cond.leaf(col, prefix ~ "IN", list);
        }
    case "BETWEEN": {
            auto lo = parseValue(toks, pos, col);
            enforce(pos < toks.length && isWord(toks[pos], "AND"), "WHERE: BETWEEN braucht AND");
            ++pos;
            auto hi = parseValue(toks, pos, col);
            return Cond.leaf(col, prefix ~ "BETWEEN", [lo, hi]);
        }
    case "LIKE": {
            string[] likeArgs = [parseValue(toks, pos, col)];
            if (pos < toks.length && isWord(toks[pos], "ESCAPE")) {
                ++pos;
                likeArgs ~= parseValue(toks, pos, col);
            }
            return Cond.leaf(col, prefix ~ "LIKE", likeArgs);
        }
    default:
        throw new Exception("WHERE: Operator erwartet statt " ~ kw);
    }
}

private string parseValue(Token[] toks, ref size_t pos, string col) {
    enforce(pos < toks.length && (toks[pos].kind == TokKind.word || toks[pos].kind == TokKind.str),
        "WHERE: Wert erwartet nach " ~ col);
    return toks[pos++].text;
}

/// Das Zeichen aus ESCAPE 'x'.
private dchar likeEscape(string literal) {
    auto text = parseLiteral(ColumnType.text, literal);
    enforce(!isNull(text), "ESCAPE braucht genau ein Zeichen");
    auto chars = (*text.peek!string).to!dstring;
    enforce(chars.length == 1, "ESCAPE braucht genau ein Zeichen");
    return chars[0];
}

/// Löst das Escape-Zeichen auf: literal[i] sagt, ob p[i] kein Platzhalter ist.
private void compileLike(dstring pattern, dchar escape, out dstring p, out bool[] literal) {
    dchar[] chars;
    for (size_t i = 0; i < pattern.length; ++i) {
        immutable escaped = pattern[i] == escape;
        if (escaped) {
            enforce(i + 1 < pattern.length, "LIKE: Muster endet mit dem Escape-Zeichen");
            ++i;
        }
        chars ~= pattern[i];
        literal ~= escaped;
    }
    p = chars.idup;
}

/// SQL-LIKE: % = beliebig viele Zeichen, _ = genau ein Zeichen (Groß-/Kleinschreibung zählt).
private bool likeMatch(const(dchar)[] s, const(dchar)[] p, const(bool)[] literal) {
    bool isWildcard(size_t j, dchar c) {
        return p[j] == c && !literal[j];
    }

    size_t si, pj, mark;
    size_t star = size_t.max;
    while (si < s.length) {
        if (pj < p.length && (isWildcard(pj, '_') || (!isWildcard(pj, '%') && p[pj] == s[si]))) {
            ++si;
            ++pj;
        } else if (pj < p.length && isWildcard(pj, '%')) {
            star = pj++;
            mark = si;
        } else if (star != size_t.max) {
            pj = star + 1;
            si = ++mark;
        } else
            return false;
    }
    while (pj < p.length && isWildcard(pj, '%'))
        ++pj;
    return pj == p.length;
}

unittest {
    import std.exception : assertThrown;

    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE w (k INTEGER, n VARCHAR(10), v DECIMAL)");
    foreach (row; [
            "(1, 'a', 1.0)", "(2, 'b', NULL)", "(3, 'a', 3.0)", "(4, 'c', 4.0)",
            "(5, NULL, 5.0)", "(6, 'x AND y', 6.0)"
        ])
        s.execute("INSERT INTO w VALUES " ~ row);

    long[] keys(string where) {
        long[] result;
        foreach (row; s.execute("SELECT k FROM w WHERE " ~ where ~ " ORDER BY k").rows)
            result ~= *row[0].peek!long;
        return result;
    }

    assert(keys("n = 'a' AND v > 1") == [3L]);
    assert(keys("n = 'a' OR k = 4") == [1L, 3, 4]);
    assert(keys("(n = 'a' OR n = 'b') AND v IS NOT NULL") == [1L, 3]);
    assert(keys("n = 'a' OR n = 'b' AND k > 100") == [1L, 3]); // AND bindet stärker als OR
    assert(keys("n = 'x AND y'") == [6L]); // Schlüsselwort im Textliteral
    assert(keys("n IS NULL OR v >= 5") == [5L, 6]);
    assert(keys("k <> 1 AND k <= 3") == [2L, 3]);

    assertThrown(s.execute("SELECT k FROM w WHERE k = 1 AND"));
    assertThrown(s.execute("SELECT k FROM w WHERE (k = 1"));

    assert(s.execute("UPDATE w SET v = 0 WHERE n = 'a' AND k >= 3").affected == 1);
    assert(s.execute("DELETE FROM w WHERE k = 1 OR k = 2").affected == 2);
    assert(s.execute("SELECT COUNT(*) FROM w").rows[0][0] == Value(4L));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE cu (id INTEGER, name VARCHAR(10))");
    s.execute("CREATE TABLE od (id INTEGER, cid INTEGER, amt DECIMAL)");
    foreach (row; ["(1, 'ann')", "(2, 'bob')", "(3, 'cy')"])
        s.execute("INSERT INTO cu VALUES " ~ row);
    foreach (row; [
            "(10, 1, 5.0)", "(11, 1, 7.0)", "(12, 2, 1.0)", "(13, 9, 2.0)"
        ])
        s.execute("INSERT INTO od VALUES " ~ row);

    // zwei UND-Teile auf verschiedenen Tabellen: beide werden vorgezogen
    auto before = s.pushedDownFilters;
    auto r = s.execute(
        "SELECT c.name, o.amt FROM cu c JOIN od o ON c.id = o.cid "
            ~ "WHERE c.name = 'ann' AND o.amt > 5");
    assert(s.pushedDownFilters == before + 2 && r.rows.length == 1 && r.rows[0][1] == Value(7.0));

    // ein OR über zwei Tabellen lässt sich nicht vorziehen, das Ergebnis stimmt trotzdem
    before = s.pushedDownFilters;
    r = s.execute("SELECT c.name, o.amt FROM cu c JOIN od o ON c.id = o.cid "
            ~ "WHERE c.name = 'ann' OR o.amt > 1 ORDER BY o.amt");
    assert(s.pushedDownFilters == before && r.rows.length == 2);

    // LEFT JOIN: linker Teil wird vorgezogen, der Teil auf die NULL-ergänzte Seite bleibt nach dem Join
    before = s.pushedDownFilters;
    r = s.execute("SELECT c.name FROM cu c LEFT JOIN od o ON c.id = o.cid "
            ~ "WHERE c.name = 'cy' AND o.id IS NULL");
    assert(s.pushedDownFilters == before + 1 && r.rows.length == 1 && r.rows[0][0] == Value("cy"));

    // ein OR auf nur einer Tabelle ist ein einziger vorziehbarer Teil
    before = s.pushedDownFilters;
    r = s.execute(
        "SELECT o.id FROM cu c JOIN od o ON c.id = o.cid WHERE o.amt = 1 OR o.amt = 7 ORDER BY o.id");
    assert(s.pushedDownFilters == before + 1 && r.rows.length == 2);
}

unittest {
    import std.exception : assertThrown;

    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE p (k INTEGER, n VARCHAR(20), v DECIMAL)");
    foreach (row; [
            "(1, 'apple', 1.0)", "(2, 'banana', 2.5)", "(3, 'cherry', NULL)",
            "(4, 'apricot', 4.0)",
            "(5, NULL, 5.0)", "(6, 'a_b', 6.0)", "(7, '100%', 7.0)"
        ])
        s.execute("INSERT INTO p VALUES " ~ row);

    long[] keys(string where) {
        long[] result;
        foreach (row; s.execute("SELECT k FROM p WHERE " ~ where ~ " ORDER BY k").rows)
            result ~= *row[0].peek!long;
        return result;
    }

    // LIKE
    assert(keys("n LIKE 'a%'") == [1L, 4, 6]);
    assert(keys("n LIKE '%an%'") == [2L]);
    assert(keys("n LIKE 'a__le'") == [1L]);
    assert(keys("n LIKE '_pple'") == [1L]);
    assert(keys("n LIKE '100%'") == [7L]);
    assert(keys("n LIKE '100\\%' ESCAPE '\\'") == [7L]); // Inhalt von Zeile 7 ist genau '100%'
    assert(keys("n LIKE '1\\%' ESCAPE '\\'") == []);
    assert(keys("n LIKE '%\\%' ESCAPE '\\'") == [7L]);
    assert(keys("n LIKE 'a\\_ple' ESCAPE '\\'") == []);
    assert(keys("n NOT LIKE '%\\%' ESCAPE '\\'") == [1L, 2, 3, 4, 6]);
    assertThrown(keys("n LIKE 'a\\' ESCAPE '\\'"));
    assertThrown(keys("n LIKE 'a' ESCAPE 'xy'"));
    assert(keys("n NOT LIKE 'a%'") == [2L, 3, 7]); // NULL-Zeile (k = 5) ist nie ein Treffer

    // IN
    assert(keys("k IN (1, 3, 99)") == [1L, 3]);
    assert(keys("k NOT IN (1, 2)") == [3L, 4, 5, 6, 7]);
    assert(keys("k NOT IN (1, NULL)").length == 0); // NOT IN mit NULL in der Liste ist nie wahr
    assert(keys("n IN ('apple', 'cherry')") == [1L, 3]);

    // BETWEEN (Grenzen inklusive)
    assert(keys("v BETWEEN 2 AND 5") == [2L, 4, 5]);
    assert(keys("v NOT BETWEEN 2 AND 5") == [1L, 6, 7]); // NULL-Zeile (k = 3) ist nie ein Treffer

    // zusammen mit AND/OR: das AND in BETWEEN gehört zum Operator
    assert(keys("n IN ('apple', 'cherry') AND v BETWEEN 1 AND 3") == [1L]);
    assert(keys("k BETWEEN 2 AND 3 OR n LIKE 'a%'") == [1L, 2, 3, 4, 6]);

    // Fehler
    assertThrown(s.execute("SELECT k FROM p WHERE k LIKE 'a%'")); // LIKE nur für Text
    assertThrown(s.execute("SELECT k FROM p WHERE k IN ()"));
    assertThrown(s.execute("SELECT k FROM p WHERE k IN (1, 2"));
    assertThrown(s.execute("SELECT k FROM p WHERE k BETWEEN 1 3"));

    // auch in UPDATE und DELETE
    assert(s.execute("DELETE FROM p WHERE n LIKE 'a%'").affected == 3);
    assert(s.execute("UPDATE p SET v = 0 WHERE k IN (2, 5)").affected == 2);
    assert(s.execute("SELECT COUNT(*) FROM p").rows[0][0] == Value(4L));
}

private bool lessKeys(Value[] a, Value[] b) {
    foreach (i; 0 .. a.length) {
        immutable c = compareValues(a[i], b[i]);
        if (c != 0)
            return c < 0;
    }
    return false;
}

unittest {
    import std.exception : assertThrown;

    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE s (reg VARCHAR(5), prod VARCHAR(5), q INTEGER)");
    foreach (row; [
            "('n', 'a', 1)", "('n', 'a', 2)", "('n', 'b', 3)", "('s', 'a', 4)",
            "('s', 'b', 5)", "('s', 'b', NULL)", "(NULL, 'a', 7)"
        ])
        s.execute("INSERT INTO s VALUES " ~ row);

    // zwei Gruppierungsspalten; ohne Wert für q zählt die Zeile bei COUNT(*), aber nicht bei SUM
    foreach (round; 0 .. 2) {
        if (round == 1)
            s.mergeDelta(); // gleiches Ergebnis, wenn alles im Main-Store liegt
        auto r = s.execute(
            "SELECT reg, prod, COUNT(*), SUM(q) FROM s GROUP BY reg, prod ORDER BY reg, prod");
        assert(r.rows.length == 5);
        assert(isNull(r.rows[0][0]) && r.rows[0][3] == Value(7.0)); // NULL bildet eine Gruppe und sortiert zuerst
        assert(r.rows[1][2] == Value(2L) && r.rows[1][3] == Value(3.0));
        assert(r.rows[4][2] == Value(2L) && r.rows[4][3] == Value(5.0));
    }

    // Gruppierungsspalte muss nicht ausgewählt werden; HAVING auf Aggregat, Sortierung nach Aggregat
    auto r = s.execute(
        "SELECT prod, SUM(q) FROM s GROUP BY reg, prod HAVING COUNT(*) >= 2 ORDER BY SUM(q) DESC");
    assert(r.rows.length == 2 && r.rows[0][0] == Value("b") && r.rows[1][0] == Value("a"));

    // HAVING auf eine nicht ausgewählte Gruppierungsspalte
    r = s.execute("SELECT reg, COUNT(*) FROM s GROUP BY reg, prod HAVING prod = 'a'");
    assert(r.rows.length == 3 && r.rows[1][1] == Value(2L));

    // eine Gruppierungsspalte wie bisher, ohne ORDER BY nach Schlüssel sortiert
    r = s.execute("SELECT reg, COUNT(*) FROM s GROUP BY reg");
    assert(r.rows.length == 3 && isNull(r.rows[0][0]) && r.rows[2][1] == Value(3L));

    // Spalten, die weder gruppiert noch aggregiert sind, werden abgelehnt
    assertThrown(s.execute("SELECT reg, prod, COUNT(*) FROM s GROUP BY reg"));
    assertThrown(s.execute("SELECT reg FROM s GROUP BY reg, nope"));
}

/// Entfernt doppelte Ergebniszeilen (Sortierung nach allen Spalten, NULL zuerst).
private Value[][] dedupeRows(Value[][] rows) {
    if (rows.length < 2)
        return rows;
    auto sorted = rows.dup;
    sorted.sort!((a, b) => lessKeys(a, b), SwapStrategy.stable);
    Value[][] result = [sorted[0]];
    foreach (r; sorted[1 .. $])
        if (lessKeys(result[$ - 1], r))
            result ~= r;
    return result;
}

unittest {
    import std.exception : assertThrown;

    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE d (g VARCHAR(5), x INTEGER, y DECIMAL)");
    foreach (row; [
            "('a', 1, 1.0)", "('a', 1, 2.0)", "('a', 2, 2.0)", "('b', 2, 3.0)",
            "('b', NULL, 4.0)", "(NULL, 1, 5.0)", "(NULL, 1, 5.0)"
        ])
        s.execute("INSERT INTO d VALUES " ~ row);

    // SELECT DISTINCT
    auto r = s.execute("SELECT DISTINCT g FROM d ORDER BY g");
    assert(r.rows.length == 3 && isNull(r.rows[0][0]) && r.rows[2][0] == Value("b"));
    r = s.execute("SELECT DISTINCT g, x FROM d ORDER BY g, x");
    assert(r.rows.length == 5 && isNull(r.rows[3][1]) && r.rows[4][1] == Value(2L));
    assert(s.execute("SELECT DISTINCT * FROM d").rows.length == 6); // die zwei gleichen Zeilen werden eins
    assert(s.execute("SELECT DISTINCT g FROM d ORDER BY g LIMIT 2").rows.length == 2);
    assert(s.execute("SELECT DISTINCT COUNT(*) FROM d GROUP BY g").rows.length == 2); // Zählungen 2, 3, 2

    // COUNT/SUM/AVG(DISTINCT x)
    assert(s.execute("SELECT COUNT(DISTINCT x) FROM d").rows[0][0] == Value(2L)); // 1, 2; NULL zählt nicht
    r = s.execute("SELECT SUM(DISTINCT y), SUM(y), AVG(DISTINCT y) FROM d");
    assert(r.rows[0][0] == Value(15.0) && r.rows[0][1] == Value(22.0) && r.rows[0][2] == Value(3.0));
    r = s.execute("SELECT g, COUNT(DISTINCT x), COUNT(x), COUNT(*) FROM d GROUP BY g ORDER BY g");
    assert(r.rows.length == 3);
    assert(r.rows[1][1] == Value(2L) && r.rows[1][2] == Value(3L) && r.rows[1][3] == Value(3L)); // a
    assert(r.rows[2][1] == Value(1L) && r.rows[2][2] == Value(1L) && r.rows[2][3] == Value(2L)); // b
    r = s.execute("SELECT g FROM d GROUP BY g HAVING COUNT(DISTINCT x) >= 2");
    assert(r.rows.length == 1 && r.rows[0][0] == Value("a"));

    // gleicher Wert in Main und Delta zählt nur einmal
    s.mergeDelta();
    s.execute("INSERT INTO d VALUES ('c', 1, 1.0)");
    assert(s.execute("SELECT COUNT(DISTINCT x) FROM d").rows[0][0] == Value(2L));
    assert(s.execute("SELECT SUM(DISTINCT y) FROM d").rows[0][0] == Value(15.0));
    assert(s.execute("SELECT DISTINCT x FROM d").rows.length == 3); // NULL, 1, 2

    assertThrown(s.execute("SELECT COUNT(DISTINCT *) FROM d"));
}

private struct MergeTask {
    Column column;
    MergeJob job;
}

private struct CompactionTask {
    ColumnTable table;
    CompactionJob job;
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE m (k INTEGER, v VARCHAR(5))");

    // Ab 1000 Delta-Zeilen startet ein Merge im Hintergrund, während die Einfügungen weiterlaufen.
    foreach (i; 0 .. 1500)
        s.execute("INSERT INTO m VALUES (" ~ i.to!string ~ ", 'x')");
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);

    auto st = s.stats()[0];
    assert(st.rows == 1500);
    assert(st.columns[0].mainRows >= 1000);
    assert(st.columns[0].mainRows + st.columns[0].deltaRows == 1500);
    assert(s.mergeStatus().completed >= 1 && s.mergeStatus().lastError.length == 0);

    // nichts ging verloren oder wurde vertauscht
    assert(s.execute("SELECT COUNT(*) FROM m").rows[0][0] == Value(1500L));
    assert(s.execute("SELECT SUM(k) FROM m").rows[0][0] == Value(1_124_250.0));
    assert(s.execute("SELECT COUNT(*) FROM m WHERE k >= 990 AND k < 1010").rows[0][0] == Value(20L));
    assert(s.execute("SELECT COUNT(DISTINCT k) FROM m").rows[0][0] == Value(1500L));

    // synchroner Merge: gelöschte Zeilen verschwinden, alles liegt danach im Main
    s.execute("DELETE FROM m WHERE k < 100");
    s.execute("UPDATE m SET v = 'y' WHERE k >= 1400");
    s.mergeDelta();
    st = s.stats()[0];
    assert(st.columns[0].deltaRows == 0 && st.rows == 1400 && st.deletedRows == 0);
    assert(s.execute("SELECT COUNT(*) FROM m WHERE v = 'y'").rows[0][0] == Value(100L));

    // asynchroner Aufruf: es läuft nie mehr als ein Merge, und das Ergebnis ist unverändert
    s.execute("INSERT INTO m VALUES (5000, 'z')");
    assert(s.mergeDeltaAsync());
    s.mergeDeltaAsync(); // läuft er noch, ist das ein No-op
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);
    s.mergeDelta();
    assert(s.mergeStatus().lastError.length == 0);
    assert(s.stats()[0].columns[0].deltaRows == 0);
    assert(s.execute("SELECT COUNT(*) FROM m").rows[0][0] == Value(1401L));
}

unittest {
    static class FakeRepo : ITableRepository {
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

    auto s = new SqlService(new FakeRepo);
    s.execute("CREATE TABLE c (k INTEGER, v VARCHAR(5))");
    foreach (i; 0 .. 2500)
        s.execute("INSERT INTO c VALUES (" ~ i.to!string ~ ", 'x')");
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);

    // 1500 von 2500 Zeilen löschen: über 1000 und mehr als die Hälfte, also kompaktiert der Hintergrund-Thread
    assert(s.execute("DELETE FROM c WHERE k < 1500").affected == 1500);
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);
    auto st = s.stats()[0];
    assert(st.rows == 1000 && st.deletedRows == 0);
    assert(s.execute("SELECT MIN(k), MAX(k) FROM c").rows[0][0] == Value(1500L));
    assert(s.execute("SELECT SUM(k) FROM c").rows[0][0] == Value(1_999_500.0));

    // Wird während einer Kompaktierung weitergeschrieben, ist das Ergebnis unabhängig vom Timing dasselbe:
    // Einfügungen, Löschungen alter und neuer Zeilen und Änderungen müssen alle erhalten bleiben.
    foreach (i; 0 .. 1500)
        s.execute("INSERT INTO c VALUES (" ~ (10_000 + i).to!string ~ ", 'n')");
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);
    // 2000 von 2500 Zeilen löschen (alle alten und k = 10000..10999): das löst die Kompaktierung aus
    assert(s.execute("DELETE FROM c WHERE k < 11000").affected == 2000);
    foreach (i; 0 .. 200)
        s.execute("INSERT INTO c VALUES (" ~ (20_000 + i).to!string ~ ", 'w')");
    s.execute("DELETE FROM c WHERE k >= 20000 AND k < 20050");
    s.execute("UPDATE c SET v = 'u' WHERE k >= 11000 AND k < 11100");
    while (s.mergeStatus().running)
        Thread.sleep(1.msecs);

    // lebend: k = 11000..11499 (500) und k = 20050..20199 (150) = 650
    assert(s.execute("SELECT COUNT(*) FROM c").rows[0][0] == Value(650L));
    assert(s.execute("SELECT COUNT(*) FROM c WHERE v = 'u'").rows[0][0] == Value(100L));
    assert(s.execute("SELECT COUNT(*) FROM c WHERE k < 11000").rows[0][0] == Value(0L));
    assert(s.execute("SELECT COUNT(*) FROM c WHERE k >= 20000 AND k < 20050")
            .rows[0][0] == Value(0L));
    // 11000..11499: 500 * 11000 + 124_750 = 5_624_750; 20050..20199: 150 * 20000 + 18_675 = 3_018_675
    assert(s.execute("SELECT SUM(k) FROM c").rows[0][0] == Value(8_643_425.0));

    // zum Schluss bereinigt der synchrone Merge alles
    s.mergeDelta();
    st = s.stats()[0];
    assert(st.rows == 650 && st.deletedRows == 0 && st.columns[0].deltaRows == 0);
    assert(s.execute("SELECT SUM(k) FROM c").rows[0][0] == Value(8_643_425.0));
    assert(s.mergeStatus().lastError.length == 0);
}

unittest {
    static class FakeRepo : ITableRepository {
        ColumnTable[string] m;
        bool exists(string n) {
            return (n in m) !is null;
        }

        ColumnTable get(string n) {
            enforce(n in m, "Tabelle nicht gefunden: " ~ n); // wie MemoryTableRepository
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

    static class MemLog : IStatementLog {
        string[] lines;
        void append(string st) {
            lines ~= st;
        }

        void appendAll(string[] a) {
            lines ~= a;
        }

        string[] readAll() {
            return lines.dup;
        }

        void replaceAll(string[] a) {
            lines = a.dup;
        }
    }

    import std.exception : assertThrown;

    auto log = new MemLog;
    auto s = new SqlService(new FakeRepo, log);
    s.execute("CREATE TABLE d (k INTEGER, w DECIMAL)");
    s.execute("INSERT INTO d VALUES (1, 1234567.891)");
    assert(s.stats()[0].columns[1].type == ColumnType.decimal);

    // Checkpoint und Wiederanlauf erhalten double exakt
    s.checkpoint();
    auto restored = new SqlService(new FakeRepo, log);
    restored.recover();
    assert(restored.execute("SELECT w FROM d").rows[0][0] == Value(1234567.891));

    // DROP in einer Transaktion: Rollback stellt die Tabelle samt Daten wieder her
    auto tx = s.execute("BEGIN").transaction;
    s.executeIn(tx, "DROP TABLE d");
    assertThrown(s.executeIn(tx, "SELECT k FROM d"));
    s.executeIn(tx, "ROLLBACK");
    assert(s.execute("SELECT k FROM d").rows.length == 1);

    // DROP wird geloggt und beim Einspielen wiederholt; die Tabelle lässt sich neu anlegen
    s.execute("DROP TABLE d");
    assertThrown(s.execute("DROP TABLE d"));
    auto replayed = new SqlService(new FakeRepo, log);
    replayed.recover();
    assert(replayed.listTables().length == 0);
    replayed.execute("CREATE TABLE d (x VARCHAR)");
    assertThrown(s.execute("DROP d"));

    // Schlüsselwörter in Textliteralen sind keine Klauseln
    s.execute("CREATE TABLE q (k INTEGER, n VARCHAR)");
    s.execute("INSERT INTO q VALUES (1, 'x WHERE y = 1')");
    s.execute("INSERT INTO q VALUES (2, 'a ORDER BY b LIMIT 1')");
    assert(s.execute("UPDATE q SET n = 'z WHERE k = 2 GROUP BY' WHERE k = 1").affected == 1);
    assert(s.execute("SELECT k FROM q WHERE n = 'z WHERE k = 2 GROUP BY'").rows[0][0] == Value(1L));
    assert(s.execute("SELECT k FROM q WHERE n = 'a ORDER BY b LIMIT 1' ORDER BY k DESC LIMIT 1").rows[0][0] == Value(2L));
    assert(s.execute("SELECT k FROM q WHERE n = 'it''s FROM x'").rows.length == 0);

    // NaN würde beim Merge auch andere Zeilen verfälschen
    s.execute("CREATE TABLE f (k INTEGER, w DECIMAL)");
    s.execute("INSERT INTO f VALUES (1, 5)");
    assertThrown(s.execute("INSERT INTO f VALUES (2, nan)"));
    assertThrown(s.execute("INSERT INTO f VALUES (2, inf)"));
    assertThrown(s.execute("UPDATE f SET w = nan WHERE k = 1"));
    s.execute("INSERT INTO f VALUES (3, 7)");
    s.mergeDelta();
    auto w = s.execute("SELECT k, w FROM f ORDER BY k").rows;
    assert(w.length == 2 && w[0][1] == Value(5.0) && w[1][1] == Value(7.0));
}

unittest {
    import std.exception : assertThrown;

    auto s = new SqlService(new MemoryTableRepository);
    s.execute("CREATE TABLE m (id INTEGER, b BLOB, g GEO, l LINK)");
    s.execute("INSERT INTO m VALUES (1, X'00ff', 'point(13.4  52.5)', 'https://example.org/a?x=1,2')");
    s.execute("INSERT INTO m VALUES (2, 'AB', 'LINESTRING(0 0, 1 1)', 'mailto:a@example.org')");
    s.execute("INSERT INTO m VALUES (3, NULL, NULL, NULL)");

    auto r = s.execute("SELECT b, g, l FROM m WHERE id = 1").rows;
    assert(r[0][0] == Value("00FF") && r[0][1] == Value("POINT(13.4 52.5)"));
    assert(r[0][2] == Value("https://example.org/a?x=1,2"));

    // Vergleiche laufen über die kanonische Form, auch nach dem Merge ins Dictionary
    foreach (round; 0 .. 2) {
        assert(s.execute("SELECT id FROM m WHERE b = x'00FF'").rows == [[Value(1L)]]);
        assert(s.execute("SELECT id FROM m WHERE b IN (X'ab', X'CD')").rows == [[Value(2L)]]);
        assert(s.execute("SELECT id FROM m WHERE g = 'POINT( 13.4 52.5 )'").rows == [[Value(1L)]]);
        assert(s.execute("SELECT id FROM m WHERE g LIKE 'LINE%'").rows == [[Value(2L)]]);
        assert(s.execute("SELECT id FROM m WHERE l LIKE '%example.org/%'").rows == [[Value(1L)]]);
        assert(s.execute("SELECT id FROM m WHERE l IS NULL").rows == [[Value(3L)]]);
        s.mergeDelta();
    }

    s.execute("UPDATE m SET b = X'11', g = 'POINT(1 2)', l = 'http://h/?a=b' WHERE b = X'AB'");
    assert(s.execute("SELECT b, g, l FROM m WHERE id = 2").rows
            == [[Value("11"), Value("POINT(1 2)"), Value("http://h/?a=b")]]);
    assert(s.execute("SELECT MIN(b), COUNT(g) FROM m").rows[0][0] == Value("00FF"));

    assertThrown(s.execute("INSERT INTO m VALUES (4, X'0', NULL, NULL)"));
    assertThrown(s.execute("INSERT INTO m VALUES (4, NULL, 'CIRCLE(1 2)', NULL)"));
    assertThrown(s.execute("INSERT INTO m VALUES (4, NULL, NULL, 'javascript:alert(1)')"));
    assertThrown(s.execute("UPDATE m SET l = 'data:text/html,x' WHERE id = 1"));
    assertThrown(s.execute("SELECT SUM(b) FROM m"));
    assertThrown(s.execute("SELECT AVG(g) FROM m"));

    s.execute("CREATE TABLE a1 (g ST_GEOMETRY, l URL, n Edm.Int16)");
    foreach (table; s.stats())
        if (table.table == "a1") {
            assert(table.columns[0].type == ColumnType.geo && table.columns[1].type == ColumnType.link);
            assert(table.columns[2].type == ColumnType.int16);
        }
}

unittest {
    import std.exception : assertThrown;

    auto s = new SqlService(new MemoryTableRepository);
    s.execute("CREATE TABLE e (k TINYINT, f BOOLEAN, x NUMERIC, r REAL, d DATE, ts TIMESTAMP, tm TIME, du DURATION, u GUID)");
    s.execute("INSERT INTO e VALUES (1, TRUE, 10.5, 0.1, '2026-11-06', '2026-11-06T12:00:00Z', '08:00', 'PT36H', '01234567-89ab-cdef-0123-456789abcdef')");
    s.execute("INSERT INTO e VALUES (2, FALSE, 9.25, 0.2, '2026-11-07', '2026-11-06T12:00:00.5+01:00', '09:30', 'PT2H', 'ffffffff-89ab-cdef-0123-456789abcdef')");
    s.execute("INSERT INTO e VALUES (3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)");

    long[] ids(string where) {
        long[] r;
        foreach (row; s.execute("SELECT k FROM e WHERE " ~ where ~ " ORDER BY k").rows)
            r ~= row[0].get!long;
        return r;
    }

    string[] order(string column) {
        string[] r;
        foreach (row; s.execute("SELECT " ~ column ~ " FROM e WHERE k < 3 ORDER BY " ~ column).rows)
            r ~= valueText(row[0]);
        return r;
    }

    foreach (round; 0 .. 2) { // Delta, danach das sortierte Dictionary nach dem Merge
        assert(ids("f = TRUE") == [1] && ids("f = false") == [2] && ids("f IS NULL") == [3]);
        assert(ids("x > 9.3") == [1] && ids("x = 10.50") == [1] && ids("x BETWEEN 9 AND 10") == [2]);
        assert(ids("d >= '2026-11-07'") == [2]);
        assert(ids("ts < '2026-11-06T12:00:00Z'") == [2]); // 12:00:00.5+01:00 liegt früher
        assert(ids("du > 'PT3H'") == [1] && ids("du = 'P1DT12H'") == [1]);
        assert(ids("u = '01234567-89AB-CDEF-0123-456789ABCDEF'") == [1]);
        assert(ids("d LIKE '2026-11-0%'") == [1, 2]);
        assert(order("x") == ["9.25", "10.5"]); // als Text stünde 10.5 vorn
        assert(order("du") == ["PT2H", "P1DT12H"]); // als Text ebenfalls verkehrt
        s.mergeDelta();
    }

    auto sums = s.execute("SELECT SUM(x), AVG(r), MIN(x), MAX(du), MIN(d), COUNT(f) FROM e").rows[0];
    assert(sums[0] == Value(19.75) && valueText(sums[2]) == "9.25" && valueText(sums[3]) == "P1DT12H");
    assert(sums[4] == Value("2026-11-06") && sums[5] == Value(2L));
    assert(s.execute("SELECT f, COUNT(*) FROM e GROUP BY f").rows.length == 3);
    assert(s.execute("SELECT DISTINCT x FROM e WHERE k < 3").rows.length == 2);

    s.execute("UPDATE e SET f = false, x = 1e2, du = 'P2D' WHERE k = 1");
    assert(ids("x = 100") == [1] && ids("f = false") == [1, 2] && ids("du = 'PT48H'") == [1]);

    assertThrown(s.execute("INSERT INTO e VALUES (256, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)"));
    assertThrown(s.execute("INSERT INTO e VALUES (4, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL)"));
    assertThrown(s.execute("INSERT INTO e VALUES (4, NULL, NULL, NULL, '2026-02-30', NULL, NULL, NULL, NULL)"));
    assertThrown(s.execute("SELECT SUM(du) FROM e"));
    assertThrown(s.execute("SELECT SUM(f) FROM e"));
    assertThrown(s.execute("SELECT SUM(d) FROM e"));
    assertThrown(s.execute("SELECT k FROM e WHERE du LIKE 'P%'"));
    assertThrown(s.execute("SELECT k FROM e WHERE x LIKE '1%'"));
    assertThrown(s.execute("CREATE TABLE z (a RAW)"));
}
