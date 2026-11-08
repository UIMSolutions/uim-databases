/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.value;

import uim.hdb;
import core.checkedint : adds, muls;
import std.algorithm : all, any, canFind, cmp, findSplit, startsWith;
import std.array : join;
import std.ascii : isDigit, isHexDigit;
import std.conv : to;
import std.datetime.date : Date, DateTime, TimeOfDay;
import std.exception : enforce;
import std.format : format;
import std.math : abs, isFinite;
import std.regex : matchFirst;
import std.string : indexOf, replace, split, strip, stripLeft, stripRight, toLower, toUpper;
import core.time : dur;
import std.sumtype;

@safe:

/// Die einzige Zuordnung von SQL- zu EDM-Typen. Bei gleichem EDM-Typ gewinnt beim Lesen der erste Eintrag.
static immutable TypeSpec[] typeSpecs = [
    TypeSpec(ColumnType.boolean, "BOOLEAN", "Edm.Boolean", ["BOOL"]),
    TypeSpec(ColumnType.byte_, "TINYINT", "Edm.Byte", ["BYTE"]),
    TypeSpec(ColumnType.sbyte, "SBYTE", "Edm.SByte", []),
    TypeSpec(ColumnType.int16, "SMALLINT", "Edm.Int16", ["INT16"]),
    TypeSpec(ColumnType.int32, "INT32", "Edm.Int32", []),
    TypeSpec(ColumnType.integer, "INTEGER", "Edm.Int64", ["INT", "BIGINT", "INT64"]),
    TypeSpec(ColumnType.single, "REAL", "Edm.Single", ["SINGLE"]),
    TypeSpec(ColumnType.decimal, "DECIMAL", "Edm.Double", ["DOUBLE"]),
    TypeSpec(ColumnType.exact, "NUMERIC", "Edm.Decimal", []),
    TypeSpec(ColumnType.text, "VARCHAR", "Edm.String", ["TEXT"]),
    TypeSpec(ColumnType.blob, "BLOB", "Edm.Binary", ["BINARY", "VARBINARY"]),
    TypeSpec(ColumnType.date, "DATE", "Edm.Date", []),
    TypeSpec(ColumnType.dateTime, "TIMESTAMP", "Edm.DateTimeOffset", ["DATETIMEOFFSET"]),
    TypeSpec(ColumnType.time, "TIME", "Edm.TimeOfDay", ["TIMEOFDAY"]),
    TypeSpec(ColumnType.duration, "DURATION", "Edm.Duration", []),
    TypeSpec(ColumnType.guid, "GUID", "Edm.Guid", ["UUID"]),
    TypeSpec(ColumnType.geo, "GEO", "Edm.Geometry", ["GEOMETRY", "ST_GEOMETRY"]),
    TypeSpec(ColumnType.geography, "GEOGRAPHY", "Edm.Geography", []),
    TypeSpec(ColumnType.link, "LINK", "Edm.String", ["URL"]), // EDM kennt keine URL
];

private ref immutable(TypeSpec) specOf(ColumnType type) {
    foreach (ref s; typeSpecs)
        if (s.type == type)
            return s;
    assert(0);
}

string edmType(ColumnType type) {
    return specOf(type).edm;
}

/// Ganzzahlige Spaltentypen; alle werden als long gespeichert.
bool isIntegerType(ColumnType type) {
    return [ColumnType.byte_, ColumnType.sbyte, ColumnType.int16, ColumnType.int32, ColumnType.integer].canFind(type);
}

/// Spaltentypen, mit denen SUM und AVG rechnen können.
bool isNumeric(ColumnType type) {
    return isIntegerType(type) || [ColumnType.single, ColumnType.decimal, ColumnType.exact].canFind(type);
}

/// Spaltentypen, deren Werte als string gespeichert werden und deshalb LIKE erlauben.
bool isTextual(ColumnType type) {
    return !isNumeric(type) && type != ColumnType.boolean && type != ColumnType.duration;
}

/// SQL-NULL als eigener Wert.
struct Null {
    int opCmp(const Null) const pure nothrow @nogc @safe {
        return 0;
    }
}

int compareDecimalText(string a, string b) {
    immutable negative = a[0] == '-';
    if (negative != (b[0] == '-'))
        return negative ? -1 : 1;
    auto x = (negative ? a[1 .. $] : a).findSplit("."), y = (negative ? b[1 .. $] : b).findSplit(".");
    int order = x[0].length != y[0].length ? (x[0].length < y[0].length ? -1 : 1) : cmp(x[0], y[0]);
    if (order == 0)
        order = cmp(x[2], y[2]); // ohne Nullen am Ende ist die Textordnung der Nachkommastellen richtig
    return negative ? -order : order;
}

