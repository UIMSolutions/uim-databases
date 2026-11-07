module uim.hdb.domain.enumerations.columntype;

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