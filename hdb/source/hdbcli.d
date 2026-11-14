/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// hdb-cli: SQL-Shell. Lokal läuft die Datenbank wie in uim.hdb.embedded im eigenen Prozess, ohne Anmeldung und
/// Rollen; mit --socket ist hdb-cli Client eines laufenden Servers. dub run --config=cli -- --help
module hdbcli;

import uim.hdb;
import uim.hdb.presentation.cli;

int main(string[] args) @safe {
    auto program = args.length ? baseName(args[0]) : "hdb-cli";
    auto output = new ConsoleOutput;
    CliOptions options;
    try
        options = parseCliOptions(args.length ? args[1 .. $] : null);
    catch (Exception e) {
        output.error(program ~ ": " ~ e.msg ~ "\n\n" ~ cliUsage(program));
        return 2;
    }
    if (options.help) {
        output.write(cliUsage(program));
        return 0;
    }

    ISqlUseCase sql;
    SqlService core; // nur im lokalen Betrieb
    RemoteSqlClient client; // nur im Client-Betrieb
    bool loggedIn;
    if (options.socket.length) {
        client = new RemoteSqlClient(new UnixSocketTransport(options.socket), environment.get("HDB_TOKEN", ""));
        try
            loggedIn = connect(client, options, output);
        catch (Exception e) {
            output.error(program ~ ": " ~ e.msg ~ "\n");
            client.close();
            return 1;
        }
        sql = client;
    } else {
        // Wiederherstellen wie beim Server: Ablage laden, Protokoll nachspielen, Delta zusammenführen
        try {
            if (options.database.length) {
                auto parts = storageIn(options.database);
                core = new SqlService(parts.tables, parts.log);
                core.recover();
                core.mergeDelta();
            } else
                core = new SqlService(new MemoryTableRepository);
        } catch (Exception e) {
            output.error(program ~ ": cannot open " ~ options.database ~ ": " ~ e.msg ~ "\n");
            return 1;
        }
        sql = core;
    }

    auto shell = new CliShell(sql, output, options.format);
    shell.stopOnError = !options.continueOnError;
    int status;
    if (options.interactive) {
        auto input = new ConsoleInput;
        if (input.interactive)
            output.error(options.socket.length ? "Connected to " ~ options.socket ~ "\n"
                    : options.database.length ? "Database: " ~ options.database ~ "\n"
                    : "Database in memory: nothing is saved.\n");
        status = shell.run(input);
    } else {
        bool ok = true;
        foreach (command; options.commands)
            if (ok || options.continueOnError)
                ok &= shell.runScript(command);
        foreach (file; options.files)
            if (ok || options.continueOnError)
                ok &= file == "-" ? shell.run(new ConsoleInput) == 0 : shell.command(`\i ` ~ file);
        shell.rollbackOpen();
        status = ok ? 0 : 1;
    }

    if (client !is null) {
        try
            if (loggedIn) // eine mit HDB_TOKEN übernommene Sitzung gehört dem Aufrufer und bleibt offen
                client.logout();
        catch (Exception) {
        }
        client.close();
    } else if (options.database.length) {
        try
            core.checkpoint(); // Stand wegschreiben wie HdbDatabase.close
        catch (Exception e) {
            output.error(program ~ ": checkpoint failed: " ~ e.msg ~ "\n");
            return 1;
        }
    }
    return status;
}

/// Meldet am Server an. Gibt true zurück, wenn hdb-cli die Sitzung selbst geöffnet hat (und am Ende beendet).
private bool connect(RemoteSqlClient client, CliOptions options, ICliOutput output) @safe {
    auto user = options.user.length ? options.user : environment.get("HDB_USER", "");
    if (user.length == 0) {
        enforce(client.token.length, "Client mode needs --user (or HDB_USER), or a session token in HDB_TOKEN");
        client.listTables(); // prüft das Token sofort statt erst bei der ersten Anweisung
        return false;
    }
    auto password = environment.get("HDB_PASSWORD", null);
    if (password is null)
        password = readSecret("Password for " ~ user ~ (options.tenant.length ? "@" ~ options.tenant : "") ~ ": ");
    enforce(password !is null, "No password: set HDB_PASSWORD or run on a terminal");
    auto tenant = client.login(options.tenant, user, password);
    if (options.interactive)
        output.error("Logged in as " ~ user ~ (tenant.length ? " (tenant " ~ tenant ~ ")" : "") ~ "\n");
    return true;
}
