module uim.hdb.infrastructure.repositories.json;

import uim.hdb;
import std.array : appender;
import std.conv : to;
import std.exception : enforce;
import vibe.data.json : Json, parseJsonString;

/// Tabellen als lesbare JSON-Dateien (<name>.json):
///   {"name": "t", "columns": [{"name": "id", "type": "INTEGER"}], "rows": [[1, "a", null]]}
/// Zahlen schreibt exactText: Json.toString hat nur 16 Stellen und würde manche double verändern.
final class JsonTableRepository : SnapshotTableRepository {
    this(string directory) {
        super(directory, "json");
        loadAll();
    }

    protected override string encode(ColumnTable t) {
        auto out_ = appender!string;
        out_ ~= `{"name": ` ~ Json(t.name).toString ~ `, "columns": [`;
        foreach (i, d; t.defs) {
            if (i)
                out_ ~= ", ";
            out_ ~= `{"name": ` ~ Json(d.name).toString ~ `, "type": "` ~ typeName(d.type) ~ `"}`;
        }
        out_ ~= "],\n" ~ `"rows": [`;
        bool first = true;
        foreach (row; t.liveRows()) {
            out_ ~= first ? "\n[" : ",\n[";
            first = false;
            foreach (c; 0 .. t.defs.length) {
                if (c)
                    out_ ~= ", ";
                out_ ~= tableValueJson(t.value(c, row));
            }
            out_ ~= "]";
        }
        out_ ~= "\n]}\n";
        return out_[];
    }

    protected override ColumnTable decode(string content) {
        auto document = parseJsonString(content);
        ColumnDef[] defs;
        foreach (c; document["columns"])
            defs ~= ColumnDef(c["name"].get!string, parseTypeName(c["type"].get!string));
        auto name = document["name"].get!string;
        auto table = new ColumnTable(name, defs, TableStorage.json);
        foreach (r; document["rows"]) {
            enforce(r.length == defs.length, "Ungültige Zeile in Tabelle " ~ name);
            Value[] row;
            foreach (i, d; defs)
                row ~= tableValueFromJson(d.type, r[i]);
            table.insert(row);
        }
        return table;
    }
}

/// JSON-Text eines Werts mit exakten Zahlen.
string tableValueJson(Value v) {
    if (isNull(v))
        return "null";
    if (auto s = v.peek!string)
        return Json(*s).toString;
    if (auto e = v.peek!Exact)
        return Json(e.text).toString; // als Zahl verlöre Edm.Decimal beim Lesen Stellen
    return valueText(v);
}

Value tableValueFromJson(ColumnType type, Json j) {
    if (j.type == Json.Type.null_)
        return nullValue;
    switch (type) {
    case ColumnType.integer:
        return Value(j.get!long);
    case ColumnType.decimal:
        return Value(j.to!double);
    case ColumnType.text:
        return Value(j.get!string);
    case ColumnType.boolean:
        return Value(j.get!bool);
    case ColumnType.byte_:
    case ColumnType.sbyte:
    case ColumnType.int16:
    case ColumnType.int32:
        return valueFromInput(type, j.get!long.to!string);
    case ColumnType.single:
        return valueFromInput(type, exactText(j.to!double));
    default:
        return valueFromInput(type, j.get!string); // Backups kommen auch von außen: nur gültige Werte übernehmen
    }
}
