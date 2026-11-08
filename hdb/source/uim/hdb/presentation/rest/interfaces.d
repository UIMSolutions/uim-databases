module uim.hdb.presentation.rest.interfaces;

import uim.hdb.presentation.rest.models;
import vibe.data.json : Json;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;

/// Betrieb: Zustand, Statistik und Wartung.
@path("/api/v1")
interface ISystemRestApi {
@safe:
    @method(HTTPMethod.GET) @path("/health")
    RestStatus health();

    @method(HTTPMethod.GET) @path("/stats")
    RestTableInfo[] stats();

    @method(HTTPMethod.POST) @path("/checkpoint")
    RestStatus checkpoint();

    @method(HTTPMethod.GET) @path("/merge")
    RestMergeStatus mergeStatus();

    /// Startet den Delta-Merge im Hintergrund und antwortet mit 202; status ist STARTED oder RUNNING.
    @method(HTTPMethod.POST) @path("/merge")
    RestStatus startMerge(@viaStatus out int httpStatus);
}

/// SQL-Ausführung. BEGIN liefert die Transaktions-Id, die folgende Aufrufe im Feld `transaction`
/// oder im Header X-Transaction-Id mitgeben; das Feld hat Vorrang.
@path("/api/v1")
interface ISqlRestApi {
@safe:
    @method(HTTPMethod.POST) @path("/sql")
    @bodyParam("statement", "statement") @bodyParam("transaction", "transaction") @headerParam("headerTransaction", "X-Transaction-Id")
    RestSqlResult execute(string statement, string transaction = "", string headerTransaction = "");
}

/// Tabellen als Ressourcen.
@path("/api/v1")
interface ITableRestApi {
@safe:
    @method(HTTPMethod.GET) @path("/tables")
    string[] list();

    /// Legt eine Tabelle an; type ist ein SQL- oder EDM-Name wie INTEGER oder Edm.Int64, storage MEMORY (Standard), FILE oder JSON.
    @method(HTTPMethod.POST) @path("/tables")
    @bodyParam("name", "name") @bodyParam("columns", "columns") @bodyParam("storage", "storage")
    RestTableInfo create(string name, RestColumnDef[] columns, string storage = "");

    @method(HTTPMethod.GET) @path("/tables/:name")
    RestTableInfo info(string _name);

    @method(HTTPMethod.DELETE) @path("/tables/:name")
    RestStatus drop(string _name);

    /// Liest Zeilen; `where` ist eine WHERE-Bedingung, `sort` eine Spalte. `limit` höchstens 1000.
    @method(HTTPMethod.GET) @path("/tables/:name/rows")
    @queryParam("where", "where") @queryParam("sort", "sort") @queryParam("desc", "desc")
    @queryParam("limit", "limit") @queryParam("offset", "offset")
    RestRowPage rows(string _name, string where = "", string sort = "", bool desc = false,
        long limit = 100, long offset = 0);

    /// Fügt eine Zeile ein: ein Wert je Spalte in Tabellenreihenfolge, null für NULL.
    @method(HTTPMethod.POST) @path("/tables/:name/rows")
    @bodyParam("values", "values")
    RestSqlResult insert(string _name, Json[] values);
}

/// Anmeldung. Das Token aus login geht als `Authorization: Bearer <token>` an alle anderen Endpunkte.
@path("/api/v1/auth")
interface IAuthRestApi {
@safe:
    /// `tenant` ist optional; ohne meldet login im Mandanten default an.
    @method(HTTPMethod.POST) @path("/login")
    @bodyParam("user", "user") @bodyParam("password", "password") @bodyParam("tenant", "tenant")
    RestLogin login(string user, string password, string tenant = "");

    @method(HTTPMethod.POST) @path("/logout")
    @headerParam("authorization", "Authorization")
    RestStatus logout(string authorization);

    @method(HTTPMethod.GET) @path("/me")
    RestUser me();

    /// Ändert das eigene Passwort und beendet alle eigenen Sitzungen.
    @method(HTTPMethod.POST) @path("/password")
    @bodyParam("current", "current") @bodyParam("replacement", "replacement")
    RestStatus changePassword(string current, string replacement);
}

/// Benutzerverwaltung, nur für die Rolle admin.
@path("/api/v1")
interface IUserRestApi {
@safe:
    @method(HTTPMethod.GET) @path("/users")
    RestUser[] list();

    @method(HTTPMethod.POST) @path("/users")
    @bodyParam("name", "name") @bodyParam("password", "password") @bodyParam("role", "role")
    RestUser create(string name, string password, string role);

    @method(HTTPMethod.PUT) @path("/users/:name")
    @bodyParam("role", "role") @bodyParam("active", "active")
    RestUser update(string _name, string role, bool active);

    @method(HTTPMethod.POST) @path("/users/:name/password")
    @bodyParam("password", "password")
    RestStatus resetPassword(string _name, string password);

    @method(HTTPMethod.DELETE) @path("/users/:name")
    RestStatus remove(string _name);
}

/// Mandantenverwaltung, nur für Administratoren des Mandanten system. Sie sehen keine Daten der Mandanten.
@path("/api/v1")
interface ITenantRestApi {
@safe:
    @method(HTTPMethod.GET) @path("/tenants")
    RestTenant[] list();

    /// Legt den Mandanten mit leerer Datenbank und seinem ersten Administrator an.
    @method(HTTPMethod.POST) @path("/tenants")
    @bodyParam("name", "name") @bodyParam("label", "label")
    @bodyParam("adminName", "adminName") @bodyParam("adminPassword", "adminPassword")
    RestTenant create(string name, string adminName, string adminPassword, string label = "");

    /// active=false beendet alle Sitzungen des Mandanten.
    @method(HTTPMethod.PUT) @path("/tenants/:name")
    @bodyParam("label", "label") @bodyParam("active", "active")
    RestTenant update(string _name, bool active, string label = "");

    /// Löscht Benutzer, Daten und Sicherungen endgültig; nur für deaktivierte Mandanten.
    @method(HTTPMethod.DELETE) @path("/tenants/:name")
    RestStatus remove(string _name);
}

/// Sichern und Wiederherstellen, nur für die Rolle admin. Dazu kommen außerhalb dieser Schnittstelle, weil es rohe
/// Dateien sind: GET /api/v1/backups/:name/content und POST /api/v1/backups/import.
@path("/api/v1")
interface IBackupRestApi {
@safe:
    @method(HTTPMethod.GET) @path("/backups")
    RestBackup[] list();

    @method(HTTPMethod.POST) @path("/backups")
    @bodyParam("label", "label")
    RestBackup create(string label = "");

    @method(HTTPMethod.GET) @path("/backups/schedule")
    RestBackupSchedule schedule();

    /// Weniger aufbewahren wirkt sofort: überzählige geplante und Sicherheitskopien werden gelöscht.
    @method(HTTPMethod.PUT) @path("/backups/schedule")
    @bodyParam("enabled", "enabled") @bodyParam("intervalHours", "intervalHours")
    @bodyParam("keepScheduled", "keepScheduled") @bodyParam("keepSafety", "keepSafety")
    RestBackupSchedule updateSchedule(bool enabled, int intervalHours, int keepScheduled, int keepSafety);

    /// Ersetzt alle Tabellen; vorher wird automatisch eine Sicherheitskopie angelegt.
    @method(HTTPMethod.POST) @path("/backups/:name/restore")
    RestRestore restore(string _name);

    @method(HTTPMethod.DELETE) @path("/backups/:name")
    RestStatus remove(string _name);
}
