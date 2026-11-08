# hana-lite

In-Memory-Spaltendatenbank mit vibe.d, aufgebaut als Hexagonale Architektur.

    domain/        Value, ColumnTable (Column Store)
    application/   Ports + SqlService (Mini-SQL-Parser/Executor)
    adapters/
      inbound/     REST (vibe.d)
      outbound/    InMemoryTableRepository
    app.d          Composition Root

Start: `dub run`

    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"CREATE TABLE orders (id INTEGER, customer VARCHAR(40), amount DECIMAL)"}'
    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"INSERT INTO orders VALUES (1, '\''ACME'\'', 99.5)"}'
    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT SUM(amount) FROM orders WHERE id >= 1"}'

## Datentypen

Jeder Spaltentyp entspricht einem primitiven EDM-Typ aus OData v4. In `CREATE TABLE` und in der REST-API gilt der SQL-Name, ein
Synonym oder der EDM-Name, ohne Rücksicht auf die Schreibweise: `CREATE TABLE t (a Edm.Int16, b SMALLINT)`.

| SQL | Synonyme | EDM | Literal in SQL |
| --- | --- | --- | --- |
| `BOOLEAN` | `BOOL` | `Edm.Boolean` | `TRUE`, `FALSE` |
| `TINYINT` | `BYTE` | `Edm.Byte` | `255` (0 bis 255) |
| `SBYTE` | | `Edm.SByte` | `-128` (-128 bis 127) |
| `SMALLINT` | `INT16` | `Edm.Int16` | `32767` |
| `INT32` | | `Edm.Int32` | `2147483647` |
| `INTEGER` | `INT`, `BIGINT`, `INT64` | `Edm.Int64` | `42` |
| `REAL` | `SINGLE` | `Edm.Single` | `0.1` |
| `DECIMAL` | `DOUBLE` | `Edm.Double` | `1.5` |
| `NUMERIC` | | `Edm.Decimal` | `12345678901234567890.55` |
| `VARCHAR` | `NVARCHAR`, `TEXT` | `Edm.String` | `'Text'` |
| `BLOB` | `BINARY`, `VARBINARY` | `Edm.Binary` | `X'00FF'` oder `'00FF'` |
| `DATE` | | `Edm.Date` | `'2026-11-06'` |
| `TIMESTAMP` | `DATETIMEOFFSET` | `Edm.DateTimeOffset` | `'2026-11-06T12:30:00+01:00'` |
| `TIME` | `TIMEOFDAY` | `Edm.TimeOfDay` | `'12:30:00'` |
| `DURATION` | | `Edm.Duration` | `'P1DT2H'` |
| `GUID` | `UUID` | `Edm.Guid` | `'01234567-89ab-cdef-0123-456789abcdef'` |
| `GEO` | `GEOMETRY`, `ST_GEOMETRY` | `Edm.Geometry` | `'POINT(13.4 52.5)'` |
| `GEOGRAPHY` | | `Edm.Geography` | `'POINT(13.4 52.5)'`, Länge und Breite in Grad |
| `LINK` | `URL` | `Edm.String` | `'https://example.org/a'` |

`LINK` ist die einzige Ergänzung: EDM kennt keine URL, nach außen ist der Typ deshalb `Edm.String`. Erlaubt sind `http`,
`https`, `ftp` und `mailto`, die Admin-Oberfläche zeigt die Werte als klickbaren Verweis.

Vorsicht bei `DECIMAL`: Der Name ist aus Kompatibilität mit bestehenden Daten geblieben, der Typ ist ein double. Exakte
Dezimalzahlen, etwa für Geldbeträge, sind `NUMERIC`.

    CREATE TABLE orte (id GUID, aktiv BOOLEAN, preis NUMERIC, foto BLOB, lage GEOGRAPHY, seit TIMESTAMP, web LINK)
    INSERT INTO orte VALUES ('01234567-89ab-cdef-0123-456789abcdef', TRUE, 19.99, X'89504E47',
      'POINT(13.4 52.5)', '2026-11-06T12:30:00+01:00', 'https://example.org')
    SELECT id FROM orte WHERE aktiv = TRUE AND seit >= '2026-01-01T00:00:00Z' ORDER BY preis

Werte werden beim Schreiben geprüft, auch beim Laden von Dateien und Backups, und in eine einheitliche Form gebracht:

- `TIMESTAMP` wird nach UTC umgerechnet und mit sieben Nachkommastellen gespeichert; der Versatz selbst geht verloren.
- `DURATION` kennt nur Tage bis Sekunden, wie EDM; `PT36H` wird `P1DT12H`. Sortiert wird nach der Länge.
- `NUMERIC` ist exakt und sortiert numerisch, `SUM` und `AVG` rechnen aber mit double und runden dabei.
- `GEO` und `GEOGRAPHY` nehmen WKT für `POINT`, `LINESTRING` und `POLYGON` an, nur 2D. Es gibt keine räumlichen Funktionen wie
  Abstand oder Schnitt; `Multi*`-Geometrien und Sammlungen fehlen.
- `SUM` und `AVG` gehen nur auf Zahlen, `LIKE` nur auf Typen, die als Text gespeichert werden, also nicht auf Zahlen, `BOOLEAN`
  und `DURATION`.

`Edm.Stream` gibt es nicht: Es ist kein Spaltenwert, sondern Medieninhalt mit eigener Adresse. Für Binärdaten dient `BLOB`.
Intern und über die REST-API ist `BLOB` Hex-Text; das verdoppelt die Größe, große Dateien gehören also nicht hinein.

Die REST-API überträgt `BOOLEAN` als JSON-Wahrheitswert, `NUMERIC` als Text, damit keine Stellen verloren gehen, `GEO` als WKT
und `BLOB` als Hex-Text. OData nutzt dagegen die Formate der Spezifikation, siehe dort.

## REST-API v1

Typisierte vibe.d-Schnittstellen in `presentation/rest` (`interfaces.d`, `models.d`, `services.d`), registriert von
`registerHdbRestApi`. Aus den Schnittstellen lassen sich Clients erzeugen: `new RestInterfaceClient!ITableRestApi(url)`.

| Methode und Pfad | Zweck |
|---|---|
| `GET /api/v1/health` | Zustand |
| `GET /api/v1/stats` | Statistik aller Tabellen |
| `POST /api/v1/checkpoint` | Checkpoint schreiben |
| `GET /api/v1/merge` | Zustand des Delta-Merges |
| `POST /api/v1/merge` | Delta-Merge starten (202) |
| `POST /api/v1/sql` | `{"statement": "...", "transaction": "<id>"}`, Id auch im Header `X-Transaction-Id` |
| `GET /api/v1/tables` | Tabellennamen |
| `POST /api/v1/tables` | `{"name": "t", "columns": [{"name": "id", "type": "INTEGER"}]}` |
| `GET /api/v1/tables/:name` | Spalten und Statistik |
| `DELETE /api/v1/tables/:name` | Tabelle löschen |
| `GET /api/v1/tables/:name/rows` | Zeilen; Parameter `where`, `sort`, `desc`, `limit` (1 bis 1000, Standard 100), `offset` |
| `POST /api/v1/tables/:name/rows` | `{"values": [1, "a", null]}`, ein Wert je Spalte |

