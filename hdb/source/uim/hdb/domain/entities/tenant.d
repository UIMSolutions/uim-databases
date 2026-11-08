module uim.hdb.domain.entities.tenant;

import std.algorithm : all;
import std.ascii : isDigit, isLower;
import std.exception : enforce;
import std.string : strip, toLower;

/// Mandant, dem Benutzer und Logins ohne Angabe zugeordnet sind. Er entsteht beim ersten Start
/// und nimmt bei der Umstellung die bisherigen Daten und Benutzer auf.
enum defaultTenant = "default";

/// Bereich der Systemadministratoren: sie verwalten Mandanten, haben aber keine eigenen Daten
/// und sehen keine Daten der Mandanten. Er ist immer aktiv und steht nicht in der Mandantenliste.
enum systemTenant = "system";

/// Ein Mandant. Daten und Benutzer sind vollständig von anderen Mandanten getrennt.
struct Tenant {
    string name; // Kennung: Teil des Logins und Name des Datenverzeichnisses
    string label; // Anzeigename
    bool active = true; // inaktiv: keine Anmeldung, laufende Sitzungen enden
}

/// Kennung eines Mandanten. Sie wird zum Verzeichnisnamen, deshalb nur Kleinbuchstaben, Ziffern, '-' und '_',
/// mit Buchstabe oder Ziffer am Anfang: so kann sie nie aus dem Datenverzeichnis herausführen.
string validTenantName(string name) {
    auto normalized = name.strip.toLower;
    enforce(normalized.length >= 1 && normalized.length <= 32
            && (isLower(normalized[0]) || isDigit(normalized[0]))
            && normalized.all!(c => isLower(c) || isDigit(c) || c == '_' || c == '-'),
        "Tenant names use 1 to 32 lowercase letters, digits, '_' or '-', starting with a letter or digit");
    return normalized;
}

/// Mandant aus einer Anmeldung: leer bedeutet default.
string loginTenant(string tenant) {
    auto normalized = tenant.strip.toLower;
    return normalized.length ? normalized : defaultTenant;
}

unittest {
    import std.array : replicate;
    import std.exception : assertThrown;

    assert(validTenantName(" Kunde-1 ") == "kunde-1");
    assert(validTenantName("a_b") == "a_b");
    assertThrown(validTenantName(""));
    assertThrown(validTenantName(".."));
    assertThrown(validTenantName("a/b"));
    assertThrown(validTenantName("-a"));
    assertThrown(validTenantName("a.b"));
    assertThrown(validTenantName("ä"));
    assertThrown(validTenantName("x".replicate(33)));

    assert(loginTenant("") == defaultTenant && loginTenant("  ") == defaultTenant);
    assert(loginTenant(" Kunde1 ") == "kunde1");
}

