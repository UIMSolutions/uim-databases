/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.shell;

import uim.hdb;
import uim.hdb.presentation.cli.format;
import uim.hdb.presentation.cli.interfaces;
import uim.hdb.presentation.cli.statements;

import core.time : MonoTime;
import std.algorithm : among, startsWith;
import std.array : split;
import std.conv : to;
import std.string : indexOf, splitLines, strip, toLower, toUpper;

@safe:

/// Eingehender Adapter: interaktive SQL-Shell und Skriptausführung über ISqlUseCase.
/// Anweisungen enden mit `;`, Befehle der Shell beginnen mit `\` und gelten für eine Zeile (siehe `help`).
/// Eine mit BEGIN geöffnete Transaktion merkt sich die Shell: folgende Anweisungen laufen darin bis COMMIT oder ROLLBACK.
final class CliShell {
    enum help = `Statements end with ';' and may span several lines.
Shell commands:
  \q, \quit, exit       leave the shell (an open transaction is rolled back)
  \h, \?, help          show this help
  \dt                   list tables
  \stats [table]        table statistics, or the columns of one table
  \format [table|csv|json]  show or set the output format
  \timing [on|off]      show the time each statement takes
  \tx                   show the open transaction
  \checkpoint           write all tables to their storage and truncate the log
  \merge                run the delta merge now
  \i FILE               run the statements in FILE
`;

    private ISqlUseCase sql;
    private ICliOutput output;
    private CliFormat _format;
    private bool timing;
    private string _transaction;
    private bool quitRequested;
    /// Bricht Skripte (run, runScript, \i) beim ersten Fehler ab. Interaktiv geht es immer weiter.
    bool stopOnError = true;
    /// Liest Dateien für \i; austauschbar für Tests.
    string delegate(string path) @safe readFile;

    this(ISqlUseCase sql, ICliOutput output, CliFormat format = CliFormat.table) {
        this.sql = sql;
        this.output = output;
        _format = format;
        readFile = (string path) => readFileText(path);
    }

    CliFormat format() const {
        return _format;
    }

    /// Kennung der offenen Transaktion; leer, wenn keine offen ist.
    string transaction() const {
        return _transaction;
    }

    /// Liest bis zum Ende der Eingabe oder bis \q. Exit-Code: 0, oder 1, wenn eine Anweisung fehlschlug.
    int run(ICliInput input) {
        quitRequested = false;
        StatementBuffer buffer;
        bool failed;
        immutable interactive = input.interactive;
        if (interactive)
            output.error("hdb shell. Type \\h for help, \\q to quit.\n");
        while (!quitRequested) {
            auto line = input.readLine(prompt(buffer.incomplete));
            if (line is null)
                break;
            // Befehle nur am Anfang einer Anweisung, damit ein '\' in einem Text keiner wird
            if (!buffer.incomplete && isCommand(line)) {
                if (!command(line.strip))
                    failed = true;
            } else
                foreach (statement; buffer.feed(line))
                    if (!execute(statement))
                        failed = true;
            if (failed && stopOnError && !interactive)
                break;
        }
        if (!(failed && stopOnError && !interactive)) {
            auto rest = buffer.flush();
            if (rest.length && !quitRequested && !execute(rest)) // letzte Anweisung einer Datei ohne ';'
                failed = true;
        }
        rollbackOpen();
        return failed ? 1 : 0;
    }

    /// Führt einen ganzen Text aus (Option -c, Datei). Gibt false zurück, wenn etwas fehlschlug.
    bool runScript(string text) {
        quitRequested = false; // \q im Skript beendet es und, über \i, auch das aufrufende
        StatementBuffer buffer;
        bool ok = true;
        foreach (line; text.splitLines) {
            if (quitRequested)
                break;
            if (!buffer.incomplete && isCommand(line))
                ok &= command(line.strip);
            else
                foreach (statement; buffer.feed(line))
                    ok &= execute(statement);
            if (!ok && stopOnError)
                return false;
        }
        auto rest = buffer.flush();
        if (rest.length && !quitRequested)
            ok &= execute(rest);
        return ok;
    }