Fehler: `{"statusMessage": "..."}` mit 400 (ungültiges SQL, gesperrte Datenbank) oder 404 (Tabelle unbekannt).
Dazu `GET|PUT /api/v1/network`, `PUT /api/v1/tenants/:name/networks` (siehe Erlaubte Netze),
`GET|PUT|DELETE /api/v1/replication…` (siehe Replikation), `POST /api/v1/auth/login|logout|password`, `GET /api/v1/auth/me` und `GET|POST /api/v1/users`,
`PUT|DELETE /api/v1/users/:name`, `POST /api/v1/users/:name/password`, `PUT /api/v1/users/:name/grants`,
`GET /api/v1/roles`, `PUT|DELETE /api/v1/roles/:name` (siehe Benutzer und Rechte), für Systemadministratoren `GET|POST /api/v1/tenants`
und `PUT|DELETE /api/v1/tenants/:name` (siehe Mandanten). Fehlende Anmeldung ergibt 401, fehlende Rechte 403.
Die Endpunkte ohne `/api/v1` (`adapters/inbound/rest_api.d`) bestehen weiter und verlangen ebenfalls ein Bearer-Token.

## OData v4

OData 4.0 unter `/odata/v4` (`presentation/odata`), Tabellen sind Entity Sets. Anmeldung per Bearer-Token und Rollen gelten
wie bei allen anderen Schnittstellen.

    curl localhost:8080/odata/v4/\$metadata -H "Authorization: Bearer $TOKEN"
    curl "localhost:8080/odata/v4/orders?\$filter=amount%20gt%2010&\$orderby=id%20desc&\$top=5&\$count=true" -H "Authorization: Bearer $TOKEN"
    curl -X PATCH "localhost:8080/odata/v4/orders(1)" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d '{"amount": 12.5}'

- Lesen: Service-Dokument, `$metadata` (CSDL/XML), `/orders`, `/orders/$count`, `/orders(1)`, `/orders(1)/name`, `/orders(1)/name/$value`.
- Schreiben: `POST`, `PATCH`, `PUT` (fehlende Eigenschaften werden NULL), `DELETE`; `Prefer: return=minimal|representation`.
- Optionen: `$filter`, `$select`, `$orderby`, `$top`, `$skip`, `$count`, `$format=json`. Höchstens 1000 Zeilen je Antwort,
  danach `@odata.nextLink`.
- `$filter`: `eq ne gt ge lt le`, `and or not`, Klammern, `null`, `contains`, `startswith`, `endswith`. Verglichen wird eine
  Eigenschaft mit einem Literal. NULL verhält sich wie in OData 4.0: `a ne 1` trifft auch Zeilen, in denen `a` NULL ist.
- Nicht umgesetzt, Antwort 501: `$expand`, `$search`, `$apply`, `$compute`, `$batch`, weitere Funktionen und Arithmetik in
  `$filter`. Es gibt keine ETags und keine Beziehungen zwischen Tabellen.

Typen: siehe [Datentypen](#datentypen). `Edm.Binary` ist Base64url, `/$value` liefert die Rohbytes. `Edm.Geometry` und
`Edm.Geography` sind GeoJSON (`{"type":"Point","coordinates":[13.4,52.5]}`); beim Schreiben geht auch WKT als Text, weil der
UI5-Client Eigenschaften nur mit einfachen Werten ändern kann. Mit `IEEE754Compatible=true` in `Accept` oder `Content-Type` sind
`Edm.Int64`, `Edm.Decimal` und `@odata.count` in beide Richtungen Text. Ohne diese Angabe ist `Edm.Decimal` beim Lesen eine
JSON-Zahl mit allen Stellen, beim Schreiben bleibt nur Text exakt.

Literale in `$filter`: `true`, `2026-11-06`, `2026-11-06T12:30:00Z`, `12:30:00`, GUIDs ohne Anführungszeichen, dazu
`duration'P1D'`, `binary'AAEC'`, `geometry'SRID=0;Point(1 2)'` und `geography'SRID=4326;Point(1 2)'`. `contains`, `startswith`
und `endswith` gehen nur auf `Edm.String`.

Schlüssel: Tabellen haben keinen Primärschlüssel, deshalb gilt eine Spalte `id` (ganze Zahl, `VARCHAR` oder `GUID`) als Schlüssel.
Der Kern erzwingt keine Eindeutigkeit: `POST` lehnt vorhandene Schlüssel ab, kommt ein Schlüssel trotzdem mehrfach vor
(etwa nach SQL-Änderungen), antworten Zugriffe darauf mit 409 statt mehrere Zeilen zu ändern. Tabellen ohne `id` zeigen die
berechnete Eigenschaft `__rowid`. Das ist nur die Position im Ergebnis, einzelne Zeilen sind dort nicht adressierbar (501).
Tabellen oder Spalten, deren Name kein gültiger OData-Bezeichner ist (etwa `1a`), erscheinen nicht im Dienst.

## Fiori-Frontend

OpenUI5-Anwendung im Design Fiori 3 (`sap_fiori_3`) unter `http://localhost:8080/ui5/`, Quellen in `public/ui5/`. Sie spricht
nur mit `/odata/v4` und der Anmeldung (`/api/v1/auth`) und braucht keinen Build-Schritt.

- `FlexibleColumnLayout`: Tabellen, Zeilen, Details. Links wie `#/tables/orders/rows/1` lassen sich teilen und neu laden.
- Seitennavigation (`sap.tnt.ToolPage`) mit Hamburger-Button in der ShellBar: Tabellen, Statistik, Backups (nur
  Administratoren), Hilfe und Admin-Konsole. Sie klappt zu einer Symbolleiste ein, auf schmalen Bildschirmen schließt sie nach der Auswahl.
- Sprache im Profilmenü: Englisch oder Deutsch, gespeichert im `localStorage`. Ohne Wahl gilt die Browsersprache. Die
  Admin-Oberfläche und Fehlermeldungen des Servers sind davon nicht betroffen.
- Suche, Sortierung, nachladende Liste, Zeilen anlegen, bearbeiten und löschen. Spalten kommen aus `$metadata`, neue Tabellen
  brauchen keine Änderung am Client. Tabellen anlegen und Benutzer verwalten bleibt in der Administrationsoberfläche.
- Das Modell nutzt die Gruppe `$direct`, weil der Dienst kein `$batch` kennt: jede Änderung ist eine eigene Anfrage. Beim
  Speichern geht jedes geänderte Feld als eigenes `PATCH`, mehrere Felder einer Zeile werden also nicht atomar geändert.
- Das Token liegt im `sessionStorage` und endet mit dem Browser-Tab. OpenUI5 kommt mit fester Version (1.148.10, Wartung bis
  Q3/2027) vom CDN `sdk.openui5.org`. Dieses Skript läuft mit Zugriff auf das Token; für den Betrieb ohne fremdes CDN die
  Bibliothek selbst ausliefern und die URL in `public/ui5/index.html` ändern.
- `public/ui5/` ist ohne Anmeldung erreichbar und darf deshalb keine Daten oder Geheimnisse enthalten.

## Administrationsoberfläche

`http://localhost:8080/admin` (Adapter `adapters/inbound/admin_web.d`, Templates in `views/`, Skript in `public/admin.js`).

- Dashboard: Kennzahlen je Tabelle, Delta-Merge und Checkpoint auslösen, Tabellen anlegen.
- Tabellenansicht: Filtern (WHERE), Sortieren, Blättern, Zeilen anlegen, bearbeiten und löschen, CSV-Export,
  Tabelle leeren oder löschen, Speicherstatistik je Spalte.
- SQL-Konsole: mehrere Anweisungen mit `;`, Abbruch beim ersten Fehler, `BEGIN` trägt über mehrere Ausführungen.
- Statistik (`/admin/stats`): Speicherkennzahlen aller Tabellen je Spalte. Hilfe (`/admin/help`): Bedienung, SQL, Datentypen.

Tabellen haben keinen Primärschlüssel. Bearbeiten und Löschen einer Zeile treffen deshalb alle Zeilen mit
identischen Werten; die Oberfläche meldet die Anzahl.

Die Oberfläche blendet aus, was die Rolle nicht darf; entschieden wird aber immer auf dem Server.

## Unix Domain Socket

Mit `UNIX_SOCKET=/run/hdb/hdb.sock` nimmt der Server zusätzlich zu HTTP Anfragen über einen Unix Domain Socket an
(`presentation/unix`). Ohne die Variable gibt es keinen Socket. Pfade und JSON sind dieselben wie bei der REST-API:
`/api/v1/health`, `/auth/login`, `/auth/logout`, `/sql`, `/tables`, `/stats`, `/checkpoint` und `/merge`.

    POST /api/v1/sql
    Authorization: Bearer <token>
    Content-Length: 37

    {"statement":"SELECT COUNT(*) FROM t"}

Antwort: Zeile `STATUS 200`, Header mit `Content-Length`, Leerzeile, Body. Eine Verbindung bedient mehrere Anfragen nacheinander.

- Der Socket hat die Rechte 0600. Das ersetzt die Anmeldung nicht: jede Anfrage braucht ein Token, Rollen gelten wie bei HTTP.
- Ein Body hat höchstens 16 MB, Header höchstens 64 KB. Eine ungültige Nachricht wird mit 400 oder 413 beantwortet, danach
  endet die Verbindung. Ohne Anfrage endet sie nach 5 Minuten.
- Ein verwaister Socket nach einem Absturz wird beim Start ersetzt. Antwortet er noch oder liegt dort etwas anderes als ein
  Socket, bricht der Start ab; es wird nichts gelöscht.

## Mandanten

Jeder Mandant hat seine eigene Datenbank: Tabellen, Anweisungsprotokoll, Sicherungen, Zeitplan und Benutzer. Nichts davon
wird geteilt, auch nicht eine offene Transaktion. Zwei Mandanten können dieselben Tabellen- und Benutzernamen haben.

    data/hdb-tenants.json          Liste der Mandanten (TENANTS_FILE)
    data/hdb-users.json            Benutzer aller Mandanten (USERS_FILE)
    data/tenants/<mandant>/        Daten eines Mandanten (TENANTS_DIR)
        hdb.log                    Anweisungsprotokoll
        tables/file, tables/json   Tabellen mit Speicher FILE und JSON
        backups/                   Sicherungen und schedule.json

Anmeldung mit Mandant: in den Formularen im Feld „Mandant“, per API im Feld `tenant`. Ohne Angabe gilt `default`,
bestehende Skripte laufen also unverändert weiter.

    curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"tenant":"acme","user":"admin","password":"..."}'

