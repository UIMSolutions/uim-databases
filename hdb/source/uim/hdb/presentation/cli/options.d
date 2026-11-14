/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.cli.options;

import uim.hdb.presentation.cli.format;

import std.algorithm : findSplit, startsWith;
import std.exception : enforce;

@safe:

/// Aufrufparameter von hdb-cli.
struct CliOptions {
    /// Verzeichnis der Datenbank (Aufbau wie ein Mandant: tables/, hdb.log, backups/); leer: im Speicher.
    string database;
    bool memory;
    /// Client-Betrieb: Unix-Socket eines laufenden Servers statt eines Verzeichnisses.
    string socket;
    /// Anmeldung im Client-Betrieb; ohne Benutzer gilt HDB_USER bzw. das Token aus HDB_TOKEN.
    string user;
    /// Mandant der Anmeldung; leer: default.
    string tenant;
    /// Anweisungen aus -c, in dieser Reihenfolge vor den Dateien.
    string[] commands;
    /// Skripte aus -f; "-" ist die Standardeingabe.
    string[] files;
    CliFormat format = CliFormat.table;
    /// Nach einem Fehler in -c oder -f weitermachen.
    bool continueOnError;
    bool help;

    /// Ohne -c und -f startet die Shell auf der Standardeingabe.
    bool interactive() const {
        return commands.length == 0 && files.length == 0;
    }
}

/// Wertet die Argumente ohne den Programmnamen aus. Wirft bei unbekannten oder unvollständigen Optionen.
CliOptions parseCliOptions(string[] args) {
    CliOptions options;
    for (size_t i = 0; i < args.length; i++) {
        auto arg = args[i];
        string value;
        bool inline;
        // --name=wert
        if (arg.startsWith("--"))
            if (auto parts = arg.findSplit("="))
                if (parts[1].length) {
                    arg = parts[0];
                    value = parts[2];
                    inline = true;
                }

        string next() {
            if (inline)
                return value;
            enforce(i + 1 < args.length, "Option " ~ arg ~ " needs a value");
            return args[++i];
        }

        switch (arg) {
        case "-d", "--db", "--database":
            options.database = next();
            enforce(options.database.length, "Option " ~ arg ~ " needs a directory");
            break;
        case "-m", "--memory":
            options.memory = true;
            break;
        case "-s", "--socket":
            options.socket = next();
            enforce(options.socket.length, "Option " ~ arg ~ " needs a socket path");
            break;
        case "-u", "--user":
            options.user = next();
            break;
        case "-t", "--tenant":
            options.tenant = next();
            break;
        case "-c", "--command":
            options.commands ~= next();
            break;
        case "-f", "--file":
            options.files ~= next();
            break;
        case "-F", "--format":
            options.format = parseCliFormat(next());
            break;
        case "--csv":
            options.format = CliFormat.csv;
            break;
        case "--json":
            options.format = CliFormat.json;
            break;
        case "-k", "--continue-on-error":
            options.continueOnError = true;
            break;
        case "-h", "--help":
            options.help = true;
            break;
        default:
            // Ein einzelnes Argument ohne Strich ist das Verzeichnis, wie bei sqlite3
            enforce(!arg.startsWith("-") && options.database.length == 0, "Unknown argument: " ~ arg);
            options.database = arg;
        }
    }
    enforce(!(options.memory && options.database.length), "Use either --memory or a database directory, not both");
    enforce(options.socket.length == 0 || (!options.memory && options.database.length == 0),
        "--socket connects to a server; it cannot be combined with --memory or a database directory");
    enforce(options.socket.length || (options.user.length == 0 && options.tenant.length == 0),
        "--user and --tenant need --socket");
    return options;
}

string cliUsage(string program) {
    return "Usage: " ~ program ~ ` [options] [DIRECTORY]
       ` ~ program ~ ` --socket PATH [--user NAME] [--tenant NAME] [options]

Local mode: opens the database in DIRECTORY (created if missing) and runs SQL against it, without a server.
The directory has the same layout as a tenant of the server; only one process may open it at a time,
so stop the server or use a copy. Without a directory, the database lives in memory.

Client mode (--socket): connects to a running server through its Unix socket (server setting UNIX_SOCKET).
Login, roles and audit apply as over HTTP. The password comes from HDB_PASSWORD or is asked for; instead of
logging in, HDB_TOKEN can hold the token of an existing session. HDB_USER is the default for --user.

Options:
  -d, --db DIRECTORY        database directory
  -m, --memory              volatile database in memory
  -s, --socket PATH         client mode: Unix socket of a running server
  -u, --user NAME           client mode: user to log in as
  -t, --tenant NAME         client mode: tenant of the user (default: default)
  -c, --command SQL         run SQL and exit (repeatable)
  -f, --file FILE           run the statements in FILE and exit (repeatable, - for stdin)
  -F, --format FORMAT       output format: table (default), csv or json
      --csv, --json         short for --format csv / --format json
  -k, --continue-on-error   keep going after a failing statement in -c or -f
  -h, --help                show this help

Inside the shell, \h lists the shell commands.
`;
}

unittest {
    import std.exception : assertThrown;

    auto o = parseCliOptions(["--db=data/x", "-c", "SELECT 1", "--file", "a.sql", "--csv", "-k"]);
    assert(o.database == "data/x" && o.commands == ["SELECT 1"] && o.files == ["a.sql"]);
    assert(o.format == CliFormat.csv && o.continueOnError && !o.interactive);

    assert(parseCliOptions(["mydb"]).database == "mydb");
    assert(parseCliOptions([]).interactive);
    assert(parseCliOptions(["-F", "json"]).format == CliFormat.json);
    assert(parseCliOptions(["-h"]).help);

    assertThrown(parseCliOptions(["--nope"]));
    assertThrown(parseCliOptions(["-c"]));
    assertThrown(parseCliOptions(["-F", "xml"]));
    assertThrown(parseCliOptions(["a", "b"]));
    assertThrown(parseCliOptions(["-m", "--db", "x"]));

    auto c = parseCliOptions(["--socket=/run/hdb.sock", "-u", "root", "-t", "acme"]);
    assert(c.socket == "/run/hdb.sock" && c.user == "root" && c.tenant == "acme" && c.interactive);
    assertThrown(parseCliOptions(["-s", "/run/hdb.sock", "data/x"]));
    assertThrown(parseCliOptions(["-s", "/run/hdb.sock", "-m"]));
    assertThrown(parseCliOptions(["-u", "root"]));
}
