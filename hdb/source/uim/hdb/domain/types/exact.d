/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.exact;

import uim.hdb;


/// A value whose order does not match that of its text: `rank` is a canonical decimal number of arbitrary length.
/// When sorted as strings, “10” comes before “9” and ‘P2D’ comes after “PT1H”; a `double` would lose digits when converted to `Edm.Decimal`.
struct Exact {
    string text;
    string rank;

    int opCmp(const Exact other) const {
        return compareDecimalText(rank, other.rank);
    }

    Json toJson() const {
        return Json.emptyObject
            .set("text", text)
            .set("rank", rank);
    }

    static Exact fromJson(Json j) {
        return Exact(j.getString("text"), j.getString("rank"));
    }
}