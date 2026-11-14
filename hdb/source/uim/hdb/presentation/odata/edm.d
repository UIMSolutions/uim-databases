/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.odata.edm;

import uim.hdb;

// mixin

@safe:

/// Formats in which OData transmits values that the core stores differently: Edm.Binary is Base64url instead of Hex,
/// Edm.Geometry and Edm.Geography are GeoJSON instead of WKT.
ubyte[] hexToBytes(string hex) {
    auto bytes = new ubyte[hex.length / 2];
    foreach (i, ref b; bytes)
        b = hex[2 * i .. 2 * i + 2].to!ubyte(16);
    return bytes;
}

/** 
*    Converts a hexadecimal string to a Base64url-encoded string.
*    @param hex The hexadecimal string to convert.
*    @return The Base64url-encoded string.
*/
string hexToBase64Url(string hex) {
    return Base64URLNoPadding.encode(hexToBytes(hex)).idup;
}

/// Hex text to Base64url; padding with = is optional in OData.
string base64UrlToHex(string text) {
    ubyte[] bytes;
    try
        bytes = Base64URLNoPadding.decode(text.strip.stripRight("="));
    catch (Exception)
        throw new Exception("Kein Base64url: " ~ text);
    return bytes.map!(b => format("%02X", b)).join;
}

/// GeoJSON text from canonical WKT, see normalizeGeo. The numbers are not reformatted.
string wktToGeoJson(string wkt) {
    string pair(string point) {
        return "[" ~ point.replace(" ", ",") ~ "]";
    }

    string line(string points) {
        return "[" ~ points.split(", ").map!pair.join(",") ~ "]";
    }

    if (wkt[0 .. 5] == "POINT")
        return `{"type":"Point","coordinates":` ~ pair(wkt[6 .. $ - 1]) ~ "}";
    if (wkt[0 .. 10] == "LINESTRING")
        return `{"type":"LineString","coordinates":` ~ line(wkt[11 .. $ - 1]) ~ "}";
    auto rings = wkt["POLYGON((".length .. $ - 2].split("), (");
    return `{"type":"Polygon","coordinates":[` ~ rings.map!line.join(",") ~ "]}";
}

/// WKT from a GeoJSON object. The core checks the validity afterwards.
string geoJsonToWkt(Json geo) {
    string pair(Json point) {
        enforce(point.isArray && point.length == 2, "GeoJSON: Koordinate braucht x und y");
        return exactText(point[0].to!double) ~ " " ~ exactText(point[1].to!double);
    }

    string line(Json points) {
        enforce(points.isArray, "GeoJSON: Liste von Koordinaten erwartet");
        return points.get!(Json[]).map!pair.join(", ");
    }

    enforce(geo.isObject && geo["type"].isString, "GeoJSON: type fehlt");
    auto coordinates = geo["coordinates"];
    enforce(coordinates.isArray, "GeoJSON: coordinates fehlt");
    switch (geo["type"].get!string) {
    case "Point":
        return "POINT(" ~ pair(coordinates) ~ ")";
    case "LineString":
        return "LINESTRING(" ~ line(coordinates) ~ ")";
    case "Polygon":
        return "POLYGON(" ~ coordinates.get!(Json[]).map!(ring => "(" ~ line(ring) ~ ")").join(", ") ~ ")";
    default:
        throw new Exception("GeoJSON: nur Point, LineString und Polygon: " ~ geo["type"].get!string);
    }
}
///
unittest {
    import uim.hdb.domain.value : normalizeGeo;
    import std.exception : assertThrown;
    import vibe.data.json : parseJsonString;

    assert(hexToBase64Url("FBFF") == "-_8");
    assert(base64UrlToHex("-_8") == "FBFF" && base64UrlToHex("-_8=") == "FBFF");
    assert(hexToBase64Url("") == "" && base64UrlToHex("") == "");
    assert(hexToBytes("00FF") == [0, 255]);
    assertThrown(base64UrlToHex("a+/b"));

    foreach (wkt, json; ["POINT(13.4 52.5)": `{"type":"Point","coordinates":[13.4,52.5]}`,
            "LINESTRING(0 0, 1 1.5)": `{"type":"LineString","coordinates":[[0,0],[1,1.5]]}`,
            "POLYGON((0 0, 4 0, 4 4, 0 0), (1 1, 2 1, 2 2, 1 1))":
            `{"type":"Polygon","coordinates":[[[0,0],[4,0],[4,4],[0,0]],[[1,1],[2,1],[2,2],[1,1]]]}`]) {
        assert(wktToGeoJson(wkt) == json, wktToGeoJson(wkt));
        assert(normalizeGeo(geoJsonToWkt(parseJsonString(json))) == wkt);
    }
    assertThrown(geoJsonToWkt(parseJsonString(`{"type":"Circle","coordinates":[1,2]}`)));
    assertThrown(geoJsonToWkt(parseJsonString(`{"type":"Point","coordinates":[1]}`)));
    assertThrown(geoJsonToWkt(parseJsonString(`{"coordinates":[1,2]}`)));
    assertThrown(geoJsonToWkt(Json("POINT(1 2)")));
}
