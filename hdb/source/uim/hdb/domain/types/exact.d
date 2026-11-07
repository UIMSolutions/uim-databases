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
}