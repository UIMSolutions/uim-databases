module uim.hdb.domain.types.columnview;

import uim.hdb;
import uim.hdb.domain.value;
import std.algorithm : map, sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;

/// Momentaufnahme einer Spalte: erlaubt Lesen einzelner Werte, ohne die Spalte selbst anzufassen.
struct ColumnView {
    /* private */ Value[] mainDict;
    /* private */ PackedVector mainCodes;
    /* private */ Value[] deltaDict;
    /* private */ uint[] deltaCodes;

    size_t length() const {
        return mainCodes.length + deltaCodes.length;
    }

    Value get(size_t row) {
        return row < mainCodes.length
            ? mainDict[mainCodes[row]] : deltaDict[deltaCodes[row - mainCodes.length]];
    }
}
///
unittest {
    auto cv = ColumnView(
        ["a", "b", "c"].map!(s => Value(s)).array,
        PackedVector.pack([0, 1, 2], 3),
        ["d", "e"].map!(s => Value(s)).array,
        [0, 1]
    );
    assert(cv.length == 5);
    assert(cv.get(0) == Value("a"));
    assert(cv.get(3) == Value("d"));
}