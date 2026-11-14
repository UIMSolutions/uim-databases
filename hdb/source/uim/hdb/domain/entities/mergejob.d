/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.hdb.domain.entities.mergejob;

import uim.hdb;
import std.algorithm : sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;

@safe:

/// Frozen portion of a column for Phase 2 of the merge: contains only read-only data and the result.
final class MergeJob {
    protected Value[] _mainDict;
    @property Value[] mainDict() { return _mainDict; }
    @property MergeJob mainDict(Value[] newValues) { _mainDict = newValues; return this; }

    protected PackedVector _mainCodes;
    @property PackedVector mainCodes() { return _mainCodes; }
    @property MergeJob mainCodes(PackedVector newCodes) { _mainCodes = newCodes; return this; }

    protected Value[] _frozenDict;
    @property Value[] frozenDict() { return _frozenDict; }
    @property MergeJob frozenDict(Value[] newValues) { _frozenDict = newValues; return this; }

    protected  uint[] _frozenCodes;
    @property uint[] frozenCodes() { return _frozenCodes; }
    @property MergeJob frozenCodes(uint[] newCodes) { _frozenCodes = newCodes; return this; }
    

    protected  Value[] _newDict;
    @property Value[] newDict() { return _newDict; }
    @property MergeJob newDict(Value[] newValues) { _newDict = newValues; return this; }

    protected  PackedVector _newCodes;
    @property PackedVector newCodes() { return _newCodes; }
    @property MergeJob newCodes(PackedVector newCodes) { _newCodes = newCodes; return this; }

    protected  bool _done;
    @property bool done() { return _done; }
    @property MergeJob done(bool newDone) { _done = newDone; return this; }

    protected  bool _released;
    @property bool released() { return _released; }
    @property MergeJob released(bool newReleased) { _released = newReleased; return this; }

    /// Gemeinsames sortiertes Dictionary, alle Codes werden umgeschrieben und neu gepackt.
    void run() {
        auto all = (mainDict ~ frozenDict).dup
            .sort!valueLess
            .uniq!((a, b) => compareValues(a, b) == 0)
            .toValues;
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
