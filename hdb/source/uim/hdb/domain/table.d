module uim.hdb.domain.table;

import uim.hdb;
import std.algorithm : sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;
import std.string : icmp, lastIndexOf;



/// Spaltenorientierte Tabelle mit Main/Delta-Spalten.
final class ColumnTable {
    enum mergeThreshold = 1000; // ab so vielen Delta-Zeilen einer Spalte lohnt sich ein Merge

    string name;
    ColumnDef[] defs;
    Column[] columns;
    TableStorage storage;
    private bool[] deleted; // Löschvektor: eine Zeile je physischer Zeile
    private size_t deletedCount;
    private bool compacting; // eine Kompaktierung ist eingefroren und läuft gerade
    private size_t[] compactLog; // seit dem Einfrieren gelöschte Zeilen (alte Zeilennummern)

    this(string name, ColumnDef[] defs, TableStorage storage = TableStorage.memory) {
        this.name = name;
        this.defs = defs;
        this.storage = storage;
        this.columns = new Column[defs.length];
        foreach (ref c; columns)
            c = new Column;
    }

    /// Tiefe Kopie inklusive Löschvektor (für Rollback-Snapshots).
    ColumnTable clone() {
        auto t = new ColumnTable(name, defs.dup, storage);
        foreach (i, c; columns)
            t.columns[i] = c.clone();
        t.deleted = deleted.dup;
        t.deletedCount = deletedCount;
        return t;
    }

    size_t rowCount() const {
        return columns.length ? columns[0].length : 0;
    }

    /// Exakter Name, sonst (Join-Ergebnis) eindeutiges Suffix ".name" für unqualifizierte Angaben.
    size_t indexOf(string column) const {
        foreach (i, d; defs)
            if (icmp(d.name, column) == 0)
                return i;
        size_t found = size_t.max;
        foreach (i, d; defs) {
            auto dot = d.name.lastIndexOf('.');
            if (dot >= 0 && icmp(d.name[dot + 1 .. $], column) == 0) {
                enforce(found == size_t.max, "Spalte ist mehrdeutig: " ~ column);
                found = i;
            }
        }
        if (found != size_t.max)
            return found;
        throw new Exception("Spalte nicht gefunden: " ~ column);
    }

    Value value(size_t col, size_t row) {
        return columns[col].get(row);
    }

    void insert(Value[] row) {
        enforce(row.length == defs.length, "Spaltenanzahl passt nicht");
        foreach (i, v; row)
            columns[i].append(v);
        deleted ~= false;
    }

    /// Hat eine Spalte so viel Delta, dass sich ein Merge lohnt (und läuft dort nicht schon einer)?
    bool needsMerge() {
        if (compacting)
            return false;
        foreach (c; columns)
            if (!c.isMerging && c.deltaRows >= mergeThreshold)
                return true;
        return false;
    }

    /// Läuft gerade ein Merge einer Spalte? Dann dürfen die Spalten nicht ersetzt werden (Kompaktierung).
    bool anyMerging() {
        foreach (c; columns)
            if (c.isMerging)
                return true;
        return false;
    }

    size_t liveCount() const {
        return rowCount - deletedCount;
    }

    void markDeleted(size_t row) {
        if (!deleted[row]) {
            deleted[row] = true;
            ++deletedCount;
            if (compacting)
                compactLog ~= row; // wird beim Umschalten auf die neuen Zeilennummern übertragen
        }
    }

    /// Zeilennummern aller nicht gelöschten Zeilen.
    size_t[] liveRows() const {
        size_t[] result;
        foreach (i, d; deleted)
            if (!d)
                result ~= i;
        return result;
    }

    size_t[] filterLive(size_t[] rows) const {
        if (deletedCount == 0)
            return rows;
        size_t[] result;
        foreach (r; rows)
            if (!deleted[r])
                result ~= r;
        return result;
    }

