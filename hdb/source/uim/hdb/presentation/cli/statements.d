/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.statements;

import std.array : appender, Appender;
import std.string : strip;

@safe:

/// Sammelt Eingabezeilen zu Anweisungen. Eine Anweisung endet mit `;` außerhalb von '…' und "…";
/// Kommentare mit `--` bis zum Zeilenende fallen weg. Eine Anweisung darf über mehrere Zeilen gehen.
struct StatementBuffer {
    private Appender!string pending;
    private char quote = 0; // 0, '\'' oder '"' (char.init wäre 0xFF)

    /// Nimmt eine Zeile auf und gibt die damit vollständigen Anweisungen zurück, ohne `;`.
    string[] feed(string line) {
        string[] complete;
        for (size_t i = 0; i < line.length; i++) {
            immutable c = line[i];
            if (quote) {
                pending.put(c);
                if (c == quote) // '' und "" sind maskierte Anführungszeichen und schließen gleich wieder auf
                    quote = 0;
                continue;
            }
            if (c == '-' && i + 1 < line.length && line[i + 1] == '-')
                break;
            if (c == ';') {
                auto statement = pending.data.strip;
                if (statement.length)
                    complete ~= statement;
                pending = appender!string;
                continue;
            }
            if (c == '\'' || c == '"')
                quote = c;
            pending.put(c);
        }
        if (pending.data.length)
            pending.put('\n');
        return complete;
    }

    /// true, solange eine angefangene Anweisung auf ihr `;` wartet.
    bool incomplete() const {
        return quote != 0 || pending.data.strip.length > 0;
    }

    /// Rest ohne abschließendes `;`, etwa am Ende einer Datei. Leert den Puffer.
    string flush() {
        auto rest = pending.data.strip;
        pending = appender!string;
        quote = 0;
        return rest;
    }
}

unittest {
    StatementBuffer b;
    assert(b.feed("SELECT 1; SELECT 2;") == ["SELECT 1", "SELECT 2"]);
    assert(!b.incomplete);

    assert(b.feed("SELECT * -- Kommentar; kein Ende").length == 0);
    assert(b.incomplete);
    assert(b.feed("FROM t;") == ["SELECT * \nFROM t"]);

    // Semikolon und -- in Text und Bezeichnern zählen nicht
    assert(b.feed("INSERT INTO t VALUES ('a;b', 'it''s -- x');") == ["INSERT INTO t VALUES ('a;b', 'it''s -- x')"]);
    assert(b.feed(`SELECT "a;b" FROM t;`) == [`SELECT "a;b" FROM t`]);

    // Text über mehrere Zeilen
    assert(b.feed("INSERT INTO t VALUES ('first").length == 0);
    assert(b.incomplete);
    assert(b.feed("second');") == ["INSERT INTO t VALUES ('first\nsecond')"]);

    assert(b.feed(";;  ;").length == 0);
    assert(b.feed("SELECT 3").length == 0);
    assert(b.flush() == "SELECT 3" && !b.incomplete);
}
