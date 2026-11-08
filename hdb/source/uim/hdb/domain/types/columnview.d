/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.columnview;

import uim.hdb;
import std.algorithm : map, sort, uniq;
import std.array : array;
import std.exception : enforce;
import std.range : assumeSorted;

@safe:

/// Snapshot of a column: allows you to read individual values without modifying the column itself.
struct ColumnView {
    /* private */
    Value[] mainDict;
    /* private */
    PackedVector mainCodes;
    /* private */
    Value[] deltaDict;
    /* private */
    uint[] deltaCodes;

    size_t length() const {
        return mainCodes.length + deltaCodes.length;
    }

    Value get(size_t row) {
        return row < mainCodes.length
            ? mainDict[mainCodes[row]] : deltaDict[deltaCodes[row - mainCodes.length]];
    }

    // Json toJson() const {
    //     return Json.emptyObject
    //         .set("mainDict", mainDict.map!(v => v.toJson).array)
    //         .set("mainCodes", mainCodes)
    //         .set("delta", deltaDict.map!(v => v.toJson).array)
    //         .set("deltaCodes", deltaCodes);
    // }
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