alias Value = SumType!(long, double, string, Null, bool, Exact);

/// Zeiger auf den Inhalt, wenn der Wert den Typ T hat, sonst null.
/// @trusted: der Zeiger zeigt in `v` und gilt nur, solange `v` lebt und nicht neu zugewiesen wird. `return ref` macht
/// das für den Compiler sichtbar (mit -preview=dip1000 wird es geprüft); alle Aufrufer verwenden ihn sofort.
T* peek(T)(return ref Value v) @trusted {
    return v.match!((ref x) {
        static if (is(typeof(x) == T))
            return &x;
        else
            return cast(T*)null;
    });
}

private T convertTo(T, X)(X x) {
    static if (is(X : T))
        return x;
    else
        throw new Exception("Wert vom Typ " ~ X.stringof ~ " ist kein " ~ T.stringof);
}

/// Inhalt als T; erlaubt sind nur implizite Umwandlungen wie long nach double.
T get(T)(Value v) {
    return v.match!(x => convertTo!T(x));
}

private int compareContent(X, Y)(X x, Y y) {
    static if (is(typeof(x < y)))
        return x < y ? -1 : (x > y ? 1 : 0);
    else
        throw new Exception("Werte vom Typ " ~ X.stringof ~ " und " ~ Y.stringof ~ " sind nicht vergleichbar");
}

/// Überschreibt einen Wert in einem Feld oder einer Variablen.
/// Phobos nennt die Zuweisung an einen SumType mit Text @system: zeigte gerade noch eine Referenz in den alten
/// Inhalt (etwa von peek oder match mit ref), würde sie ungültig. @trusted, weil dieser Code solche Referenzen nie
/// über eine Zuweisung hinweg hält: peek-Zeiger werden im selben Ausdruck verwendet und verworfen.
void assign(ref Value slot, Value value) @trusted {
    slot = value;
}

Value nullValue() {
    return Value(Null());
}

bool isNull(Value v) {
    return v.peek!Null !is null;
}

/// Gesamtordnung über Werte desselben Typs; NULL sortiert vor allem anderen.
int compareValues(Value a, Value b) {
    immutable an = isNull(a), bn = isNull(b);
    if (an || bn)
        return an == bn ? 0 : (an ? -1 : 1);
    return match!((x, y) => compareContent(x, y))(a, b);
}

bool valueLess(Value a, Value b) {
    return compareValues(a, b) < 0;
}

/// Wandelt ein SQL-Literal (oder NULL) passend zum Spaltentyp in einen Value um.
Value parseLiteral(ColumnType type, string literal) {
    literal = literal.strip;
    if (literal.toUpper == "NULL")
        return nullValue();
    if (isNumeric(type) || type == ColumnType.boolean)
        return valueFromInput(type, literal);
    if (type == ColumnType.blob && literal.length && (literal[0] == 'X' || literal[0] == 'x'))
        literal = literal[1 .. $]; // toSqlLiteral schreibt Hex-Text ohne X, beide Formen müssen lesbar sein
    return valueFromInput(type, unquote(literal));
}

private string unquote(string literal) {
    enforce(literal.length >= 2 && literal[0] == '\'' && literal[$ - 1] == '\'',
        "Textliterale müssen in Hochkommata stehen: " ~ literal);
    return literal[1 .. $ - 1].replace("''", "'");
}

/// Hex-Text in Großbuchstaben; je zwei Ziffern sind ein Byte.
string normalizeBlob(string hex) {
    auto text = hex.strip;
    enforce(text.length % 2 == 0 && text.all!isHexDigit, "BLOB braucht Hex-Ziffern in Paaren: " ~ hex);
    return text.toUpper;
}

/// WKT in einheitlicher Schreibweise, damit gleiche Geometrien auch als Werte gleich sind.
string normalizeGeo(string wkt, bool wgs84 = false) {
    auto text = wkt.strip;
    auto open = text.indexOf('(');
    enforce(open > 0 && text[$ - 1] == ')', "GEO braucht WKT wie POINT(13.4 52.5): " ~ wkt);
    auto kind = text[0 .. open].strip.toUpper;
    auto inner = text[open + 1 .. $ - 1];
    switch (kind) {
    case "POINT":
        auto point = geoPoints(inner, wgs84);
        enforce(point.length == 1, "POINT braucht genau eine Koordinate: " ~ wkt);
        return kind ~ "(" ~ point[0] ~ ")";
    case "LINESTRING":
        auto line = geoPoints(inner, wgs84);
        enforce(line.length >= 2, "LINESTRING braucht mindestens zwei Koordinaten: " ~ wkt);
        return kind ~ "(" ~ line.join(", ") ~ ")";
    case "POLYGON":
        return kind ~ "(" ~ geoRings(inner, wkt, wgs84).join(", ") ~ ")";
    default:
        throw new Exception("GEO kennt nur POINT, LINESTRING und POLYGON: " ~ wkt);
    }
}