Mandanten verwalten nur Systemadministratoren, also Administratoren im Bereich `system`. Sie melden sich mit dem
Mandanten `system` an, legen Mandanten mit ihrem ersten Administrator an, ändern Anzeigenamen und deaktivieren oder
löschen Mandanten. Auf Daten der Mandanten haben sie keinen Zugriff: SQL, OData, Tabellen und Sicherungen antworten mit 403,
und die Administrationsoberfläche zeigt ihnen nur Mandanten, Systembenutzer und ihr Konto. Alles andere verwalten die
Administratoren eines Mandanten selbst, und nur in ihrem Mandanten.

    curl localhost:8080/api/v1/tenants -H "Authorization: Bearer $SYSTOKEN" -H 'Content-Type: application/json' \
      -d '{"name":"acme","label":"Acme Corp","adminName":"admin","adminPassword":"..."}'
    curl -X PUT localhost:8080/api/v1/tenants/acme -H "Authorization: Bearer $SYSTOKEN" -H 'Content-Type: application/json' \
      -d '{"label":"Acme Corp","active":false}'
    curl -X DELETE localhost:8080/api/v1/tenants/acme -H "Authorization: Bearer $SYSTOKEN"

- Mandantennamen: 1 bis 32 Kleinbuchstaben, Ziffern, `_` und `-`, beginnend mit Buchstabe oder Ziffer. Sie sind Teil der
  Anmeldung und der Verzeichnisname, deshalb nicht änderbar. `system` ist reserviert.
- Deaktivieren beendet sofort alle Sitzungen des Mandanten und verhindert neue Anmeldungen. Daten und Benutzer bleiben.
- Löschen geht nur bei deaktivierten Mandanten und entfernt Benutzer, Daten und Sicherungen endgültig.
- Liegen beim Anlegen noch Daten eines früheren Mandanten gleichen Namens auf der Platte, wird abgelehnt, statt sie zu übernehmen.
- Die Anmeldung meldet einen unbekannten oder deaktivierten Mandanten genauso wie ein falsches Passwort.
- Alle Mandanten werden beim Start geladen und liegen im Speicher, wie bisher die eine Datenbank.

Erster Start: Es entstehen der Mandant `default` mit `ADMIN_USER` (Standard `admin`, Passwort `ADMIN_PASSWORD`) und der
Systemadministrator `SYSTEM_ADMIN_USER` (Standard `sysadmin`, Passwort `SYSTEM_ADMIN_PASSWORD`). Ohne Passwort wird eines
erzeugt und einmalig ins Log geschrieben. Der Systemadministrator wird auch angelegt, wenn der Bereich `system` noch
keine Benutzer hat, etwa beim ersten Start nach der Umstellung.

Umstellung einer bestehenden Installation: Beim ersten Start ziehen `DATA_FILE`, `TABLES_DIR` und `BACKUP_DIR` nach
`TENANTS_DIR/default` um (verschoben, nicht kopiert), und alle bisherigen Benutzer gehören zu `default`. Anmeldungen
ohne Mandant funktionieren wie vorher. Das geschieht nur, solange `TENANTS_DIR/default` noch nicht existiert.

## Benutzer und Rechte

Außer `GET /health`, `GET /api/v1/health` und den Anmeldeseiten verlangt jede Route eine Anmeldung.

Rechte werden über Rollen vergeben (RBAC), auf drei Ebenen:

| Ebene | Wer | Rechte |
|---|---|---|
| Server | Benutzer im Bereich `system` | `viewTenants`, `manageTenants`, `manageAccess` (Systembenutzer und -rollen) |
| Mandant | Rolle eines Benutzers, gilt für alle Tabellen | `select`, `insert`, `update`, `delete`, `drop`, `create`, `transact`, `maintain`, `manageBackups`, `replicate`, `manageReplication`, `manageAccess` |
| Tabelle | Freigabe: Rolle für eine einzelne Tabelle | davon nur `select`, `insert`, `update`, `delete`, `drop` |

Vordefinierte Rollen, unveränderlich; bestehende Benutzer behalten damit ihre Rechte:

| Bereich | Rolle | Rechte |
|---|---|---|
| Mandant | `viewer` | `select`, `replicate` |
| Mandant | `editor` | zusätzlich `insert`, `update`, `delete`, `transact` |
| Mandant | `admin` | alle Mandantenrechte |
| `system` | `viewer` | `viewTenants` |
| `system` | `admin` | alle Serverrechte |

Eigene Rollen legt man mit `manageAccess` unter `/admin/roles` oder per API an, je Mandant bzw. im Bereich `system`.
Ein Benutzer hat höchstens eine Rolle im Mandanten (oder keine) und beliebig viele Tabellenfreigaben unter
`/admin/users/<name>/grants`. Rechte addieren sich, es gibt keine Verbote. Ein Benutzer ohne Rolle sieht nur die
freigegebenen Tabellen.

    curl -X PUT localhost:8080/api/v1/roles/clerk -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"description":"Reads and adds rows","permissions":["select","insert"]}'
    curl localhost:8080/api/v1/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"name":"tina","password":"...","role":""}'
    curl -X PUT localhost:8080/api/v1/users/tina/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"orders","role":"clerk"}]}'
    curl localhost:8080/api/v1/auth/me -H "Authorization: Bearer $TOKEN"   # aufgelöste Rechte, auch je Tabelle

