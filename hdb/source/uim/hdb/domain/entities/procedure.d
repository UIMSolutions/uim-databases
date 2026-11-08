/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Gespeicherte Prozeduren: eine benannte Folge von SQL-Anweisungen mit typisierten Parametern.
///
/// ---
/// CREATE [OR REPLACE] PROCEDURE name ([param TYP, ...]) AS BEGIN anweisung; anweisung; ... END
/// DROP PROCEDURE name
/// CALL name([wert, ...])
/// SHOW PROCEDURES | SHOW PROCEDURE name
/// ---
///
/// Im Rumpf steht `:param` für einen Parameter; beim Aufruf wird dort der Wert als SQL-Literal eingesetzt, passend
/// zum Typ geprüft. In 'Textliteralen' wird nichts ersetzt. Erlaubt sind SELECT, INSERT, UPDATE, DELETE sowie
/// CREATE TABLE und DROP TABLE; Transaktionssteuerung und Prozeduraufrufe nicht.
module uim.hdb.domain.entities.procedure;

import uim.hdb;
import std.algorithm : canFind, map;
import std.array : array, join;
import std.ascii : isAlpha, isAlphaNum, isWhite;
import std.conv : to;
import std.exception : enforce;
import std.regex : ctRegex, matchFirst;
import std.string : strip, toLower, toUpper;

@safe:

/// Parameter einer Prozedur.
struct ProcedureParam {
    string name; // wie angegeben; Vergleich ohne Groß-/Kleinschreibung
    string typeName; // wie angegeben, etwa VARCHAR(40)
    ColumnType type;
}

/// Eine gespeicherte Prozedur.
struct StoredProcedure {
    string name;
    ProcedureParam[] params;
    string[] statements; // Rumpf, je Anweisung ohne abschließendes Semikolon

    /// Kanonische Definition: so steht die Prozedur im Protokoll, in Sicherungen und in SHOW PROCEDURE.
    string definition() const {
        return "CREATE PROCEDURE " ~ name ~ " (" ~ signature ~ ") AS BEGIN " ~ statements.join("; ") ~ " END";
    }

    /// Parameterliste wie "id INTEGER, note VARCHAR(40)".
    string signature() const {
        return params.map!(p => p.name ~ " " ~ p.typeName).join(", ");
    }

    /// Anweisungen mit eingesetzten Argumenten. `args` sind SQL-Literale wie in INSERT ... VALUES.
    string[] bind(string[] args) const {
        enforce(args.length == params.length, "Prozedur " ~ name ~ " erwartet " ~ params.length.to!string
                ~ " Argument(e), nicht " ~ args.length.to!string);
        string[string] literals;
        foreach (i, p; params) {
            try
                literals[p.name.toLower] = toSqlLiteral(parseLiteral(p.type, args[i]));
            catch (Exception e)
                throw new Exception("Argument " ~ p.name ~ " (" ~ p.typeName ~ "): " ~ e.msg);
        }
        return statements.map!(s => substitute(s, literals)).array;
    }
}

/// Ergebnis von parseCreateProcedure.
struct ProcedureDefinition {
    StoredProcedure procedure;
    bool replace; // OR REPLACE
}

/// Liest CREATE [OR REPLACE] PROCEDURE und prüft Namen, Typen, Rumpf und die verwendeten Parameter.
ProcedureDefinition parseCreateProcedure(string sql) {
    auto m = matchFirst(sql.strip, ctRegex!(
            `^CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE\s+(\w+)\s*\((.*?)\)\s*AS\s+BEGIN\s+(.*?);?\s*END$`, "is"));
    enforce(!m.empty,
        "Syntax: CREATE [OR REPLACE] PROCEDURE name ([param TYP, ...]) AS BEGIN anweisung; ... END");
    StoredProcedure p;
    p.name = m[2];
    bool[string] seen;
    foreach (part; splitOutside(m[3], ',')) {
        auto text = part.strip;
        if (text.length == 0 && m[3].strip.length == 0)
            break;
        auto space = indexOfWhite(text);
        enforce(space > 0, "Ungültige Parameterdefinition: " ~ part.strip);
        auto name = text[0 .. space];
        auto typeName = text[space .. $].strip;
        enforce(isIdentifier(name), "Ungültiger Parametername: " ~ name);
        enforce((name.toLower in seen) is null, "Parameter ist doppelt: " ~ name);
        seen[name.toLower] = true;
        p.params ~= ProcedureParam(name, typeName, columnTypeOf(typeName));
    }
    foreach (raw; splitOutside(m[4], ';')) {
        auto s = raw.strip;
        if (s.length)
            p.statements ~= s;
    }
    enforce(p.statements.length, "Eine Prozedur braucht mindestens eine Anweisung");
    foreach (s; p.statements) {
        enforce(isAllowedInProcedure(s),
            "In Prozeduren erlaubt: SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, DROP TABLE; nicht: " ~ firstWords(s));
        foreach (used; parameterNames(s))
            enforce((used.toLower in seen) !is null, "Unbekannter Parameter :" ~ used ~ " in: " ~ s);
    }
    return ProcedureDefinition(p, m[1].length > 0);
}

