/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.enumerations.servermode;

import std.exception : enforce;
import std.string : strip, toLower;

@safe:

/// Betriebsart des Servers (HDB_MODE). Die eingebettete Datenbank ist keine Betriebsart des Servers, sondern
/// eine Bibliothek: siehe uim.hdb.embedded.
enum ServerMode {
    multi, // mehrere Mandanten mit Systembereich (Standard)
    single, // genau ein Mandant (default), ohne Mandantenfeld und Systembereich
    gateway // ein Zugang vor mehreren hdb-Servern, Weiterleitung nach Mandant
}

string modeName(ServerMode mode) {
    final switch (mode) {
    case ServerMode.multi:
        return "multi";
    case ServerMode.single:
        return "single";
    case ServerMode.gateway:
        return "gateway";
    }
}

/// Wert von HDB_MODE; leer bedeutet multi.
ServerMode parseServerMode(string text) {
    switch (text.strip.toLower) {
    case "", "multi", "multi-tenant":
        return ServerMode.multi;
    case "single", "single-tenant":
        return ServerMode.single;
    case "gateway", "distributed":
        return ServerMode.gateway;
    default:
        enforce(false, "HDB_MODE must be single, multi or gateway, not '" ~ text ~ "'");
        assert(0);
    }
}

unittest {
    import std.exception : assertThrown;

    assert(parseServerMode("") == ServerMode.multi && parseServerMode(" Single ") == ServerMode.single);
    assert(parseServerMode("distributed") == ServerMode.gateway && modeName(ServerMode.gateway) == "gateway");
    assertThrown(parseServerMode("embedded"));
}