- Tabellenrechte prüft der SQL-Kern an jeder Stelle, an der eine Anweisung eine Tabelle holt: bei Joins für jede
  beteiligte Tabelle, vor jeder Änderung. Eine verborgene Tabelle verhält sich wie eine fehlende (403 bzw. 404 mit
  derselben Meldung wie für unbekannte Tabellen), ihre Existenz wird nicht verraten.
- Tabellenlisten, Statistik, OData-`$metadata` und die Oberflächen zeigen nur Tabellen, auf denen der Benutzer ein Recht
  hat, und nur die Schaltflächen, die er nutzen darf.
- `create` und `transact` gelten nur im ganzen Mandanten: `BEGIN` sperrt alle Tabellen.
- Freigaben dürfen Tabellen nennen, die es noch nicht gibt, und gelten nach `DROP` für eine neu angelegte Tabelle
  gleichen Namens wieder.
- Rollen- und Freigabeänderungen wirken sofort, auch in laufenden Sitzungen. Eine Rolle lässt sich erst löschen,
  wenn sie niemand mehr verwendet.
- In jedem Bereich muss ein aktiver Benutzer `manageAccess` behalten; Änderungen, die das verhindern würden, werden
  abgelehnt. Dieses Recht kommt nur aus der Rolle im Mandanten, nie aus einer Tabellenfreigabe.
- Sicherungen (`manageBackups`) und der Replikationsstrom (`replicate`) enthalten alle Tabellen: diese Rechte deshalb
  nur Rollen geben, die ohnehin alles lesen dürfen.
- Eigene Rollen liegen in `ROLES_FILE` (Standard `data/hdb-roles.json`), Rollen und Freigaben der Benutzer in `USERS_FILE`.

Eine offene Transaktion kann nur ihr Besitzer verwenden.

### Befristete Rechte

Zusätzliche Rollen eines Benutzers (unter `/admin/users/<name>/grants` oder `PUT /api/v1/users/<name>/grants`) lassen
sich befristen. Ohne Tabelle gilt eine solche Rolle im ganzen Mandanten, im Bereich `system` auf dem Server, etwa
„admin bis Freitag 18 Uhr“:

    curl -X PUT localhost:8080/api/v1/users/vic/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"","role":"admin","until":"2026-11-13T17:00:00Z"},
                     {"table":"orders","role":"editor","from":"2026-11-10T08:00","until":"2026-11-10T18:00"}]}'

- `from` (einschließlich) und `until` (ausschließlich) sind optional und UTC; ohne Zeitzone gilt UTC. Gespeichert wird
  kanonisch (`2026-11-10T08:00:00Z`).
- Außerhalb des Zeitraums hat eine Freigabe keine Wirkung. Die Rechte werden bei jeder Anfrage neu aufgelöst: eine
  Freigabe beginnt und endet auf die Sekunde, auch in bereits offenen Sitzungen.
- Antworten nennen den Zustand (`active`, `scheduled`, `expired`). Abgelaufene Freigaben bleiben zur Nachvollziehbarkeit
  stehen, bis man sie entfernt („Remove expired grants“); neu anlegen lassen sich abgelaufene nicht.
- Befristete Rollen zählen nicht für die Regel, dass ein aktiver Benutzer `manageAccess` behalten muss: dafür zählt nur
  die dauerhafte Rolle.

### Erlaubte Netze

Administratoren eines Mandanten (`manageAccess`) legen unter `/admin/network` oder per API fest, von welchen
IP-Adressen und Netzen (IPv4/IPv6, CIDR) dessen Benutzer arbeiten dürfen. Eine leere Liste erlaubt alles.

    curl localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN"     # Liste und eigene Adresse
    curl -X PUT localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"networks":["192.168.10.0/24","2001:db8::/32"]}'

- Geprüft wird bei der Anmeldung (nach dem Passwort; außerhalb: 403 mit Meldung) und bei jeder Anfrage. Ein Token, das von
  einer anderen Adresse kommt, gilt dort nicht; die Sitzung bleibt für erlaubte Adressen bestehen.
- Eine Liste, die die eigene Adresse ausschließt, wird abgelehnt: so sperrt sich niemand selbst aus. Haben sich die
  Administratoren eines Mandanten trotzdem ausgesperrt, setzen Systemadministratoren (`manageTenants`) die Liste auf der
  Mandantenseite oder per `PUT /api/v1/tenants/<name>/networks` zurück.
- Der Bereich `system` wird nicht eingeschränkt.
- Clients am Unix-Socket gelten als `127.0.0.1`. Replikationsziele brauchen ihre Adresse in der Liste der Quelle.
- Hinter einem Reverse-Proxy: `TRUSTED_PROXIES` (Adressen oder Netze, durch Komma getrennt) nennen. Nur von diesen
  Proxys gilt `X-Forwarded-For`, und zwar der letzte Eintrag, der kein vertrauter Proxy ist. Ohne die Variable zählt
  die Adresse der Verbindung; dann sieht der Server bei einem Proxy nur dessen Adresse.
- Die Listen stehen in `TENANTS_FILE` (Feld `networks`).

Erster Start: siehe Mandanten. Erzeugte Passwörter bitte unter `/admin/account` ändern; danach werden die Variablen
ignoriert. Administrator-Passwort eines Mandanten verloren: ein anderer Administrator des Mandanten setzt es zurück.
Gibt es keinen mehr, lässt sich der Mandant nur noch über `USERS_FILE` reparieren.

    TOKEN=$(curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"user":"admin","password":"..."}' | jq -r .token)
    curl localhost:8080/sql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT * FROM orders"}'

- Anmeldung: `/admin` nutzt ein Cookie (HttpOnly, SameSite=Strict), alle REST-Routen nur Bearer-Tokens. Tokens gelten
  12 Stunden, liegen nur als Hash im Speicher und enden bei Neustart, Passwortwechsel, Deaktivieren oder Löschen.
- Passwörter: mindestens 12 Zeichen, PBKDF2-HMAC-SHA256 mit 600 000 Runden. Nach 5 Fehlversuchen ist der Name 1 Minute
  gesperrt, auch wenn er nicht existiert. Dadurch kann ein Angreifer die Anmeldung eines Namens zeitweise blockieren.
- Benutzer aller Mandanten liegen in `USERS_FILE` (Standard `data/hdb-users.json`, Rechte 0600), nicht im Anweisungsprotokoll.
  Eine beschädigte Datei bricht den Start ab. Sicherungen müssen die Datei einschließen.
- Das Log enthält weiterhin alle Daten im Klartext; die Rechte gelten nur für den Zugriff über HTTP.
- Tokens, Cookies und Passwörter gehen im Klartext über HTTP: im Netz nur hinter TLS betreiben. Das Cookie erhält
  `Secure`, wenn der Proxy `X-Forwarded-Proto: https` setzt.

Durchgesetzt wird an einer Stelle: `TenantDatabases` wählt die Datenbank des angemeldeten Mandanten, und dort umschließt
`SecuredSqlUseCase` den Kern. Alle eingehenden Adapter sehen nur `TenantDatabases`.
`SecurityGate` setzt je Anfrage die Identität und lässt nur die öffentlichen Pfade ohne Anmeldung durch.

## Tabellenspeicher

    CREATE TABLE klein (id INTEGER, name VARCHAR) USING JSON

