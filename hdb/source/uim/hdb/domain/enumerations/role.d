/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.enumerations.role;

import uim.hdb;

@safe:
/// HdbRole is the role of a user in the HDB system, defining their permissions and access level.
enum HdbRole {
    viewer, // SELECT
    editor, // zusätzlich INSERT, UPDATE, DELETE und Transaktionen
    admin // zusätzlich CREATE, DROP, Wartung und Benutzerverwaltung
}