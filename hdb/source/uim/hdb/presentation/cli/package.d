/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Kommandozeile: SQL-Shell und Skripte (Programm hdb-cli, dub run --config=cli), entweder gegen eine Datenbank
/// im eigenen Prozess oder als Client über den Unix-Socket eines laufenden Servers. Die Shell kennt nur
/// ISqlUseCase; RemoteSqlClient ist dessen Umsetzung über den Socket.
module source.uim.hdb.presentation.cli;

public:
    import uim.hdb.presentation.cli.console;
    import uim.hdb.presentation.cli.format;
    import uim.hdb.presentation.cli.interfaces;
    import uim.hdb.presentation.cli.options;
    import uim.hdb.presentation.cli.remote;
    import uim.hdb.presentation.cli.shell;
    import uim.hdb.presentation.cli.statements;