/// Koordinatenpaare "x y" in kanonischer Zahlendarstellung.
private string[] geoPoints(string list, bool wgs84) {
    string[] points;
    foreach (raw; list.split(",")) {
        auto parts = raw.split();
        enforce(parts.length == 2, "Koordinate braucht x und y: " ~ raw.strip);
        string[] numbers;
        foreach (i, p; parts) {
            double d;
            try
                d = p.to!double;
            catch (Exception)
                throw new Exception("Keine Zahl in Koordinate: " ~ p);
            enforce(isFinite(d), "Keine endliche Zahl in Koordinate: " ~ p);
            enforce(!wgs84 || abs(d) <= (i == 0 ? 180 : 90), "GEOGRAPHY braucht Länge und Breite in Grad: " ~ raw.strip);
            numbers ~= exactText(d);
        }
        points ~= numbers.join(" ");
    }
    return points;
}

/// Die Ringe eines Polygons: "(x y, ...), (x y, ...)". Jeder Ring ist geschlossen.
private string[] geoRings(string list, string wkt, bool wgs84) {
    string[] rings;
    auto rest = list.strip;
    while (true) {
        auto close = rest.indexOf(')');
        enforce(rest.length && rest[0] == '(' && close > 0, "POLYGON braucht Ringe in Klammern: " ~ wkt);
        auto ring = geoPoints(rest[1 .. close], wgs84);
        enforce(ring.length >= 4 && ring[0] == ring[$ - 1],
            "Ein POLYGON-Ring braucht vier Koordinaten und endet an seinem Anfang: " ~ wkt);
        rings ~= "(" ~ ring.join(", ") ~ ")";
        rest = rest[close + 1 .. $].strip;
        if (rest.length == 0)
            return rings;
        enforce(rest[0] == ',', "POLYGON: ',' zwischen Ringen erwartet: " ~ wkt);
        rest = rest[1 .. $].strip;
    }
}

/// Prüft eine URL. Die Oberflächen zeigen sie als klickbaren Verweis, deshalb gibt es eine feste Liste von
/// Schemata: javascript: und data: dürfen gar nicht erst in die Tabelle gelangen.
string normalizeLink(string url) {
    auto text = url.strip;
    enforce(!text.any!(c => c <= ' ' || c == 0x7f), "LINK darf keine Leer- oder Steuerzeichen enthalten: " ~ url);
    auto colon = text.indexOf(':');
    enforce(colon > 0, "LINK braucht ein Schema wie https: " ~ url);
    auto scheme = text[0 .. colon].toLower;
    auto rest = text[colon + 1 .. $];
    enforce(["http", "https", "ftp", "mailto"].canFind(scheme), "LINK erlaubt http, https, ftp und mailto: " ~ url);
    if (scheme == "mailto")
        enforce(rest.length, "LINK braucht eine Adresse: " ~ url);
    else
        enforce(rest.length > 2 && rest[0 .. 2] == "//" && rest[2] != '/', "LINK braucht einen Host: " ~ url);
    return scheme ~ ":" ~ rest;
}

/// Dezimalzahl ohne führende und abschließende Nullen; Exponenten werden ausgeschrieben.
string normalizeNumeric(string input) {
    auto text = input.strip;
    immutable negative = text.startsWith("-");
    if (negative || text.startsWith("+"))
        text = text[1 .. $];
    auto parts = text.toLower.findSplit("e");
    long exponent;
    if (parts[1].length) {
        try
            exponent = parts[2].to!long;
        catch (Exception)
            throw new Exception("Keine Dezimalzahl: " ~ input);
        enforce(abs(exponent) <= 1000, "Exponent zu groß: " ~ input);
    }
    auto mantissa = parts[0].findSplit(".");
    auto digits = mantissa[0] ~ mantissa[2];
    enforce(digits.length && digits.all!isDigit, "Keine Dezimalzahl: " ~ input);

    long point = cast(long) mantissa[0].length + exponent;
    if (point <= 0) {
        digits = "0".replicate(cast(size_t)(1 - point)) ~ digits;
        point = 1;
    } else if (point > digits.length)
        digits ~= "0".replicate(cast(size_t) point - digits.length);
    auto whole = digits[0 .. cast(size_t) point].stripLeft("0");
    auto fraction = digits[cast(size_t) point .. $].stripRight("0");
    auto result = (whole.length ? whole : "0") ~ (fraction.length ? "." ~ fraction : "");
    return negative && result != "0" ? "-" ~ result : result;
}

