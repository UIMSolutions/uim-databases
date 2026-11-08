/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Admin-Client mit GTK (GtkD). Ein eigenes Programm (dub build --config=gui), das den Server nur über seine
/// REST-API anspricht: dieselben Rechte, dieselbe Anmeldung wie jeder andere Client.
module uim.hdb.presentation.gui;

public:
    import uim.hdb.presentation.gui.api;
    import uim.hdb.presentation.gui.transport;
    import uim.hdb.presentation.gui.login;
    import uim.hdb.presentation.gui.pages;
    import uim.hdb.presentation.gui.widgets;
    import uim.hdb.presentation.gui.window;
