/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Einstieg des Admin-Clients: dub run --config=gui -- --server=http://localhost:8080
module hdbadmin;

import uim.hdb.presentation.gui;

int main(string[] args) {
    return runAdminClient(args);
}