private string replicate(string s, size_t count) {
    string result;
    foreach (_; 0 .. count)
        result ~= s;
    return result;
}

private enum long ticksPerSecond = 10_000_000;

/// ISO-8601-Dauer aus Tagen und Uhrzeit wie P1DT2H30M; Monate und Jahre haben keine feste Länge und fehlen in EDM.
Exact parseDuration(string input) {
    auto text = input.strip;
    auto m = matchFirst(text, `^(-?)P(?:(\d+)D)?(T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)(?:\.(\d{1,7}))?S)?)?$`);
    enforce(!m.empty && text[$ - 1] != 'P' && text[$ - 1] != 'T', "DURATION braucht eine Dauer wie P1DT2H: " ~ input);
    bool overflow;
    long total;
    foreach (i, seconds; [86_400L, 3600L, 60L, 1L]) {
        auto part = m[[2, 4, 5, 6][i]];
        if (part.length) {
            enforce(part.length <= 18, "DURATION ist zu lang: " ~ input);
            total = adds(total, muls(part.to!long, seconds * ticksPerSecond, overflow), overflow);
        }
    }
    enforce(!overflow, "DURATION ist zu lang: " ~ input);
    total += (m[7] ~ "0000000")[0 .. 7].to!long;

    long rest = total;
    auto days = rest / (86_400 * ticksPerSecond);
    rest %= 86_400 * ticksPerSecond;
    auto hours = rest / (3600 * ticksPerSecond);
    rest %= 3600 * ticksPerSecond;
    auto minutes = rest / (60 * ticksPerSecond);
    rest %= 60 * ticksPerSecond;
    auto clock = (hours ? hours.to!string ~ "H" : "") ~ (minutes ? minutes.to!string ~ "M" : "");
    if (rest)
        clock ~= normalizeNumeric(format("%d.%07d", rest / ticksPerSecond, rest % ticksPerSecond)) ~ "S";
    auto body_ = (days ? days.to!string ~ "D" : "") ~ (clock.length ? "T" ~ clock : "");
    if (total == 0)
        return Exact("PT0S", "0");
    return m[1].length ? Exact("-P" ~ body_, "-" ~ total.to!string) : Exact("P" ~ body_, total.to!string);
}

string normalizeDate(string input) {
    auto text = input.strip;
    enforce(!matchFirst(text, `^\d{4}-\d{2}-\d{2}$`).empty, "DATE braucht die Form 2026-11-06: " ~ input);
    try
        return Date.fromISOExtString(text).toISOExtString;
    catch (Exception)
        throw new Exception("Kein gültiges Datum: " ~ input);
}

/// hh:mm:ss, Nachkommastellen ohne Nullen am Ende. Die Textordnung bleibt richtig: 12:00:05 steht vor 12:00:05.5.
string normalizeTime(string input) {
    auto m = matchFirst(input.strip, `^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,7}))?)?$`);
    enforce(!m.empty, "TIME braucht die Form 12:30:00: " ~ input);
    try
        return TimeOfDay(m[1].to!int, m[2].to!int, m[3].length ? m[3].to!int : 0).toISOExtString
            ~ (m[4].stripRight("0").length ? "." ~ m[4].stripRight("0") : "");
    catch (Exception)
        throw new Exception("Keine gültige Uhrzeit: " ~ input);
}

/// Zeitpunkt in UTC mit fester Länge. Der Versatz ist Pflicht, EDM kennt keine lokalen Zeitpunkte.
string normalizeDateTime(string input) {
    auto m = matchFirst(input.strip,
        `^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,7}))?)?(?:Z|z|([+-])(\d{2}):(\d{2}))$`);
    enforce(!m.empty, "TIMESTAMP braucht die Form 2026-11-06T12:30:00Z: " ~ input);
    DateTime moment;
    try {
        moment = DateTime(Date.fromISOExtString(m[1]), TimeOfDay(m[2].to!int, m[3].to!int, m[4].length ? m[4].to!int : 0));
        if (m[6].length) {
            enforce(m[7].to!int < 24 && m[8].to!int < 60);
            immutable offset = m[7].to!int * 60 + m[8].to!int;
            moment -= dur!"minutes"(m[6] == "-" ? -offset : offset);
        }
    } catch (Exception)
        throw new Exception("Kein gültiger Zeitpunkt: " ~ input);
    enforce(moment.year >= 1 && moment.year <= 9999, "Zeitpunkt außerhalb der Jahre 1 bis 9999: " ~ input);
    return moment.toISOExtString ~ "." ~ (m[5] ~ "0000000")[0 .. 7] ~ "Z";
}

