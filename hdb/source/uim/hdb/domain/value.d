module uim.hdb.domain.value;

import std.conv : to;
import std.exception : enforce;
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
        return Value(literal.to!double);
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