/// Name aus DROP PROCEDURE name.
string parseDropProcedure(string sql) {
    auto m = matchFirst(sql.strip, ctRegex!(`^DROP\s+PROCEDURE\s+(\w+)$`, "i"));
    enforce(!m.empty, "Syntax: DROP PROCEDURE name");
    return m[1];
}

/// Name und Argumente (als SQL-Literale) aus CALL name(...).
struct ProcedureCall {
    string name;
    string[] args;
}

ProcedureCall parseCall(string sql) {
    auto m = matchFirst(sql.strip, ctRegex!(`^CALL\s+(\w+)\s*(?:\((.*)\))?$`, "is"));
    enforce(!m.empty, "Syntax: CALL name([wert, ...])");
    string[] args;
    if (m[2].strip.length)
        foreach (a; splitOutside(m[2], ','))
            args ~= a.strip;
    return ProcedureCall(m[1], args);
}

/// Ob die Anweisung eine Prozedur anlegt, löscht, aufruft oder zeigt.
bool isProcedureStatement(string sql) {
    return !matchFirst(sql, ctRegex!(`^\s*(CREATE\s+(OR\s+REPLACE\s+)?PROCEDURE|DROP\s+PROCEDURE|CALL|SHOW\s+PROCEDURES?)\b`,
            "i")).empty;
}

private bool isAllowedInProcedure(string s) {
    return !matchFirst(s, ctRegex!(`^(SELECT|INSERT|UPDATE|DELETE|CREATE\s+TABLE|DROP\s+TABLE)\b`, "i")).empty;
}

private string firstWords(string s) {
    auto m = matchFirst(s, ctRegex!(`^\S+(\s+\S+)?`));
    return m.empty ? s : m[0];
}

/// Teilt an `sep` außerhalb von 'Textliteralen' und Klammern.
private string[] splitOutside(string s, char sep) {
    string[] result;
    size_t start;
    bool quoted;
    int depth;
    foreach (i, c; s) {
        if (c == '\'')
            quoted = !quoted;
        else if (!quoted && c == '(')
            ++depth;
        else if (!quoted && c == ')')
            --depth;
        else if (!quoted && depth == 0 && c == sep) {
            result ~= s[start .. i];
            start = i + 1;
        }
    }
    enforce(!quoted, "Textliteral ohne schließendes Hochkomma");
    result ~= s[start .. $];
    return result;
}

/// Namen aller `:param` außerhalb von Textliteralen.
private string[] parameterNames(string s) {
    string[] names;
    bool quoted;
    for (size_t i = 0; i < s.length; ++i) {
        if (s[i] == '\'')
            quoted = !quoted;
        else if (!quoted && s[i] == ':' && i + 1 < s.length && (isAlpha(s[i + 1]) || s[i + 1] == '_')) {
            auto end = i + 1;
            while (end < s.length && (isAlphaNum(s[end]) || s[end] == '_'))
                ++end;
            names ~= s[i + 1 .. end];
            i = end - 1;
        }
    }
    return names;
}

