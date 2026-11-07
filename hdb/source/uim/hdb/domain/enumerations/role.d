module uim.hdb.domain.enumerations.role;

import uim.hdb;

// HdbRole is 
enum HdbRole {
    viewer, // SELECT
    editor, // zusätzlich INSERT, UPDATE, DELETE und Transaktionen
    admin // zusätzlich CREATE, DROP, Wartung und Benutzerverwaltung
}