    /// Führt eine Anweisung aus und gibt das Ergebnis aus. false bei einem Fehler, der dann nach `error` geht.
    bool execute(string statement) {
        try {
            immutable start = MonoTime.currTime;
            auto r = sql.executeIn(_transaction, statement);
            immutable elapsed = MonoTime.currTime - start;
            track(statement, r);
            output.write(formatResult(r, _format));
            if (timing)
                output.error("Time: " ~ (elapsed.total!"usecs" / 1000.0).to!string ~ " ms\n");
            return true;
        } catch (Exception e) {
            output.error("ERROR: " ~ e.msg ~ "\n");
            return false;
        }
    }

    /// Führt einen Befehl der Shell aus. false bei einem Fehler.
    bool command(string line) {
        auto space = line.indexOf(' ');
        auto name = (space < 0 ? line : line[0 .. space]).toLower;
        auto argument = space < 0 ? "" : line[space + 1 .. $].strip;
        try {
            switch (name) {
            case `\q`, `\quit`, "exit", "quit":
                quitRequested = true;
                return true;
            case `\h`, `\?`, `\help`, "help":
                output.write(help);
                return true;
            case `\dt`:
                auto tables = sql.listTables();
                foreach (t; tables)
                    output.write(t ~ "\n");
                if (tables.length == 0)
                    output.error("No tables.\n");
                return true;
            case `\stats`:
                output.write(formatStats(sql.stats(), _format, argument));
                return true;
            case `\format`:
                if (argument.length)
                    _format = parseCliFormat(argument);
                output.error("Output format is " ~ _format.to!string ~ ".\n");
                return true;
            case `\timing`:
                if (argument.length == 0)
                    timing = !timing;
                else if (argument.toLower.among("on", "true", "1"))
                    timing = true;
                else if (argument.toLower.among("off", "false", "0"))
                    timing = false;
                else
                    throw new Exception(`Use \timing on or \timing off`);
                output.error("Timing is " ~ (timing ? "on" : "off") ~ ".\n");
                return true;
            case `\tx`:
                output.error(_transaction.length ? "Open transaction: " ~ _transaction ~ "\n"
                        : "No open transaction.\n");
                return true;
            case `\checkpoint`:
                sql.checkpoint();
                output.error("Checkpoint written.\n");
                return true;
            case `\merge`:
                sql.mergeDelta();
                auto status = sql.mergeStatus();
                output.error("Delta merge done" ~ (status.lastError.length ? ": " ~ status.lastError : ".") ~ "\n");
                return status.lastError.length == 0;
            case `\i`, `\include`:
                if (argument.length == 0)
                    throw new Exception(`Use \i FILE`);
                return runScript(readFile(argument));
            default:
                throw new Exception("Unknown command " ~ name ~ `; \h shows all commands`);
            }
        } catch (Exception e) {
            output.error("ERROR: " ~ e.msg ~ "\n");
            return false;
        }
    }

    /// Eine offene Transaktion zurückrollen, damit sie die Datenbank nicht weiter sperrt.
    void rollbackOpen() {
        if (_transaction.length == 0)
            return;
        try
            sql.executeIn(_transaction, "ROLLBACK");
        catch (Exception) {
        }
        output.error("Open transaction rolled back.\n");
        _transaction = "";
    }

    private string prompt(bool continuation) const {
        if (continuation)
            return "   ...> ";
        return _transaction.length ? "hdb(tx)> " : "hdb> ";
    }