/// Ersetzt `:param` außerhalb von Textliteralen durch das Literal.
private string substitute(string s, const string[string] literals) {
    string result;
    bool quoted;
    for (size_t i = 0; i < s.length; ++i) {
        if (s[i] == '\'')
            quoted = !quoted;
        else if (!quoted && s[i] == ':' && i + 1 < s.length && (isAlpha(s[i + 1]) || s[i + 1] == '_')) {
            auto end = i + 1;
            while (end < s.length && (isAlphaNum(s[end]) || s[end] == '_'))
                ++end;
            auto literal = s[i + 1 .. end].toLower in literals;
            enforce(literal !is null, "Unbekannter Parameter :" ~ s[i + 1 .. end]);
            result ~= *literal;
            i = end - 1;
            continue;
        }
        result ~= s[i];
    }
    return result;
}

private bool isIdentifier(string s) {
    import std.algorithm : all;

    return s.length && (isAlpha(s[0]) || s[0] == '_') && s.all!(c => isAlphaNum(c) || c == '_');
}

private ptrdiff_t indexOfWhite(string s) {
    foreach (i, c; s)
        if (isWhite(c))
            return i;
    return -1;
}

unittest {
    import std.exception : assertThrown;

    auto d = parseCreateProcedure("create or replace procedure pay (id INTEGER, note VARCHAR(40), amount DECIMAL)
        AS BEGIN
          UPDATE orders SET paid = TRUE, note = :note WHERE id = :id;
          INSERT INTO log VALUES (:ID, 'paid: :id', :amount);
          SELECT * FROM orders WHERE id = :id;
        END");
    assert(d.replace);
    auto p = d.procedure;
    assert(p.name == "pay" && p.params.length == 3 && p.params[1].typeName == "VARCHAR(40)");
    assert(p.statements.length == 3);
    assert(p.signature == "id INTEGER, note VARCHAR(40), amount DECIMAL");
    assert(parseCreateProcedure(p.definition).procedure == p); // die Definition liest sich zurück

    auto bound = p.bind(["7", "'it''s; done'", "12.50"]);
    assert(bound[0] == "UPDATE orders SET paid = TRUE, note = 'it''s; done' WHERE id = 7", bound[0]);
    assert(bound[1] == "INSERT INTO log VALUES (7, 'paid: :id', 12.5)", bound[1]); // im Literal bleibt :id
    assert(p.bind(["NULL", "NULL", "NULL"])[0] == "UPDATE orders SET paid = TRUE, note = NULL WHERE id = NULL");
    assertThrown(p.bind(["7"])); // zu wenige
    assertThrown(p.bind(["'x'", "'a'", "1"])); // kein INTEGER
    assertThrown(p.bind(["1 OR 1=1", "'a'", "1"])); // keine eingeschleusten Ausdrücke
    assertThrown(p.bind(["1", "a' OR 'x", "1"])); // Text nur in Hochkommata

    auto none = parseCreateProcedure("CREATE PROCEDURE cleanup () AS BEGIN DELETE FROM t WHERE done = TRUE END");
    assert(!none.replace && none.procedure.params.length == 0 && none.procedure.bind([]).length == 1);

    assertThrown(parseCreateProcedure("CREATE PROCEDURE x (a INTEGER) AS BEGIN SELECT :b FROM t END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x (a INTEGER, A INTEGER) AS BEGIN SELECT 1 FROM t END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x (a NOPE) AS BEGIN SELECT 1 FROM t END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x () AS BEGIN COMMIT END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x () AS BEGIN CALL y() END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x () AS BEGIN CREATE PROCEDURE y () AS BEGIN SELECT 1 FROM t END END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x () AS BEGIN END"));
    assertThrown(parseCreateProcedure("CREATE PROCEDURE x () AS BEGIN SELECT 'open FROM t END"));

    assert(parseDropProcedure(" drop procedure pay ") == "pay");
    assert(parseCall("CALL pay(7, 'a, b', NULL)") == ProcedureCall("pay", ["7", "'a, b'", "NULL"]));
    assert(parseCall("call cleanup()") == ProcedureCall("cleanup", null));
    assert(parseCall("CALL cleanup") == ProcedureCall("cleanup", null));
    assert(isProcedureStatement("call x()") && isProcedureStatement("SHOW PROCEDURES")
            && isProcedureStatement("CREATE OR REPLACE PROCEDURE x") && !isProcedureStatement("CREATE TABLE p (a INTEGER)"));
}
