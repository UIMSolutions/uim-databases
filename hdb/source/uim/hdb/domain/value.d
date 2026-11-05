module uim.hdb.domain.value;

import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.math : isFinite;
import std.string : replace, strip, toUpper;
import std.variant : Algebraic;

enum ColumnType {
    integer,
    decimal,
    text
}

/// SQL-NULL als eigener Wert.
struct Null {
    int opCmp(const Null) const pure nothrow @nogc @safe {
        return 0;
    }
}

alias Value = Algebraic!(long, double, string, Null);

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
    return a < b ? -1 : (a > b ? 1 : 0);
}

bool valueLess(Value a, Value b) {
    return compareValues(a, b) < 0;
}

/// Wandelt ein SQL-Literal (oder NULL) passend zum Spaltentyp in einen Value um.
Value parseLiteral(ColumnType type, string literal) {
    literal = literal.strip;
    if (literal.toUpper == "NULL")
        return nullValue;
    final switch (type) {
    case ColumnType.integer:
        return Value(literal.to!long);
    case ColumnType.decimal:
        // NaN hat keine Ordnung: das sortierte Dictionary des Merges würde dadurch auch andere Zeilen verfälschen
        auto d = literal.to!double;
        enforce(isFinite(d), "Keine endliche Zahl: " ~ literal);
        return Value(d);
    case ColumnType.text:
        enforce(literal.length >= 2 && literal[0] == '\'' && literal[$ - 1] == '\'',
            "Textliterale müssen in Hochkommata stehen: " ~ literal);
        return Value(literal[1 .. $ - 1].replace("''", "'"));
    }
}

double toDouble(Value v) {
    if (auto l = v.peek!long)
        return *l;
    return *v.peek!double;
}

string typeName(ColumnType t) {
    final switch (t) {
    case ColumnType.integer:
        return "INTEGER";
    case ColumnType.decimal:
        return "DECIMAL";
    case ColumnType.text:
        return "VARCHAR";
    }
}

ColumnType parseTypeName(string name) {
    switch (name) {
    case "INTEGER":
        return ColumnType.integer;
    case "DECIMAL":
        return ColumnType.decimal;
    case "VARCHAR":
        return ColumnType.text;
    default:
        throw new Exception("Unbekannter Typ: " ~ name);
    }
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
    return *v.peek!string;
}

/// SQL-Literal eines Werts; parseLiteral liest es verlustfrei zurück.
string toSqlLiteral(Value v) {
    if (auto s = v.peek!string)
        return "'" ~ (*s).replace("'", "''") ~ "'";
    return valueText(v);
}

/// Wandelt Formulartext (ohne SQL-Quoting) passend zum Spaltentyp in einen Value um.
Value valueFromInput(ColumnType type, string input) {
    final switch (type) {
    case ColumnType.integer:
        try
            return Value(input.strip.to!long);
        catch (Exception)
            throw new Exception("Keine ganze Zahl: " ~ input);
    case ColumnType.decimal:
        double d;
        try
            d = input.strip.to!double;
        catch (Exception)
            throw new Exception("Keine Zahl: " ~ input);
        enforce(isFinite(d), "Keine endliche Zahl: " ~ input);
        return Value(d);
    case ColumnType.text:
        return Value(input);
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
