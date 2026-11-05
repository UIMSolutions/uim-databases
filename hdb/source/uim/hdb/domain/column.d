module uim.hdb.domain.column;

import uim.hdb.domain.packed_vector;
import uim.hdb.domain.value;
import std.algorithm : sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;

/// Dictionary-komprimierte Spalte (wie HANA):
///  - Main:  sortiertes Dictionary + bitgepackte Codes (read-optimiert)
///  - Delta: unsortiertes Dictionary + uint-Codes (write-optimiert)
/// Der Delta-Merge läuft in drei Phasen, damit die teure Mitte ohne Sperre laufen kann:
///   1. beginMerge()   (unter Sperre) friert das Delta ein und gibt einen MergeJob mit den eingefrorenen Daten zurück,
///   2. MergeJob.run() (ohne Sperre)  baut sortiertes Dictionary und neue Codes, greift nur auf den Job zu,
///   3. finishMerge()  (unter Sperre) schaltet auf das neue Main um; Zeilen, die inzwischen ins Delta kamen, bleiben dort.
/// merge() führt alle drei Phasen am Stück aus.
final class Column {
    private Value[] mainDict;
    private PackedVector mainCodes;
    private Value[] deltaDict;
    private uint[] deltaCodes;
    private uint[Value] deltaIndex;
    private bool merging; // ein Merge ist eingefroren und läuft gerade

    size_t length() const {
        return mainCodes.length + deltaCodes.length;
    }

    size_t mainRows() const {
        return mainCodes.length;
    }

    size_t deltaRows() const {
        return deltaCodes.length;
    }

    size_t mainDistinct() const {
        return mainDict.length;
    }

    size_t deltaDistinct() const {
        return deltaDict.length;
    }

    uint mainBits() const {
        return mainCodes.bitsPerValue;
    }

    size_t mainCodeBytes() const {
        return mainCodes.bytes;
    }

    /// Schlüsselraum für Gruppierung: Main-Codes, danach Delta-Codes (um mainDict.length verschoben).
    size_t keySpace() const {
        return mainDict.length + deltaDict.length;
    }

    size_t keyAt(size_t row) const {
        return row < mainCodes.length
            ? mainCodes[row] : mainDict.length + deltaCodes[row - mainCodes.length];
    }

    Value keyValue(size_t key) {
        return key < mainDict.length ? mainDict[key] : deltaDict[key - mainDict.length];
    }

    Value get(size_t row) {
        return keyValue(keyAt(row));
    }

    /// Tiefe Kopie (für Rollback-Snapshots).
    Column clone() {
        auto c = new Column;
        c.mainDict = mainDict.dup;
        c.mainCodes = mainCodes; // nach pack() nie verändert, daher darf das Array geteilt werden
        c.deltaDict = deltaDict.dup;
        c.deltaCodes = deltaCodes.dup;
        c.deltaIndex = deltaIndex.dup;
        return c;
    }

    void append(Value v) {
        if (auto p = v in deltaIndex) {
            deltaCodes ~= *p;
            return;
        }
        auto code = cast(uint)deltaDict.length;
        deltaDict ~= v;
        deltaIndex[v] = code;
        deltaCodes ~= code;
    }

    /// Das Prädikat wird nur einmal pro DISTINCT-Wert ausgewertet, danach werden nur Codes gescannt.
    size_t[] scan(scope bool delegate(Value) pred) {
        auto mainOk = new bool[mainDict.length];
        foreach (i, v; mainDict)
            mainOk[i] = pred(v);
        auto deltaOk = new bool[deltaDict.length];
        foreach (i, v; deltaDict)
            deltaOk[i] = pred(v);

        size_t[] hits;
        foreach (i; 0 .. mainCodes.length)
            if (mainOk[mainCodes[i]])
                hits ~= i;
        foreach (i, c; deltaCodes)
            if (deltaOk[c])
                hits ~= mainCodes.length + i;
        return hits;
    }

    /// Spalte, die nur aus einem fertigen Main besteht (leeres Delta); Ergebnis der Kompaktierung.
    static Column fromMain(Value[] dict, PackedVector codes) {
        auto c = new Column;
        c.mainDict = dict;
        c.mainCodes = codes;
        return c;
    }

    /// Lesbare Momentaufnahme (Main + aktuelles Delta) für Arbeit ohne Sperre. Das Main wird nie verändert,
    /// nur ersetzt, und Delta-Einträge ändern sich nie; neue Zeilen werden nur hinten angehängt.
    ColumnView view() {
        ColumnView v;
        v.mainDict = mainDict;
        v.mainCodes = mainCodes;
        v.deltaDict = deltaDict[0 .. $];
        v.deltaCodes = deltaCodes[0 .. $];
        return v;
    }

    bool isMerging() const {
        return merging;
    }

    /// Phase 1 (unter Sperre): friert das Delta ein. null, wenn es nichts zu mergen gibt oder schon ein Merge läuft.
    /// Das Main wird nie verändert, sondern nur ersetzt, und eingefrorene Delta-Einträge bleiben unverändert;
    /// beides darf der Job daher ohne Sperre lesen, während neue Zeilen ans Delta angehängt werden.
    MergeJob beginMerge() {
        if (merging || deltaCodes.length == 0)
            return null;
        merging = true;
        auto job = new MergeJob;
        job.mainDict = mainDict;
        job.mainCodes = mainCodes;
        job.frozenDict = deltaDict[0 .. $];
        job.frozenCodes = deltaCodes[0 .. $];
        return job;
    }