Beim Anlegen wählt man im Admin-Formular, per `USING` oder im Feld `storage` von `POST /api/v1/tables`, wo eine Tabelle
liegt. Ohne Angabe gilt `MEMORY`. Abfragen laufen immer im Hauptspeicher, der Unterschied betrifft nur die Dauerhaftigkeit.
Der Speicher lässt sich später nicht ändern; dafür Tabelle neu anlegen und Daten kopieren.

| Speicher | Repository | Dauerhaft durch | Schreiben kostet |
|---|---|---|---|
| `MEMORY` | `MemoryTableRepository` | Anweisungsprotokoll (siehe Persistenz) | eine Zeile im Log |
| `FILE` | `FileTableRepository` | `tables/file/<name>.tbl` (Text, tabulatorgetrennt) | ganze Datei neu |
| `JSON` | `JsonTableRepository` | `tables/json/<name>.json` | ganze Datei neu |
| `BINARY` | `BinaryTableRepository` | `tables/binary/<name>.bin` (kompakt, mit SHA-256) | ganze Datei neu |
| `BSON` | `BsonTableRepository` | `tables/bson/<name>.bson` (ein BSON-Dokument) | ganze Datei neu |

Die Pfade liegen im Verzeichnis des Mandanten (`TENANTS_DIR/<mandant>`, siehe Mandanten). `RoutingTableRepository` verteilt die Tabellen, Namen sind über alle Speicher
eindeutig. `GET /stats` und `GET /api/v1/stats` zeigen `storage`.

- `FILE`-, `JSON`-, `BINARY`- und `BSON`-Tabellen stehen nie im Anweisungsprotokoll: jede Tabelle hat genau eine dauerhafte Quelle.
- `BINARY`: little-endian, Zahlen bitgenau (int64, IEEE-754 double), Text als UTF-8 mit Längenangabe, exakte
  Dezimalzahlen als Text. Am Ende steht eine SHA-256-Prüfsumme; eine beschädigte Datei bricht den Start ab.
  Aufbau im Kommentar von `BinaryTableRepository`.
- `BSON`: `{format: "hdb-table", version: 1, name, columns: [{name, type}], rows: [[...], ...]}`. Ganzzahlen sind int64,
  `DOUBLE`/`REAL` double, `BOOLEAN` bool, alles andere string (auch `DECIMAL`, damit keine Stelle verloren geht).
  Lesbar etwa mit `bsondump tables/bson/<name>.bson`. Gelesen wird streng: unbekannte BSON-Typen, falsche Längen oder
  Werte, die nicht zum Spaltentyp passen, brechen den Start ab. BSON erlaubt höchstens 2 GB je Datei, MongoDB nimmt
  nur Dokumente bis 16 MB an.
- Geschrieben wird am Commit-Punkt, also nach jeder Anweisung oder beim `COMMIT`; `ROLLBACK` erreicht die Datei nie.
  Dateien werden per temporärer Datei, `fsync` und `rename` ersetzt, es liegt also der alte oder der neue Stand vor.
- Bei jeder Änderung wird die ganze Datei neu geschrieben. Für große oder oft geänderte Tabellen ist `MEMORY` die bessere Wahl.
- Eine Transaktion über mehrere Dateien oder über Datei und Log ist bei einem Absturz mitten im `COMMIT` nicht atomar:
  Dateien werden nacheinander geschrieben, das Log zuletzt.
- Eine beschädigte Datei, oder derselbe Tabellenname in zwei Speichern, bricht den Start ab.
- Die Dateien sind Klartext. Sicherungen des Servers müssen `TENANTS_DIR` einschließen.

## Sichern und Wiederherstellen

Nur für die Rolle `admin`, in der Administrationsoberfläche (`/admin/backups`), im Fiori-Frontend und per REST:

    curl -X POST localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d '{"label": "vor dem Update"}'
    curl localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN"
    curl -o sicherung.hdbbak localhost:8080/api/v1/backups/<name>/content -H "Authorization: Bearer $TOKEN"
    curl -X POST --data-binary @sicherung.hdbbak localhost:8080/api/v1/backups/import \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/octet-stream'
    curl -X POST localhost:8080/api/v1/backups/<name>/restore -H "Authorization: Bearer $TOKEN"

- Sicherungen gehören zum Mandanten: Administratoren sehen und erzeugen nur Sicherungen ihres Mandanten, eine Wiederherstellung
  ersetzt nur dessen Tabellen, und jeder Mandant hat seinen eigenen Zeitplan.
- Eine Sicherung ist eine Datei (`*.hdbbak`, Rechte 0600) in `TENANTS_DIR/<mandant>/backups`. Sie enthält alle Tabellen
  aller Speicher mit Schema, Speicherart und exakten Werten und endet mit einer SHA-256-Prüfsumme. Sie ist nicht verschlüsselt.
- Sichern braucht einen ruhenden Stand: bei einer offenen Transaktion wird abgelehnt. Die Datenbank bleibt sonst benutzbar,
  ist aber während des Kopierens gesperrt. Eine Sicherung liegt vollständig im Speicher, auch beim Hoch- und Herunterladen.
- Wiederherstellen ersetzt alle Tabellen. Die Datei wird vorher vollständig geprüft, dann entsteht automatisch die
  Sicherheitskopie `before-restore`, mit der sich auch ein Erfolg rückgängig machen lässt. Schlägt das Ersetzen fehl, wird der alte
  Stand zurückgespielt. Bei einem Absturz mitten im Ersetzen kann ein Mischzustand bleiben: dann die Sicherheitskopie
  wiederherstellen. Sicherheitskopien werden nicht automatisch gelöscht.
- Benutzer gehören nicht zur Sicherung: eine Wiederherstellung sperrt niemanden aus und bringt keine alten Passwörter zurück.
  `USERS_FILE` muss getrennt gesichert werden.
- Hochgeladene Dateien gelten als nicht vertrauenswürdig. Die Prüfsumme erkennt Beschädigung, nicht Fälschung; Namen, Typen und
  Werte werden deshalb immer geprüft. Hochladen stellt noch nichts wieder her.
- `MAX_REQUEST_MB` (Standard 256) begrenzt Anfragen und damit die Größe beim Hochladen. Ohne Anmeldung gelten höchstens 64 KB.
- Sicherungen liegen auf demselben Datenträger wie die Daten: für den Schutz vor dessen Ausfall müssen sie zusätzlich an
  einen anderen Ort kopiert werden.

Zeitplan und Aufbewahrung sind standardmäßig aktiv: alle 24 Stunden eine Sicherung, 7 geplante und 5 Sicherheitskopien bleiben.
Einstellbar in beiden Oberflächen und per `GET|PUT /api/v1/backups/schedule`, gespeichert in `backups/schedule.json` des Mandanten.

    curl -X PUT localhost:8080/api/v1/backups/schedule -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"enabled": true, "intervalHours": 6, "keepScheduled": 28, "keepSafety": 5}'

- Die erste Sicherung entsteht kurz nach dem Start, sobald es Tabellen gibt. Ein Neustart setzt die Frist nicht zurück.
  `BACKUP_TICK_SECONDS` (Standard 60) legt fest, wie oft auf Fälligkeit geprüft wird.
- Die Aufbewahrung löscht nur die Arten `scheduled` und `safety`, die ältesten zuerst und erst nach einer erfolgreichen neuen
  Sicherung. Eigene und hochgeladene Sicherungen bleiben immer. Die Labels `scheduled` und `before-restore` sind deshalb reserviert.
  Weniger aufzubewahren wirkt sofort.