string normalizeGuid(string input) {
    auto text = input.strip;
    enforce(!matchFirst(text, `^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$`).empty,
        "GUID braucht die Form 01234567-89ab-cdef-0123-456789abcdef: " ~ input);
    return text.toLower;
}

private Value integerValue(ColumnType type, string input) {
    long value;
    try
        value = input.strip.to!long;
    catch (Exception)
        throw new Exception("Keine ganze Zahl: " ~ input);
    long low = long.min, high = long.max;
    switch (type) {
    case ColumnType.byte_:
        low = 0;
        high = 255;
        break;
    case ColumnType.sbyte:
        low = -128;
        high = 127;
        break;
    case ColumnType.int16:
        low = short.min;
        high = short.max;
        break;
    case ColumnType.int32:
        low = int.min;
        high = int.max;
        break;
    default:
        break;
    }
    enforce(value >= low && value <= high, "Zahl außerhalb des Bereichs von " ~ typeName(type) ~ ": " ~ input);
    return Value(value);
}

private double finiteNumber(string input) {
    double d;
    try
        d = input.strip.to!double;
    catch (Exception)
        throw new Exception("Keine Zahl: " ~ input);
    // NaN hat keine Ordnung: das sortierte Dictionary des Merges würde dadurch auch andere Zeilen verfälschen
    enforce(isFinite(d), "Keine endliche Zahl: " ~ input);
    return d;
}

/// Der double zum kürzesten Text, der denselben float ergibt: 0.1 bleibt 0.1 statt 0.100000001490116.
private double singleValue(string input) {
    auto d = finiteNumber(input);
    immutable f = cast(float) d;
    enforce(isFinite(f), "Zahl außerhalb des Bereichs von REAL: " ~ input);
    foreach (precision; 6 .. 10) {
        auto text = format("%.*g", precision, cast(double) f);
        if (text.to!float == f)
            return text.to!double;
    }
    return f;
}

double toDouble(Value v) {
    if (auto l = v.peek!long)
        return *l;
    if (auto e = v.peek!Exact)
        return e.rank.to!double;
    return *v.peek!double;
}

string typeName(ColumnType t) {
    return specOf(t).name;
}

/// Der kanonische Name, wie ihn typeName liefert; so stehen Typen in Tabellendateien und Backups.
ColumnType parseTypeName(string name) {
    foreach (ref s; typeSpecs)
        if (s.name == name)
            return s.type;
    throw new Exception("Unbekannter Typ: " ~ name);
}

/// Typ aus CREATE TABLE: kanonischer Name, Synonym oder EDM-Name, ohne Rücksicht auf die Schreibweise.
ColumnType columnTypeOf(string name) {
    auto upper = name.toUpper;
    if (upper.startsWith("VARCHAR") || upper.startsWith("NVARCHAR"))
        return ColumnType.text;
    foreach (ref s; typeSpecs)
        if (s.name == upper || s.edm.toUpper == upper || s.aliases.canFind(upper))
            return s.type;
    throw new Exception("Unbekannter Typ: " ~ name);
}

/// Kürzeste Dezimaldarstellung, die exakt denselben double ergibt (to!string behielte nur 6 Stellen).
string exactText(double d) {
    foreach (precision; 15 .. 17) {
        auto text = format("%.*g", precision, d);
        if (text.to!double == d)
            return text;
    }
    return format("%.17g", d);
}

/// Anzeigetext eines Werts; NULL ergibt "NULL".
string valueText(Value v) {
    if (isNull(v))
        return "NULL";
    if (auto l = v.peek!long)
        return (*l).to!string;
    if (auto d = v.peek!double)
        return exactText(*d);
    if (auto b = v.peek!bool)
        return *b ? "true" : "false";
    if (auto e = v.peek!Exact)
        return e.text;
    return *v.peek!string;
}

/// SQL-Literal eines Werts; parseLiteral liest es verlustfrei zurück.
string toSqlLiteral(Value v) {
    if (auto s = v.peek!string)
        return "'" ~ (*s).replace("'", "''") ~ "'";
    if (auto e = v.peek!Exact)
        return e.text == e.rank ? e.text : "'" ~ e.text ~ "'";
    return valueText(v);
}

