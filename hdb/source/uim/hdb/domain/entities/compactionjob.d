module uim.hdb.domain.entities.compactionjob;

import uim.hdb;

/// Phase 2 der Kompaktierung: baut die Spalten nur aus den lebenden Zeilen neu auf. Arbeitet ausschließlich auf den
/// eingefrorenen Momentaufnahmen und braucht keine Sperre.
final class CompactionJob {
    protected ColumnView[] _views;
    @property ColumnView[] views() {
        return _views;
    }

    @property CompactionJob views(ColumnView[] newViews) {
        _views = newViews;
        return this;
    }

    protected size_t[] _liveIds; // aufsteigend: alte Zeilennummern der lebenden Zeilen
    @property size_t[] liveIds() {
        return _liveIds;
    }

    @property CompactionJob liveIds(size_t[] ids) {
        _liveIds = ids;
        return this;
    }

    protected size_t _frozenRows; // Zeilenzahl beim Einfrieren
    @property size_t frozenRows() {
        return _frozenRows;
    }

    @property CompactionJob frozenRows(size_t rows) {
        _frozenRows = rows;
        return this;
    }

    protected Column[] _newColumns;
    @property Column[] newColumns() {
        return _newColumns;
    }

    @property CompactionJob newColumns(Column[] columns) {
        _newColumns = columns;
        return this;
    }

    protected bool _done;
    @property bool done() {
        return _done;
    }
    @property CompactionJob done(bool mode) {
        _done = mode;
        return this;
    }

    protected bool _released;
    @property bool released() {
        return _released;
    }

    @property CompactionJob released(bool mode) {
        _released = mode;
        return this;
    }

    void run() {
        auto result = new Column[views.length];
        foreach (ci, v; views) {
            Value[] vals;
            vals.reserve(liveIds.length);
            foreach (r; liveIds)
                vals ~= v.get(r);
            auto dict = vals.dup
                .sort!valueLess
                .uniq!((a, b) => compareValues(a, b) == 0)
                .array;
            auto sorted = dict.assumeSorted!valueLess;
            auto codes = new uint[vals.length];
            foreach (i, x; vals)
                codes[i] = cast(uint)sorted.lowerBound(x).length;
            result[ci] = Column.fromMain(dict, PackedVector.pack(codes, dict.length));
        }
        newColumns = result;
        done = true;
    }
}
///
unittest {
    // Kompaktierung in drei Phasen mit Änderungen während des Aufbaus
    auto t = new ColumnTable("t", [
            ColumnDef("k", ColumnType.integer), ColumnDef("v", ColumnType.text)
        ]);
    foreach (i; 0 .. 6)
        t.insert([Value(cast(long)i), Value("x")]);
    t.markDeleted(1);
    t.markDeleted(4); // lebend: 0, 2, 3, 5

    auto job = t.beginCompaction();
    assert(job !is null && t.isCompacting && t.beginCompaction() is null);

    t.insert([Value(6L), Value("x")]); // alte Zeilennummer 6
    t.insert([Value(7L), Value("y")]); // alte Zeilennummer 7
    t.markDeleted(2); // alte Zeile, war beim Einfrieren lebend
    t.markDeleted(7); // neue Zeile
    job.run();
    assert(t.rowCount == 8); // bis zum Umschalten ändert sich nichts

    t.finishCompaction(job);
    assert(!t.isCompacting && t.rowCount == 6 && t.liveCount == 4);
    assert(t.liveRows() == [cast(size_t)0, 2, 3, 4]);
    assert(t.value(0, 0) == Value(0L) && t.value(0, 2) == Value(3L));
    assert(t.value(0, 3) == Value(5L) && t.value(0, 4) == Value(6L));
    assert(t.columns[0].mainRows == 4 && t.columns[0].deltaRows == 2);

    // Abbruch gibt die Tabelle frei; ein zweiter Abbruch mit demselben Job ist wirkungslos
    t.markDeleted(0);
    auto job2 = t.beginCompaction();
    t.markDeleted(2);
    t.abortCompaction(job2);
    assert(!t.isCompacting && t.liveCount == 2);
    auto job3 = t.beginCompaction();
    t.abortCompaction(job2);
    assert(t.isCompacting);
    t.abortCompaction(job3);

    // eine laufende Kompaktierung verhindert Spalten-Merges und die synchrone Kompaktierung
    auto job4 = t.beginCompaction();
    assert(!t.needsMerge() && !t.needsCompaction());
    t.compact();
    assert(t.isCompacting && t.rowCount == 6);
    t.abortCompaction(job4);
}