- Scheitert eine geplante Sicherung, etwa wegen einer offenen Transaktion, erscheint das in den Oberflächen und im Log; nach
  5 Minuten folgt der nächste Versuch.
- Die Aufbewahrung zählt, sie prüft keinen Inhalt: ein unbemerkt falscher Datenstand verdrängt nach `keepScheduled` Läufen alle
  älteren geplanten Stände. Wichtige Stände deshalb als eigene Sicherung anlegen.

## Replikation

Ein Mandant lässt sich auf einen anderen hdb-Server spiegeln: eine Quelle, beliebig viele Ziele, Änderungen fließen nur
von der Quelle zum Ziel. Das Ziel holt zuerst einen vollständigen Stand und danach jede bestätigte Änderung, für alle
Speicherarten (`MEMORY`, `FILE`, `JSON`). Ein Ziel kann selbst Quelle sein (A -> B -> C).

Einrichten auf dem Ziel, als Administrator des Ziel-Mandanten, unter `/admin/replication` oder per API. Auf der Quelle
genügt ein Benutzer mit der Rolle `viewer`:

    curl -X PUT localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"url":"https://primary:8080","tenant":"default","user":"replica","password":"...","intervalSeconds":2}'
    curl localhost:8081/api/v1/replication -H "Authorization: Bearer $TOKEN"              # Zustand
    curl -X POST localhost:8081/api/v1/replication/resync -H "Authorization: Bearer $TOKEN"  # vollständig neu holen
    curl -X DELETE localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN"  # beenden

- Der erste Lauf ersetzt alle Tabellen des Ziel-Mandanten. Solange die Replikation läuft, nimmt das Ziel keine
  Schreibzugriffe an (403), auch kein `BEGIN` und keine Wiederherstellung; Lesen, Sicherungen und Statistik gehen.
  Nach dem Beenden behält das Ziel seinen Stand und ist wieder beschreibbar, etwa um es nach einem Ausfall der Quelle
  zu übernehmen.
- Die Quelle liefert `GET /api/v1/replication/snapshot` (Stand im Sicherungsformat, Position in `X-Hdb-Epoch` und
  `X-Hdb-Sequence`) und `GET /api/v1/replication/changes?epoch=&since=&max=`. Jede Änderung ist eine einzelne Anweisung
  oder eine ganze Transaktion; das Ziel spielt sie als Einheit ein. Zurückgerollte Transaktionen erscheinen nie.
- Der Änderungsstrom liegt nur im Speicher. Nach einem Neustart oder einer Wiederherstellung der Quelle beginnt eine neue
  Epoche, nach einem Neustart des Ziels ebenso: dann holt das Ziel einen vollständigen Stand. Das gilt auch, wenn es weiter
  zurückliegt, als die Quelle Änderungen aufbewahrt (`REPLICATION_RETAIN`, Standard 10000 je Mandant), oder wenn sich eine
  Änderung nicht einspielen lässt.
- Ausfälle der Quelle meldet das Ziel einmal im Log und in `lastError`, danach versucht es es im eingestellten Abstand
  (mindestens 5 Sekunden) weiter und holt auf. Abgelaufene Sitzungen erneuert es selbst.
- Das Passwort für die Quelle liegt im Klartext in `TENANTS_DIR/<mandant>/replication.json` (Rechte 0600), damit sich
  das Ziel neu anmelden kann. Die API gibt es nie aus; ein leeres Passwort beim Ändern behält es, aber nur für dieselbe
  Quelle und denselben Benutzer.
- Die Quelle wird mit den Rechten des Servers abgefragt. `REPLICATION_ALLOWED_HOSTS` (durch Komma getrennt) begrenzt
  die erlaubten Hosts; ohne die Variable dürfen Mandanten-Administratoren jede http(s)-Adresse eintragen.
- Zwischen Servern im Netz nur über TLS betreiben: Zugangsdaten und Daten gehen sonst im Klartext.
- Benutzer werden nicht repliziert, wie bei Sicherungen.

## Persistenz

Command-Log (Write-Ahead-Log) über den Port `IStatementLog`, Adapter `FileStatementLog`.
Jede erfolgreiche Änderung an `MEMORY`-Tabellen (`CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`) wird angehängt, beim Start spielt `recover()` das Log ein.
Nach 1000 Anweisungen oder per `POST /checkpoint` wird das Log kompakt neu geschrieben.
Datei: `TENANTS_DIR/<mandant>/hdb.log`, je Mandant eine (siehe Mandanten). `DATA_FILE` nennt nur noch den bisherigen Ort für die Umstellung.

## Spaltenspeicher: Dictionary + Delta-Merge

Jede Spalte (`domain/column.d`) besteht aus einem sortierten Main-Store (Dictionary + Codes) und einem
Delta-Store (unsortiertes Dictionary + Codes). `INSERT` landet im Delta. Der Delta-Merge baut das sortierte
Dictionary neu auf und schreibt alle Codes um; er läuft im Hintergrund (siehe unten), automatisch ab 1000
Delta-Zeilen, per `POST /merge` und einmal synchron nach dem Start. `WHERE` wird nur pro DISTINCT-Wert ausgewertet, danach werden Codes
gescannt. `GET /stats` zeigt Zeilen und DISTINCT-Werte je Spalte (Main/Delta).

## GROUP BY

    SELECT customer, COUNT(*), SUM(amount) FROM orders WHERE amount >= 10 GROUP BY customer

Erlaubt sind die Gruppierungsspalte, `COUNT(*)` und `SUM(x)`. Die Gruppe wird je DISTINCT-Schlüssel des
Dictionarys (Main und Delta) bestimmt, nicht je Zeile. Ergebnis sortiert nach Gruppenwert.

## Bitpacking

Die Main-Codes liegen in `domain/packed_vector.d`: jeder Code belegt nur `ceil(log2(distinct))` Bits statt 32.
`GET /stats` zeigt `mainBits` und `mainCodeBytes` je Spalte.

## ORDER BY und weitere Aggregate

    SELECT n, MIN(q), MAX(q), AVG(w) FROM p WHERE q >= 1 GROUP BY n ORDER BY AVG(w) DESC, n
    SELECT n FROM p ORDER BY q DESC

- Aggregate: `COUNT(*)`, `SUM(x)`, `AVG(x)` (nur numerisch), `MIN(x)`, `MAX(x)` (auch Text); auch ohne `GROUP BY`.
- `ORDER BY` mit mehreren Schlüsseln, `ASC`/`DESC`. Ohne Aggregation darf nach jeder Tabellenspalte sortiert
  werden, auch nach nicht ausgewählten. Mit Aggregation: Ergebnisspalte, Ausdruck wie im SELECT oder Position (1-basiert).
- Die Sortierung ist stabil. Ohne `ORDER BY` sind Gruppen nach dem Gruppenwert sortiert.
- Ergebnisspalten heißen jetzt `COUNT` und z.B. `SUM(amount)`.
- Aggregate ignorieren NULL; ohne Werte liefern `SUM`/`AVG`/`MIN`/`MAX` NULL, `COUNT` liefert 0.

## HAVING, LIMIT, OFFSET

    SELECT g, SUM(v) FROM h GROUP BY g HAVING COUNT(*) >= 2 ORDER BY SUM(v) DESC LIMIT 10 OFFSET 20

- `HAVING ausdruck op wert`: Ausdruck ist ein Aggregat oder die Gruppierungsspalte; er muss nicht im `SELECT` stehen.
- `LIMIT n [OFFSET m]` wirkt nach `ORDER BY`. `OFFSET` gibt es nur zusammen mit `LIMIT`.
- Reihenfolge: WHERE, GROUP BY, HAVING, ORDER BY, LIMIT.