/// Wandelt Formulartext (ohne SQL-Quoting) passend zum Spaltentyp in einen Value um.
Value valueFromInput(ColumnType type, string input) {
    final switch (type) {
    case ColumnType.integer:
    case ColumnType.byte_:
    case ColumnType.sbyte:
    case ColumnType.int16:
    case ColumnType.int32:
        return integerValue(type, input);
    case ColumnType.decimal:
        return Value(finiteNumber(input));
    case ColumnType.single:
        return Value(singleValue(input));
    case ColumnType.exact:
        auto number = normalizeNumeric(input);
        return Value(Exact(number, number));
    case ColumnType.boolean:
        auto word = input.strip.toLower;
        enforce(word == "true" || word == "false", "BOOLEAN braucht true oder false: " ~ input);
        return Value(word == "true");
    case ColumnType.text:
        return Value(input);
    case ColumnType.blob:
        return Value(normalizeBlob(input));
    case ColumnType.geo:
        return Value(normalizeGeo(input));
    case ColumnType.geography:
        return Value(normalizeGeo(input, true));
    case ColumnType.link:
        return Value(normalizeLink(input));
    case ColumnType.date:
        return Value(normalizeDate(input));
    case ColumnType.dateTime:
        return Value(normalizeDateTime(input));
    case ColumnType.time:
        return Value(normalizeTime(input));
    case ColumnType.duration:
        return Value(parseDuration(input));
    case ColumnType.guid:
        return Value(normalizeGuid(input));
    }
}

unittest {
    foreach (d; [1.23456789012, 0.1, 1234567.891, 1e20, 2.0, -0.000123456789])
        assert(exactText(d).to!double == d);
    assert(exactText(0.1) == "0.1");
    assert(toSqlLiteral(Value("it's")) == "'it''s'");
    assert(toSqlLiteral(nullValue) == "NULL");
    assert(parseLiteral(ColumnType.decimal, toSqlLiteral(Value(1234567.891))) == Value(1234567.891));
    assert(valueFromInput(ColumnType.integer, " 7 ") == Value(7L));
    assert(valueFromInput(ColumnType.text, " 7 ") == Value(" 7 "));
    import std.exception : assertThrown;

    assertThrown(valueFromInput(ColumnType.integer, "1; DROP TABLE t"));
    assertThrown(valueFromInput(ColumnType.decimal, "nan"));
    foreach (bad; ["nan", "NaN", "inf", "-inf", "infinity", "1e999"])
        assertThrown(parseLiteral(ColumnType.decimal, bad));
}

unittest {
    import std.exception : assertThrown;

    assert(parseLiteral(ColumnType.blob, "X'00ff'") == Value("00FF"));
    assert(parseLiteral(ColumnType.blob, "x'00FF'") == Value("00FF"));
    assert(parseLiteral(ColumnType.blob, "''") == Value(""));
    assert(parseLiteral(ColumnType.blob, toSqlLiteral(Value("00FF"))) == Value("00FF"));
    assert(isNull(parseLiteral(ColumnType.blob, "NULL")));
    assert(valueFromInput(ColumnType.blob, " ab ") == Value("AB"));
    foreach (bad; ["X'0'", "X'GG'", "'abc'", "X''' OR 1=1"])
        assertThrown(parseLiteral(ColumnType.blob, bad));

    assert(normalizeGeo(" point ( 13.4   52.5 ) ") == "POINT(13.4 52.5)");
    assert(normalizeGeo("LineString(0 0,1 1.50)") == "LINESTRING(0 0, 1 1.5)");
    immutable polygon = "POLYGON((0 0, 4 0, 4 4, 0 0), (1 1, 2 1, 2 2, 1 1))";
    assert(normalizeGeo("polygon((0 0,4 0,4 4,0 0),(1 1,2 1,2 2,1 1))") == polygon);
    assert(normalizeGeo(polygon) == polygon);
    assert(normalizeGeo("POINT(1e20 -0.1)") == normalizeGeo(normalizeGeo("POINT(1e20 -0.1)")));
    assert(parseLiteral(ColumnType.geo, "'POINT(1 2)'") == Value("POINT(1 2)"));
    foreach (bad; ["", "POINT", "POINT()", "POINT(1)", "POINT(1 2 3)", "POINT(1 2, 3 4)", "POINT(nan 1)", "POINT(a b)",
            "CIRCLE(1 2)", "LINESTRING(1 2)", "POLYGON(0 0, 1 1, 2 2, 0 0)", "POLYGON((0 0, 1 1, 0 0))",
            "POLYGON((0 0, 1 0, 1 1, 2 2))", "POLYGON((0 0, 1 0, 1 1, 0 0) (0 0, 1 0, 1 1, 0 0))"])
        assertThrown(normalizeGeo(bad));

    assert(normalizeLink(" HTTPS://Example.org/a?b=1 ") == "https://Example.org/a?b=1");
    assert(normalizeLink("mailto:a@example.org") == "mailto:a@example.org");
    assert(parseLiteral(ColumnType.link, "'ftp://h/f'") == Value("ftp://h/f"));
    foreach (bad; ["", "example.org", "javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,x", "http://", "http:///a",
            "https:example.org", "mailto:", "http://a b", "http://a\nb"])
        assertThrown(normalizeLink(bad));

    assert(isTextual(ColumnType.text) && !isTextual(ColumnType.integer) && !isTextual(ColumnType.decimal));
}

