/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.format;

import uim.hdb;

import std.algorithm : any, map, max;
import std.array : appender, array, replicate;
import std.conv : to;
import std.exception : enforce;
import std.range : walkLength;
import std.string : toLower;
import vibe.data.json : Json, serializeToJson;

@safe:

/// Ausgabeformat der Shell.
enum CliFormat {
    table, /// Tabelle mit Rahmen, für Menschen
    csv, /// RFC 4180, NULL als leeres Feld
    json /// dieselbe Darstellung wie die REST-API
}

CliFormat parseCliFormat(string name) {
    switch (name.toLower) {
    case "table":
        return CliFormat.table;
    case "csv":
        return CliFormat.csv;
    case "json":
        return CliFormat.json;
    default:
        throw new Exception("Unknown format '" ~ name ~ "' (table, csv or json)");
    }
}

/// Eine Zelle als Text. NULL wird `nullText`; NUMERIC bleibt exakt.
string cellText(Value v, string nullText = "NULL") {
    if (auto l = v.peek!long)
        return (*l).to!string;
    if (auto d = v.peek!double)
        return (*d).to!string;
    if (auto s = v.peek!string)
        return *s;
    if (auto b = v.peek!bool)
        return *b ? "TRUE" : "FALSE";
    if (auto e = v.peek!Exact)
        return e.text;
    return nullText;
}

/// Zahlen stehen in der Tabelle rechtsbündig.
private bool numeric(Value v) {
    return v.peek!long !is null || v.peek!double !is null || v.peek!Exact !is null;
}

/// Ergebnis einer Anweisung im gewünschten Format, mit Zeilenende.
string formatResult(QueryResult r, CliFormat format) {
    final switch (format) {
    case CliFormat.json:
        return serializeToJson(toRest(r)).toPrettyString ~ "\n";
    case CliFormat.csv:
        if (r.columns.length == 0)
            return summary(r);
        return formatCsv(r.columns, r.rows.map!(row => row.map!(v => cellText(v, "")).array).array);
    case CliFormat.table:
        if (r.columns.length == 0)
            return summary(r);
        auto cells = r.rows.map!(row => row.map!(v => cellText(v)).array).array;
        auto right = new bool[r.columns.length];
        foreach (row; r.rows)
            foreach (i, v; row)
                if (i < right.length && numeric(v))
                    right[i] = true;
        return formatTable(r.columns, cells, right)
            ~ "(" ~ rowCount(r.rows.length) ~ ")\n";
    }
}

/// Meldung einer Anweisung ohne Ergebnismenge.
private string summary(QueryResult r) {
    if (r.message.length)
        return r.message ~ "\n";
    return "OK, " ~ rowCount(r.affected) ~ " affected\n";
}

private string rowCount(T)(T n) {
    return n.to!string ~ (n == 1 ? " row" : " rows");
}

/// Tabelle mit Rahmen. `right` markiert rechtsbündige Spalten; fehlt es, ist alles linksbündig.
string formatTable(string[] header, string[][] rows, bool[] right = null) {
    auto widths = header.map!(h => h.walkLength).array;
    foreach (row; rows)
        foreach (i, cell; row)
            if (i < widths.length)
                widths[i] = max(widths[i], cell.walkLength);

    auto result = appender!string;
    void line() {
        foreach (w; widths)
            result.put("+" ~ "-".replicate(w + 2));
        result.put("+\n");
    }

    void cells(string[] values, bool alignRight) {
        foreach (i, w; widths) {
            auto text = i < values.length ? values[i] : "";
            auto pad = " ".replicate(w - text.walkLength);
            immutable r = alignRight && i < right.length && right[i];
            result.put("| " ~ (r ? pad ~ text : text ~ pad) ~ " ");
        }
        result.put("|\n");
    }

    line();
    cells(header, false);
    line();
    foreach (row; rows)
        cells(row, true);
    if (rows.length)
        line();
    return result.data;
}

/// CSV mit Kopfzeile; Felder mit Komma, Anführungszeichen oder Zeilenumbruch stehen in Anführungszeichen.
string formatCsv(string[] header, string[][] rows) {
    auto result = appender!string;
    void put(string[] values) {
        foreach (i, v; values) {
            if (i)
                result.put(",");
            if (v.any!(c => c == ',' || c == '"' || c == '\n' || c == '\r'))
                result.put(`"` ~ v.replace(`"`, `""`) ~ `"`);
            else
                result.put(v);
        }
        result.put("\n");
    }

    put(header);
    foreach (row; rows)
        put(row);
    return result.data;
}

private string replace(string text, string from, string to) {
    import std.array : replace;

    return text.replace(from, to);
}

/// Übersicht der Tabellen (\stats) oder, mit `detail`, die Spalten einer Tabelle.
string formatStats(TableStats[] stats, CliFormat format, string detail = "") {
    if (detail.length) {
        foreach (t; stats)
            if (t.table == detail)
                return formatColumns(t, format);
        throw new Exception("No such table: " ~ detail);
    }
    if (format == CliFormat.json)
        return serializeToJson(stats.map!(t => toRest(t)).array).toPrettyString ~ "\n";
    string[] header = ["table", "storage", "rows", "deleted", "columns"];
    auto rows = stats.map!(t => [t.table, storageName(t.storage), t.rows.to!string, t.deletedRows.to!string,
            t.columns.length.to!string]).array;
    return format == CliFormat.csv ? formatCsv(header, rows)
        : formatTable(header, rows, [false, false, true, true, true]);
}

private string formatColumns(TableStats t, CliFormat format) {
    if (format == CliFormat.json)
        return serializeToJson(toRest(t)).toPrettyString ~ "\n";
    string[] header = ["column", "type", "rows", "main", "delta", "main distinct", "delta distinct"];
    auto rows = t.columns.map!(c => [c.name, typeName(c.type), c.rows.to!string, c.mainRows.to!string,
            c.deltaRows.to!string, c.mainDistinct.to!string, c.deltaDistinct.to!string]).array;
    return format == CliFormat.csv ? formatCsv(header, rows)
        : formatTable(header, rows, [false, false, true, true, true, true, true]);
}

unittest {
    assert(parseCliFormat("CSV") == CliFormat.csv);
    import std.exception : assertThrown;

    assertThrown(parseCliFormat("xml"));

    assert(cellText(Value(uim.hdb.domain.value.Null())) == "NULL" && cellText(Value(uim.hdb.domain.value.Null()), "") == "");
    assert(cellText(Value(Exact("1.50"))) == "1.50" && cellText(Value(true)) == "TRUE");

    auto r = QueryResult(["id", "name"], [[Value(1L), Value("äb")], [Value(10L), Value(uim.hdb.domain.value.Null())]]);
    assert(formatResult(r, CliFormat.table) ==
        "+----+------+\n"
        ~ "| id | name |\n"
        ~ "+----+------+\n"
        ~ "|  1 | äb   |\n"
        ~ "| 10 | NULL |\n"
        ~ "+----+------+\n"
        ~ "(2 rows)\n");
    assert(formatResult(r, CliFormat.csv) == "id,name\n1,äb\n10,\n");
    assert(formatCsv(["a"], [[`x,"y"`]]) == "a\n\"x,\"\"y\"\"\"\n");
    assert(formatResult(QueryResult(null, null, 1), CliFormat.table) == "OK, 1 row affected\n");
    assert(formatResult(QueryResult(null, null, 0, "Table created"), CliFormat.csv) == "Table created\n");
    import std.algorithm : canFind;

    assert(formatResult(r, CliFormat.json).canFind(`"columns"`));
}
