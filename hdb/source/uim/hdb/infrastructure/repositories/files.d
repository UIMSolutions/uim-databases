module uim.hdb.infrastructure.repositories.files;

import uim.hdb;
import std.algorithm : findSplit, map;
import std.array : appender, array, join, replace, split;
import std.conv : to;
import std.exception : enforce;

/// Tabellen als kompakte Textdateien (<name>.tbl):
///   Zeile 1  HDBTABLE 1
///   Zeile 2  Tabellenname
///   Zeile 3  spalte:TYP, durch Tabulatoren getrennt
///   danach   eine Zeile je Datensatz, Felder durch Tabulatoren getrennt; \N ist NULL,
///            in Text sind \\, \t, \n und \r maskiert
final class FileTableRepository : SnapshotTableRepository {
    private enum header = "HDBTABLE 1";

    this(string directory) {
        super(directory, "tbl");
        loadAll();
    }

    protected override string encode(ColumnTable t) {
        auto out_ = appender!string;
        out_ ~= header ~ "\n" ~ t.name ~ "\n";
        out_ ~= t.defs.map!(d => d.name ~ ":" ~ typeName(d.type)).join("\t") ~ "\n";
        foreach (row; t.liveRows()) {
            foreach (c; 0 .. t.defs.length) {
                if (c)
                    out_ ~= "\t";
                out_ ~= field(t.value(c, row));
            }
            out_ ~= "\n";
        }
        return out_[];
    }

    protected override ColumnTable decode(string content) {
        auto lines = content.split("\n");
        enforce(lines.length >= 4 && lines[0] == header && lines[$ - 1] == "", "Ungültige Tabellendatei");
        ColumnDef[] defs;
        foreach (part; lines[2].split("\t")) {
            auto p = part.findSplit(":");
            enforce(p[0].length && p[2].length, "Ungültige Spaltendefinition: " ~ part);
            defs ~= ColumnDef(p[0], parseTypeName(p[2]));
        }
        auto table = new ColumnTable(lines[1], defs, TableStorage.file);
        foreach (line; lines[3 .. $ - 1]) {
            auto fields = line.split("\t");
            if (fields.length == 0)
                fields = [""]; // eine einzelne Textspalte mit Leerstring
            enforce(fields.length == defs.length, "Ungültige Zeile in Tabelle " ~ lines[1]);
            Value[] row;
            foreach (i, f; fields)
                row ~= parseField(defs[i].type, f);
            table.insert(row);
        }
        return table;
    }
}

private string field(Value v) {
    if (isNull(v))
        return `\N`;
    if (auto s = v.peek!string)
        return (*s).replace(`\`, `\\`).replace("\t", `\t`).replace("\n", `\n`).replace("\r", `\r`);
    return valueText(v);
}

private Value parseField(ColumnType type, string text) {
    if (text == `\N`)
        return nullValue;
    return valueFromInput(type, unescape(text));
}

private string unescape(string s) {
    auto result = appender!string;
    for (size_t i = 0; i < s.length; ++i) {
        if (s[i] != '\\' || i + 1 == s.length) {
            result ~= s[i];
            continue;
        }
        ++i;
        result ~= s[i] == 't' ? '\t' : s[i] == 'n' ? '\n' : s[i] == 'r' ? '\r' : s[i];
    }
    return result[];
}
