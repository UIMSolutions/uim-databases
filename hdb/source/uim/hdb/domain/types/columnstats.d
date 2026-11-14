
/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.columnstats;

import uim.hdb;
import uim.hdb.domain.enumerations.columntype;
import vibe.d;

mixin(ShowModule!());

@safe:

struct ColumnStats {
    string name;
    size_t rows, mainRows, deltaRows, mainDistinct, deltaDistinct;
    uint mainBits;
    size_t mainCodeBytes;
    ColumnType type;

    Json toJson() const {
        return Json.emptyObject
            .set("name", name)
            .set("rows", rows)
            .set("mainRows", mainRows)
            .set("deltaRows", deltaRows)
            .set("mainDistinct", mainDistinct)
            .set("deltaDistinct", deltaDistinct)
            .set("mainBits", mainBits)
            .set("mainCodeBytes", mainCodeBytes)
            .set("type", type.to!string);
    }
}