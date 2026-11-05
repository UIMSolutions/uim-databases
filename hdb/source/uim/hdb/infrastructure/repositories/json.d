module uim.hdb.infrastructure.repositories.json;

import uim.hdb.domain.table;
import uim.hdb.domain.types.tablestorage : TableStorage;
import uim.hdb.domain.value;
import uim.hdb.infrastructure.repositories.snapshot;
import std.array : appender;
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
                out_ ~= jsonValue(t.value(c, row));
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
                row ~= fromJson(d.type, r[i]);
            table.insert(row);
        }
        return table;
    }
}

private string jsonValue(Value v) {
    if (isNull(v))
        return "null";
    if (auto s = v.peek!string)
        return Json(*s).toString;
    return valueText(v);
}

private Value fromJson(ColumnType type, Json j) {
    if (j.type == Json.Type.null_)
        return nullValue;
    final switch (type) {
    case ColumnType.integer:
        return Value(j.get!long);
    case ColumnType.decimal:
        return Value(j.to!double);
    case ColumnType.text:
        return Value(j.get!string);
    }
}
