/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.enumerations.columntype;

@safe:
/// Spaltentypen. Jeder entspricht einem primitiven EDM-Typ, siehe typeSpecs; nur `link` ergänzt sie.
enum ColumnType {
    integer,
    decimal, /// double, also Edm.Double; das exakte Edm.Decimal ist `exact`
    text,
    blob, /// Binärdaten, gespeichert als Hex-Text in Großbuchstaben
    geo, /// Geometrie als WKT: POINT, LINESTRING oder POLYGON
    link, /// URL mit erlaubtem Schema, siehe normalizeLink
    boolean,
    byte_,
    sbyte,
    int16,
    int32,
    single,
    exact, /// Dezimalzahl beliebiger Länge, gespeichert als Exact
    date,
    dateTime, /// immer UTC mit sieben Nachkommastellen, damit die Textordnung die Zeitordnung ist
    time,
    duration, /// gespeichert als Exact, Rang sind die 100-ns-Ticks
    guid,
    geography /// wie geo, aber Längen- und Breitengrad in WGS84
}