    private static bool isCommand(string line) {
        auto text = line.strip;
        return text.startsWith(`\`) || text.toLower.among("exit", "quit", "help");
    }

    /// BEGIN liefert die Kennung der Transaktion, COMMIT und ROLLBACK beenden sie.
    private void track(string statement, QueryResult r) {
        if (r.transaction.length) {
            _transaction = r.transaction;
            return;
        }
        auto words = statement.strip.split;
        if (words.length && words[0].toUpper.among("COMMIT", "ROLLBACK", "END"))
            _transaction = "";
    }
}

private string readFileText(string path) {
    import std.file : readText;

    return readText(path);
}

version (unittest) {
    final class BufferOutput : ICliOutput {
        string written, errors;

        void write(string text) {
            written ~= text;
        }

        void error(string text) {
            errors ~= text;
        }
    }

    final class LinesInput : ICliInput {
        string[] lines;
        string[] prompts;
        bool isInteractive;

        this(string[] lines, bool isInteractive = false) {
            this.lines = lines;
            this.isInteractive = isInteractive;
        }

        string readLine(string prompt) {
            prompts ~= prompt;
            if (lines.length == 0)
                return null;
            auto line = lines[0];
            lines = lines[1 .. $];
            return line;
        }

        bool interactive() const {
            return isInteractive;
        }
    }
}

unittest {
    import std.algorithm : canFind;

    auto output = new BufferOutput;
    auto shell = new CliShell(new SqlService(new MemoryTableRepository), output);

    // Mehrzeilige Anweisungen, Befehle und das Ende ohne ';'
    auto input = new LinesInput([
        "CREATE TABLE t (id INTEGER, name VARCHAR);",
        "INSERT INTO t",
        "  VALUES (1, 'a;b'); INSERT INTO t VALUES (2, NULL);",
        `\dt`,
        "SELECT * FROM t ORDER BY id"
    ]);
    assert(shell.run(input) == 0, output.errors);
    assert(output.written.canFind("t\n"));
    assert(output.written.canFind("| 1  | a;b  |") || output.written.canFind("|  1 | a;b  |"), output.written);
    assert(output.written.canFind("(2 rows)"));

    // Ein Fehler bricht ein Skript ab
    output.written = output.errors = "";
    assert(shell.run(new LinesInput(["SELEC 1;", "SELECT * FROM t;"])) == 1);
    assert(output.errors.canFind("ERROR") && !output.written.canFind("rows"));

    // Interaktiv geht es weiter, und der Prompt zeigt Fortsetzung und Transaktion
    output.written = output.errors = "";
    auto interactive = new LinesInput([
        "SELEC 1;", "BEGIN;", "INSERT INTO t", "VALUES (3, 'c');", `\tx`, "ROLLBACK;", `\q`, "SELECT 1;"
    ], true);
    assert(shell.run(interactive) == 1);
    assert(interactive.prompts == ["hdb> ", "hdb> ", "hdb(tx)> ", "   ...> ", "hdb(tx)> ", "hdb(tx)> ", "hdb> "],
        interactive.prompts.to!string);
    assert(interactive.lines == ["SELECT 1;"]); // nach \q nicht weitergelesen
    assert(output.errors.canFind("Open transaction: "));
    assert(shell.transaction == "");

    // Formate
    output.written = "";
    assert(shell.command(`\format csv`) && shell.format == CliFormat.csv);
    assert(shell.execute("SELECT id FROM t ORDER BY id"));
    assert(output.written == "id\n1\n2\n", output.written);
    assert(!shell.command(`\format xml`));
    assert(!shell.command(`\nope`));

    // Statistik einer Tabelle und unbekannte Tabelle
    output.written = "";
    assert(shell.command(`\stats t`) && output.written.canFind("name,"));
    assert(!shell.command(`\stats missing`));

    // Skripte mit \i; eine offene Transaktion wird am Ende zurückgerollt
    shell.readFile = (string path) => path == "init.sql" ? "INSERT INTO t VALUES (5, 'e');\n-- Kommentar\n" : null;
    assert(shell.runScript(`\i init.sql`));
    assert(shell.runScript("BEGIN; INSERT INTO t VALUES (6, 'f');"));
    assert(shell.transaction.length);
    output.written = output.errors = "";
    assert(shell.run(new LinesInput([])) == 0);
    assert(output.errors.canFind("rolled back") && shell.transaction == "");
    output.written = "";
    assert(shell.execute("SELECT COUNT(*) FROM t") && output.written.canFind("3"));

    assert(shell.command(`\checkpoint`) && shell.command(`\merge`) && shell.command(`\timing on`));
}
