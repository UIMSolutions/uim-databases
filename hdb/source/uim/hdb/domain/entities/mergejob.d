module uim.hdb.domain.entities.mergejob;

import uim.hdb;
import uim.hdb.domain.value;
import std.algorithm : sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;

/// Eingefrorener Teil einer Spalte für Phase 2 des Merges: enthält nur lesbare Daten und das Ergebnis.
final class MergeJob {
    /* private */  Value[] mainDict;
    /* private */  PackedVector mainCodes;
    /* private */  Value[] frozenDict;
    /* private */  uint[] frozenCodes;
    /* private */  Value[] newDict;
    /* private */  PackedVector newCodes;
    /* private */  bool done;
    /* private */  bool released;

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