    /// Phase 3 (unter Sperre): neues Main übernehmen. Zeilen nach dem Einfrieren bekommen ein neues, kleines Delta.
    /// Zeilennummern ändern sich nicht: die eingefrorenen Zeilen stehen schon direkt hinter dem Main.
    void finishMerge(MergeJob job) {
        if (job.released)
            return;
        if (!job.done || !merging || mainCodes.length != job.mainCodes.length) {
            abortMerge(job);
            throw new Exception("Merge-Zustand passt nicht mehr zur Spalte");
        }
        mainDict = job.newDict;
        mainCodes = job.newCodes;

        auto oldDict = deltaDict;
        auto oldCodes = deltaCodes;
        deltaDict = null;
        deltaCodes = null;
        deltaIndex = null;
        foreach (i; job.frozenCodes.length .. oldCodes.length)
            append(oldDict[oldCodes[i]]);

        merging = false;
        job.released = true;
    }

    /// Bricht einen Merge ab und gibt die Spalte wieder frei (wirkungslos, wenn der Job schon beendet ist).
    void abortMerge(MergeJob job) {
        if (job.released)
            return;
        job.released = true;
        merging = false;
    }

    /// Delta-Merge am Stück (alle drei Phasen); tut nichts, wenn schon ein Merge dieser Spalte läuft.
    void merge() {
        auto job = beginMerge();
        if (job is null)
            return;
        try
            job.run();
        catch (Throwable e) {
            abortMerge(job);
            throw e;
        }
        finishMerge(job);
    }
}

/// Momentaufnahme einer Spalte: erlaubt Lesen einzelner Werte, ohne die Spalte selbst anzufassen.
struct ColumnView {
    private Value[] mainDict;
    private PackedVector mainCodes;
    private Value[] deltaDict;
    private uint[] deltaCodes;

    size_t length() const {
        return mainCodes.length + deltaCodes.length;
    }

    Value get(size_t row) {
        return row < mainCodes.length
            ? mainDict[mainCodes[row]] : deltaDict[deltaCodes[row - mainCodes.length]];
    }
}

/// Eingefrorener Teil einer Spalte für Phase 2 des Merges: enthält nur lesbare Daten und das Ergebnis.
final class MergeJob {
    private Value[] mainDict;
    private PackedVector mainCodes;
    private Value[] frozenDict;
    private uint[] frozenCodes;
    private Value[] newDict;
    private PackedVector newCodes;
    private bool done;
    private bool released;

    /// Gemeinsames sortiertes Dictionary, alle Codes werden umgeschrieben und neu gepackt.
    void run() {
        auto all = (mainDict ~ frozenDict).dup
            .sort!valueLess
            .uniq!((a, b) => compareValues(a, b) == 0)
            .array;
        auto sorted = all.assumeSorted!valueLess;
        uint codeOf(Value v) {
            return cast(uint)sorted.lowerBound(v).length;
        }

        auto mainMap = new uint[mainDict.length];
        foreach (i, v; mainDict)
            mainMap[i] = codeOf(v);
        auto deltaMap = new uint[frozenDict.length];
        foreach (i, v; frozenDict)
            deltaMap[i] = codeOf(v);

        auto codes = new uint[mainCodes.length + frozenCodes.length];
        foreach (i; 0 .. mainCodes.length)
            codes[i] = mainMap[mainCodes[i]];
        foreach (i, c; frozenCodes)
            codes[mainCodes.length + i] = deltaMap[c];

        newDict = all;
        newCodes = PackedVector.pack(codes, all.length);
        done = true;
    }
}

unittest {
    auto c = new Column;
    foreach (s; ["b", "a", "b", "c"])
        c.append(Value(s));
    assert(c.deltaDistinct == 3 && c.deltaRows == 4);
    c.merge();
    assert(c.deltaRows == 0 && c.mainDistinct == 3 && c.mainBits == 2);
    assert(c.get(0) == Value("b") && c.get(1) == Value("a"));
    c.append(Value("a"));
    c.merge();
    assert(c.mainDistinct == 3 && c.length == 5 && c.get(4) == Value("a"));
    assert(c.scan((Value v) => v == Value("b")) == [cast(size_t)0, 2]);
}

unittest {
    // Merge in drei Phasen: das eingefrorene Delta wird gemergt, später Eingefügtes bleibt im Delta
    auto c = new Column;
    foreach (x; ["c", "a", "b"])
        c.append(Value(x));
    auto job = c.beginMerge();
    assert(job !is null && c.isMerging);
    assert(c.beginMerge() is null); // pro Spalte höchstens ein Merge
    c.append(Value("b")); // kommt während des Merges dazu
    c.append(Value("d"));
    job.run(); // arbeitet nur auf dem Job, nicht auf der Spalte
    assert(c.length == 5 && c.mainRows == 0); // bis zum Umschalten ändert sich nichts
    c.finishMerge(job);
    assert(!c.isMerging && c.mainRows == 3 && c.deltaRows == 2 && c.length == 5);
    assert(c.mainDistinct == 3 && c.deltaDistinct == 2);
    assert(c.get(0) == Value("c") && c.get(1) == Value("a") && c.get(2) == Value("b"));
    assert(c.get(3) == Value("b") && c.get(4) == Value("d"));
    c.merge();
    assert(c.deltaRows == 0 && c.mainDistinct == 4 && c.get(4) == Value("d"));

    // Abbruch gibt die Spalte wieder frei, ein zweiter Abbruch ist wirkungslos
    c.append(Value("e"));
    auto job2 = c.beginMerge();
    c.abortMerge(job2);
    assert(!c.isMerging && c.deltaRows == 1);
    auto job3 = c.beginMerge();
    c.abortMerge(job2);
    assert(c.isMerging); // job2 darf den neuen Merge nicht freigeben
    c.abortMerge(job3);
}