unittest {
    import std.algorithm : sort;
    import std.array : array;
    import std.exception : assertThrown;
    import std.traits : EnumMembers;

    // Jeder Typ ist einmal beschrieben und über alle seine Namen erreichbar
    foreach (type; EnumMembers!ColumnType) {
        assert(parseTypeName(typeName(type)) == type);
        assert(columnTypeOf(typeName(type).toLower) == type);
        if (type != ColumnType.link)
            assert(columnTypeOf(edmType(type)) == type);
    }
    assert(columnTypeOf("VARCHAR(40)") == ColumnType.text && columnTypeOf("nvarchar") == ColumnType.text);
    assert(columnTypeOf("Edm.String") == ColumnType.text);
    assert(columnTypeOf("int") == ColumnType.integer && columnTypeOf("uuid") == ColumnType.guid);
    assertThrown(columnTypeOf("RAW"));
    assertThrown(parseTypeName("int"));

    // Wertebereiche der ganzen Zahlen
    assert(parseLiteral(ColumnType.byte_, "255") == Value(255L));
    assert(parseLiteral(ColumnType.sbyte, "-128") == Value(-128L));
    assert(parseLiteral(ColumnType.int16, "32767") == Value(32_767L));
    assert(parseLiteral(ColumnType.int32, "-2147483648") == Value(cast(long) int.min));
    assertThrown(parseLiteral(ColumnType.byte_, "256"));
    assertThrown(parseLiteral(ColumnType.byte_, "-1"));
    assertThrown(parseLiteral(ColumnType.sbyte, "128"));
    assertThrown(parseLiteral(ColumnType.int16, "32768"));
    assertThrown(parseLiteral(ColumnType.int32, "2147483648"));

    assert(valueText(parseLiteral(ColumnType.single, "0.1")) == "0.1");
    assert(valueText(parseLiteral(ColumnType.single, "16777217")) == "16777216");
    assertThrown(parseLiteral(ColumnType.single, "1e39"));
    assertThrown(parseLiteral(ColumnType.single, "nan"));

    assert(parseLiteral(ColumnType.boolean, "TRUE") == Value(true));
    assert(toSqlLiteral(parseLiteral(ColumnType.boolean, "false")) == "false");
    assertThrown(parseLiteral(ColumnType.boolean, "1"));

    // Edm.Decimal bleibt exakt, auch jenseits von double
    enum long_ = "12345678901234567890.123456789012345678";
    assert(valueText(parseLiteral(ColumnType.exact, long_)) == long_);
    foreach (pair; [["1.50", "1.5"], ["007", "7"], ["-0.0", "0"], [".5", "0.5"], ["5.", "5"], ["1e3", "1000"],
            ["1.5e-3", "0.0015"], ["+2", "2"], ["0", "0"], ["-1.2E+1", "-12"]])
        assert(normalizeNumeric(pair[0]) == pair[1], pair[0]);
    foreach (bad; ["", ".", "-", "abc", "1.2.3", "1e", "1e9999", "nan", "0x10"])
        assertThrown(normalizeNumeric(bad));
    auto numbers = ["10", "9", "-10", "-9", "0.5", "0.25", "-0.25", "100.1", "100.09"];
    Value[] sorted;
    foreach (n; numbers)
        sorted ~= parseLiteral(ColumnType.exact, n);
    sorted.sort!valueLess;
    string[] order;
    foreach (v; sorted)
        order ~= valueText(v);
    assert(order == ["-10", "-9", "-0.25", "0.25", "0.5", "9", "10", "100.09", "100.1"]);
    assert(parseLiteral(ColumnType.exact, toSqlLiteral(parseLiteral(ColumnType.exact, "1.5"))) == parseLiteral(ColumnType.exact, "1.50"));
    assert(toDouble(parseLiteral(ColumnType.exact, "1.5")) == 1.5);

    // Dauern sortieren nach ihrer Länge, nicht nach dem Text
    assert(parseDuration("P1DT2H30M").text == "P1DT2H30M");
    assert(parseDuration("PT36H").text == "P1DT12H");
    assert(parseDuration("PT0.5S").text == "PT0.5S" && parseDuration("PT90S").text == "PT1M30S");
    assert(parseDuration("-PT1H").text == "-PT1H" && parseDuration("P0D").text == "PT0S" && parseDuration("-PT0S").text == "PT0S");
    assert(valueLess(Value(parseDuration("PT1H")), Value(parseDuration("P1D"))));
    assert(valueLess(Value(parseDuration("-P1D")), Value(parseDuration("-PT1H"))));
    assert(parseLiteral(ColumnType.duration, toSqlLiteral(Value(parseDuration("P1D")))) == Value(parseDuration("PT24H")));
    foreach (bad; ["", "P", "PT", "P1Y", "P1M", "1D", "PT1", "P1DT", "PT1.12345678S", "P99999999999999999999D", "P999999999999D"])
        assertThrown(parseDuration(bad));

    assert(normalizeDate("2024-02-29") == "2024-02-29");
    foreach (bad; ["2023-02-29", "2026-13-01", "26-11-06", "2026-11-06T00:00:00Z", ""])
        assertThrown(normalizeDate(bad));

    assert(normalizeTime("12:30") == "12:30:00" && normalizeTime("12:30:05.500") == "12:30:05.5");
    foreach (bad; ["24:00:00", "12:60:00", "12:00:60", "12", "12:00:00.12345678"])
        assertThrown(normalizeTime(bad));

    assert(normalizeDateTime("2026-11-06T12:30:00Z") == "2026-11-06T12:30:00.0000000Z");
    assert(normalizeDateTime("2026-11-06T12:30:00.5+01:00") == "2026-11-06T11:30:00.5000000Z");
    assert(normalizeDateTime("2026-12-31T23:30-01:00") == "2027-01-01T00:30:00.0000000Z");
    assert(normalizeDateTime(normalizeDateTime("2026-11-06T12:30:00Z")) == "2026-11-06T12:30:00.0000000Z");
    // Text- und Zeitordnung stimmen überein, auch mit Sekundenbruchteilen
    assert(normalizeDateTime("2026-11-06T12:00:00Z") < normalizeDateTime("2026-11-06T12:00:00.5Z"));
    foreach (bad; ["2026-11-06", "2026-11-06T12:30:00", "2026-02-30T00:00:00Z", "2026-11-06T25:00:00Z",
            "2026-11-06T12:00:00+25:00", "9999-12-31T23:00:00-02:00"])
        assertThrown(normalizeDateTime(bad));

    assert(normalizeGuid("01234567-89AB-CDEF-0123-456789ABCDEF") == "01234567-89ab-cdef-0123-456789abcdef");
    foreach (bad; ["", "01234567", "01234567-89ab-cdef-0123-456789abcdeg", "0123456789abcdef0123456789abcdef"])
        assertThrown(normalizeGuid(bad));

    assert(parseLiteral(ColumnType.geography, "'POINT(13.4 52.5)'") == Value("POINT(13.4 52.5)"));
    assertThrown(parseLiteral(ColumnType.geography, "'POINT(181 0)'"));
    assertThrown(parseLiteral(ColumnType.geography, "'POINT(0 91)'"));
    assert(parseLiteral(ColumnType.geo, "'POINT(181 91)'") == Value("POINT(181 91)"));
    foreach (type; [ColumnType.date, ColumnType.dateTime, ColumnType.time, ColumnType.guid, ColumnType.duration])
        assertThrown(parseLiteral(type, "unquoted"));
}

unittest {
    import std.exception : assertThrown;

    auto n = Value(5L);
    assert(*n.peek!long == 5 && n.peek!double is null && n.peek!Null is null);
    *n.peek!long = 6; // peek zeigt auf den Inhalt, nicht auf eine Kopie
    assert(n == Value(6L));

    assert(Value(5L).get!long == 5 && Value(5L).get!double == 5.0 && Value("a").get!string == "a");
    assertThrown(Value("a").get!long);
    assertThrown(Value(1.5).get!long); // nur implizite Umwandlungen

    assert(compareValues(Value(1L), Value(1.5)) < 0 && compareValues(Value(2.0), Value(2L)) == 0);
    assert(compareValues(Value("a"), Value("b")) < 0 && compareValues(Value(false), Value(true)) < 0);
    assert(compareValues(nullValue, Value(-1L)) < 0 && compareValues(nullValue, nullValue) == 0);
    assertThrown(compareValues(Value("a"), Value(1L)));
}