## UPDATE und DELETE

    UPDATE orders SET amount = 120.5, customer = 'ACME' WHERE id = 7
    DELETE FROM orders WHERE amount < 10

- `DELETE` markiert Zeilen in einem Löschvektor; alle Abfragen überspringen sie.
- `UPDATE` ist insert-only: die alte Zeilenversion wird gelöscht, die neue landet im Delta (am Ende der Tabelle,
  daher ändert sich die Reihenfolge ohne `ORDER BY`).
- Gelöschte Zeilen werden beim Delta-Merge (`POST /merge`, nach dem Start) physisch entfernt, automatisch ab 1000 gelöschten
  Zeilen, wenn sie mehr als die Hälfte der Tabelle ausmachen. Beim Checkpoint werden sie nicht ins Log geschrieben.
- Beide Anweisungen werden ins Log geschrieben und beim Start deterministisch wieder eingespielt.
- `GET /stats` zeigt `rows` (lebende Zeilen) und `deletedRows`.

## DROP TABLE

    DROP TABLE orders

Wird geloggt und beim Start wiederholt. In einer Transaktion stellt `ROLLBACK` die Tabelle samt Daten wieder her.

## JOIN

    SELECT c.name, SUM(o.amt) FROM customers c JOIN orders o ON c.id = o.cid
    WHERE o.amt >= 2 GROUP BY c.name ORDER BY SUM(o.amt) DESC

- `[INNER] JOIN tabelle [alias] ON a = b`, auch mehrere hintereinander (links-tief). Umgesetzt als Hash-Join.
- Das Join-Ergebnis ist eine temporäre Spaltentabelle mit Spalten `alias.spalte`; WHERE, GROUP BY, HAVING,
  ORDER BY und Aggregate laufen darauf unverändert. Unqualifizierte Namen gehen, wenn sie eindeutig sind.
- Ein Alias auf einer einzelnen Tabelle (`FROM orders o`) erlaubt `o.spalte`.
- Nur Gleichheits-Joins (INNER und LEFT). Self-Joins brauchen zwei verschiedene Aliase.
- Beide Seiten werden für den Join kopiert (Speicher O(Zeilen)), allerdings nur die Zeilen, die nach dem
  WHERE-Pushdown (siehe unten) übrig bleiben.

## NULL und LEFT JOIN

    SELECT c.name, COUNT(o.id) FROM customers c LEFT JOIN orders o ON c.id = o.cid GROUP BY c.name
    SELECT c.name FROM customers c LEFT JOIN orders o ON c.id = o.cid WHERE o.id IS NULL

- `LEFT [OUTER] JOIN`: linke Zeilen ohne Treffer bleiben erhalten, die rechten Spalten sind NULL.
- NULL-Literal in `INSERT` und `UPDATE ... SET x = NULL`; `WHERE x IS [NOT] NULL`.
- Vergleiche mit NULL sind nie wahr (`x = NULL` trifft nichts, dafür gibt es `IS NULL`). NULL passt in keinem Join auf NULL.
- `COUNT(spalte)` zählt nur Nicht-NULL-Werte, `COUNT(*)` alle Zeilen. NULL bildet in `GROUP BY` eine eigene Gruppe.
- `ORDER BY`: NULL sortiert zuerst (bei `DESC` zuletzt). Im JSON erscheint NULL als `null`, im Log als `NULL`.

## Transaktionen

    POST /sql {"statement": "BEGIN"}                      -> {"transaction": "<id>", ...}
    POST /sql {"statement": "INSERT ..."}  + Header  X-Transaction-Id: <id>
    POST /sql {"statement": "COMMIT"}      + Header  X-Transaction-Id: <id>   (oder ROLLBACK)

Die ID kann statt im Header auch als Feld `"transaction"` im JSON-Body stehen.

- Eine offene Transaktion sperrt die Datenbank für alle anderen Sitzungen (serialisierbar, ein Schreiber).
  Andere Anfragen bekommen sofort 400 "gesperrt"; es wird nicht gewartet. Auch `/tables`, `/stats`, `/merge`
  und `/checkpoint` sind währenddessen gesperrt.
- Eigene Änderungen sind in der Transaktion sichtbar. Ohne Aktivität werden Transaktionen nach 30 s zurückgerollt.
- Rollback: vor der ersten Änderung einer Tabelle wird ein Snapshot angelegt (Copy-on-first-write, O(Tabelle)).
  Auch `CREATE TABLE` wird zurückgerollt.
- Log: erst beim `COMMIT` wird die ganze Transaktion als Gruppe `BEGIN ... COMMIT` geschrieben. Beim Start werden
  nur vollständige Gruppen eingespielt; ein unvollständiger Rest wird verworfen.
- Ein fehlerhaftes Statement macht die Transaktion nicht ungültig, hinterlässt aber keine Teiländerung.
- Ohne `BEGIN` läuft jede Anweisung wie bisher als eigene Transaktion (Autocommit).
- Keine Savepoints und keine verschachtelten Transaktionen.

## WHERE-Pushdown

Die WHERE-Bedingung wird vor dem Kopieren und Joinen auf der betroffenen Tabelle ausgewertet, wenn das das
Ergebnis nicht verändert. Das spart Kopierarbeit und verkleinert die Hash-Tabelle.

- Vorgezogen wird bei der ersten Tabelle und bei Tabellen eines `INNER JOIN`.
- Nicht vorgezogen wird bei einer `LEFT JOIN`-Tabelle, weil deren Spalten mit NULL aufgefüllt werden
  (`WHERE o.id IS NULL` findet gerade die Zeilen ohne Treffer). Dort gilt die Bedingung nach dem Join.
- Unqualifizierte Spalten werden nur vorgezogen, wenn sie in genau einer Tabelle vorkommen. Bei Mehrdeutigkeit
  gibt es wie bisher einen Fehler nach dem Join.
- Bei `FROM tabelle alias` ohne Join werden nur die Treffer in die Alias-Kopie übernommen.
- Das Ergebnis ist immer dasselbe wie ohne Pushdown. Der Zähler `pushedDownFilters` im `SqlService` dient der Diagnose.

## AND, OR und Klammern in WHERE

    SELECT k FROM w WHERE (n = 'a' OR n = 'b') AND v IS NOT NULL
    UPDATE w SET v = 0 WHERE n = 'a' AND k >= 3
    DELETE FROM w WHERE k = 1 OR k = 2

- Bedingungen `spalte op wert` und `spalte IS [NOT] NULL`, verknüpft mit `AND`, `OR` und Klammern.
  `AND` bindet stärker als `OR`. `<>` ist gleichbedeutend mit `!=`. Schlüsselwörter in Textliteralen
  (`'x AND y'`) bleiben unangetastet.
- Gilt für `SELECT`, `UPDATE` und `DELETE`. `NOT` gibt es bewusst nicht: Mit NULL-Werten (Dreiwertlogik) wäre
  das Komplement einer Treffermenge falsch. Ohne `NOT` sind Schnitt (`AND`) und Vereinigung (`OR`) der
  Treffermengen exakt.
- Pushdown: Die Bedingung wird in ihre obersten `AND`-Teile zerlegt. Jeder Teil, dessen Spalten alle zu genau
  einer vorziehbaren Tabelle gehören (erste Tabelle oder `INNER JOIN`), wird vor dem Join ausgewertet, auch ein
  `OR` innerhalb einer Tabelle. Teile über mehrere Tabellen und Teile auf der NULL-ergänzten Seite eines
  `LEFT JOIN` gelten nach dem Join.