    /// Entfernt gelöschte Zeilen physisch und baut die Spalten (mit sortiertem Dictionary) neu auf.
    void compact() {
        if (deletedCount == 0 || anyMerging || compacting)
            return;
        immutable live = liveCount;
        auto fresh = new Column[defs.length];
        foreach (ref c; fresh)
            c = new Column;
        foreach (r; liveRows())
            foreach (ci, c; fresh)
                c.append(columns[ci].get(r));
        foreach (c; fresh)
            c.merge();
        columns = fresh;
        deleted = new bool[live];
        deletedCount = 0;
    }

    bool isCompacting() const {
        return compacting;
    }

    /// Lohnt sich eine Kompaktierung? (mindestens 1000 gelöschte Zeilen und mehr als die Hälfte der Tabelle)
    bool needsCompaction() const {
        return !compacting && deletedCount >= 1000 && deletedCount * 2 > rowCount;
    }

    /// Kompaktierung in drei Phasen, damit der teure Aufbau ohne Sperre laufen kann (siehe CompactionJob):
    /// Phase 1 (unter Sperre): friert Zeilenzahl, lebende Zeilen und Spaltenstände ein. null, wenn nichts zu tun ist,
    /// schon eine Kompaktierung läuft oder gerade eine Spalte gemergt wird.
    CompactionJob beginCompaction() {
        if (compacting || deletedCount == 0 || anyMerging)
            return null;
        auto job = new CompactionJob;
        job.liveIds = liveRows();
        job.frozenRows = rowCount;
        job.views = columns.map!(c => c.view()).array;
        compacting = true;
        compactLog = null;
        return job;
    }

    /// Phase 3 (unter Sperre): schaltet auf die neuen Spalten um und überträgt, was seit dem Einfrieren geschah:
    ///  - neue Zeilen (alte Nummern ab frozenRows) kommen ins Delta und stehen direkt hinter den lebenden Zeilen,
    ///  - Löschungen aus dem Protokoll werden auf die neuen Zeilennummern abgebildet (Rang unter den lebenden Zeilen).
    void finishCompaction(CompactionJob job) {
        if (job.released)
            return;
        immutable end = rowCount;
        if (!job.done || !compacting || end < job.frozenRows) {
            abortCompaction(job);
            throw new Exception("Kompaktierungs-Zustand passt nicht mehr zur Tabelle");
        }
        immutable n = job.frozenRows;
        immutable live = job.liveIds.length;
        auto fresh = job.newColumns;
        foreach (r; n .. end)
            foreach (ci, c; fresh)
                c.append(columns[ci].get(r));

        auto newDeleted = new bool[live + (end - n)];
        size_t newCount;
        auto ids = job.liveIds.assumeSorted;
        foreach (d; compactLog) {
            immutable idx = d < n ? ids.lowerBound(d).length : live + (d - n);
            if (!newDeleted[idx]) {
                newDeleted[idx] = true;
                ++newCount;
            }
        }
        columns = fresh;
        deleted = newDeleted;
        deletedCount = newCount;
        compacting = false;
        compactLog = null;
        job.released = true;
    }

    /// Bricht eine Kompaktierung ab (wirkungslos, wenn der Job schon beendet ist).
    void abortCompaction(CompactionJob job) {
        if (job.released)
            return;
        job.released = true;
        compacting = false;
        compactLog = null;
    }

    /// Delta-Merge am Stück (synchron); gelöschte Zeilen werden dabei entfernt (wie in HANA).
    void mergeDelta() {
        compact();
        foreach (c; columns)
            c.merge();
    }

    TableStats stats() {
        TableStats s;
        s.table = name;
        s.rows = liveCount;
        s.deletedRows = deletedCount;
        s.storage = storage;
        foreach (i, d; defs) {
            auto c = columns[i];
            s.columns ~= ColumnStats(d.name, c.length, c.mainRows, c.deltaRows,
                c.mainDistinct, c.deltaDistinct,
                c.mainBits, c.mainCodeBytes, d.type);
        }
        return s;
    }
}