## IN, BETWEEN, LIKE

    SELECT k FROM p WHERE n LIKE 'a%' AND k IN (1, 4, 6)
    SELECT k FROM p WHERE v BETWEEN 2 AND 5 OR n NOT LIKE '%an%'

- `spalte [NOT] IN (wert, ...)`, `spalte [NOT] BETWEEN a AND b` (Grenzen inklusive) und `spalte [NOT] LIKE 'muster'`
  mit `%` (beliebig viele Zeichen) und `_` (genau ein Zeichen); Groß-/Kleinschreibung zählt, ein Escape-Zeichen gibt
  es nicht. `LIKE` gilt nur für Textspalten.
- Wie alle Vergleiche sind auch diese nie wahr, wenn der Spaltenwert NULL ist, also auch `NOT IN`,
  `NOT BETWEEN` und `NOT LIKE`. `x NOT IN (1, NULL)` ist nie wahr, `x IN (1, NULL)` trifft nur die 1.
- Die Prüfung läuft wie die übrigen Vergleiche einmal pro DISTINCT-Wert des Dictionarys; das `AND` innerhalb von
  `BETWEEN` gehört zum Operator und wird nicht als logisches `AND` gelesen.
- Gilt in `SELECT`, `UPDATE` und `DELETE` und wird wie jede andere Bedingung vor einem Join vorgezogen.

## Mehrere Gruppierungsspalten

    SELECT region, product, COUNT(*), SUM(qty) FROM sales GROUP BY region, product ORDER BY region, product

- `GROUP BY spalte [, spalte ...]`, auch mit qualifizierten Namen (`c.name`) nach einem Join. Duplikate in der Liste
  zählen einmal. Im `SELECT` und in `HAVING` sind alle Gruppierungsspalten und Aggregate erlaubt, die
  Gruppierungsspalten müssen aber nicht ausgewählt werden.
- Umsetzung: Je Gruppierungsspalte bekommt jeder DISTINCT-Wert (Main und Delta) eine dichte Id; je Treffer werden die
  Ids zu einem Schlüssel kombiniert (gemischte Basis, `ulong`). Es werden also keine Werte pro Zeile verglichen.
  Bei einer unrealistisch großen Zahl möglicher Kombinationen gibt es einen Fehler.
- Ohne `ORDER BY` sind die Gruppen lexikographisch nach den Schlüsselwerten sortiert, NULL zuerst. NULL bildet
  je Spalte einen eigenen Wert.

## DISTINCT

    SELECT DISTINCT region, product FROM sales ORDER BY region
    SELECT COUNT(DISTINCT customer), SUM(DISTINCT price) FROM sales

- `SELECT DISTINCT ...` entfernt doppelte Ergebniszeilen, auch mit `*`. Ohne Aggregate wird das als `GROUP BY` über
  alle ausgewählten Spalten ausgeführt (Gruppierung über die Dictionary-Ids). Das Ergebnis ist daher nach den
  Werten sortiert, nicht in Einfügereihenfolge. `ORDER BY` darf nur ausgewählte Spalten nennen (wie in SQL).
- Mit Aggregaten oder `GROUP BY` werden die fertigen Ergebniszeilen dedupliziert, danach folgen `ORDER BY` und `LIMIT`.
- `COUNT(DISTINCT x)`, `SUM(DISTINCT x)`, `AVG(DISTINCT x)`: NULL zählt nicht, ein Wert zählt je Gruppe einmal, auch wenn
  er im Main- und im Delta-Store vorkommt. `MIN`/`MAX` mit `DISTINCT` sind gleichbedeutend mit ohne.
  `COUNT(DISTINCT *)` gibt es nicht.

## Delta-Merge im Hintergrund

Der Merge sperrt die Datenbank nur noch kurz. Er läuft in drei Phasen (`domain/column.d`):

1. **Einfrieren** (unter der Sperre, kurz): `beginMerge()` merkt sich Main und die aktuellen Delta-Zeilen.
2. **Aufbau** (ohne Sperre, in einem Hintergrund-Thread): `MergeJob.run()` baut das sortierte Dictionary und die neu
   gepackten Codes. Er liest nur die eingefrorenen Daten; das Main wird nie verändert, nur ersetzt, und eingefrorene
   Delta-Einträge bleiben unverändert. Abfragen und Änderungen laufen währenddessen normal weiter.
3. **Umschalten** (unter der Sperre, kurz): `finishMerge()` ersetzt Main. Zeilen, die in der Zwischenzeit ins Delta kamen,
   bekommen ein neues kleines Delta. Zeilennummern ändern sich nicht, weil die eingefrorenen Zeilen schon direkt hinter
   dem Main stehen und das Delta ein eigenes Dictionary hat.

- Ausgelöst wird er automatisch, sobald eine Spalte 1000 Delta-Zeilen hat (nach `INSERT`/`UPDATE`), und per
  `POST /merge`. Das antwortet sofort mit 202 (`STARTED` oder `RUNNING`); `GET /merge` zeigt `running`,
  `completed` und `lastError`. Pro Spalte läuft höchstens ein Merge, insgesamt höchstens ein Merge-Thread.
- Während einer Transaktion bleiben `POST /merge` und `/stats` gesperrt wie alle anderen Aufrufe. Ein schon laufender
  Merge stört die Transaktion nicht; ein Rollback stellt den Snapshot der Tabelle wieder her.
- Beim Einspielen des Logs beim Start werden keine Hintergrund-Merges gestartet; danach läuft ein synchroner Merge.
- Grenzen: Checkpoint, Rollback-Snapshots und der Aufbau temporärer Join-Tabellen laufen weiterhin unter der Sperre.

### Kompaktierung im Hintergrund

Gelöschte Zeilen zu entfernen ändert die Zeilennummern. Auch das läuft in drei Phasen (`domain/table.d`):

1. **Einfrieren** (unter der Sperre): `beginCompaction()` merkt sich Zeilenzahl `N`, die Nummern der lebenden Zeilen
   und je Spalte eine Momentaufnahme (Main + Delta). Ab jetzt protokolliert `markDeleted` jede Löschung.
2. **Aufbau** (ohne Sperre): `CompactionJob.run()` baut aus den lebenden Zeilen neue Spalten mit sortiertem Dictionary.
3. **Umschalten** (unter der Sperre): `finishCompaction()` überträgt, was seit dem Einfrieren geschah.
   Zeilen ab `N` kommen ins Delta der neuen Spalten und stehen direkt hinter den `L` lebenden Zeilen (neue Nummer
   `L + (alt - N)`). Jede protokollierte Löschung wird auf die neue Nummer abgebildet: alte Zeilen über ihren Rang
   unter den lebenden Zeilen, neue Zeilen über die Verschiebung. Ein `UPDATE` ist Löschen plus Einfügen und
   wird damit automatisch richtig übertragen.

- Automatisch ab 1000 gelöschten Zeilen, wenn sie mehr als die Hälfte der Tabelle sind (nach `UPDATE`/`DELETE`), und
  ausdrücklich per `POST /merge` für jede Tabelle mit gelöschten Zeilen. Eine kompaktierte Tabelle wird nicht zusätzlich
  spaltenweise gemergt, denn der Aufbau mergt das Delta mit.
- Während der Kompaktierung werden Spalten dieser Tabelle nicht gemergt, und eine laufende Spalten-Merge verhindert
  den Start der Kompaktierung (sie wird übersprungen und beim nächsten Zyklus nachgeholt).
- Ein Rollback ersetzt die Tabelle durch den Snapshot; ein schon laufender Job arbeitet dann auf der verworfenen Tabelle
  und ist wirkungslos. Zeilennummern werden nirgends über Aufrufe hinweg gehalten, die Umnummerierung ist daher unsichtbar.
