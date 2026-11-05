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
Dazu `POST /api/v1/auth/login|logout|password`, `GET /api/v1/auth/me` und `GET|POST /api/v1/users`,
`PUT|DELETE /api/v1/users/:name`, `POST /api/v1/users/:name/password`. Fehlende Anmeldung ergibt 401, fehlende Rechte 403.
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

Typen: `INTEGER` ist `Edm.Int64`, `DECIMAL` ist `Edm.Double`, `VARCHAR` ist `Edm.String`.

Schlüssel: Tabellen haben keinen Primärschlüssel, deshalb gilt eine Spalte `id` (`INTEGER` oder `VARCHAR`) als Schlüssel.
Der Kern erzwingt keine Eindeutigkeit: `POST` lehnt vorhandene Schlüssel ab, kommt ein Schlüssel trotzdem mehrfach vor
(etwa nach SQL-Änderungen), antworten Zugriffe darauf mit 409 statt mehrere Zeilen zu ändern. Tabellen ohne `id` zeigen die
berechnete Eigenschaft `__rowid`. Das ist nur die Position im Ergebnis, einzelne Zeilen sind dort nicht adressierbar (501).
Tabellen oder Spalten, deren Name kein gültiger OData-Bezeichner ist (etwa `1a`), erscheinen nicht im Dienst.

## Administrationsoberfläche

`http://localhost:8080/admin` (Adapter `adapters/inbound/admin_web.d`, Templates in `views/`, Skript in `public/admin.js`).

- Dashboard: Kennzahlen je Tabelle, Delta-Merge und Checkpoint auslösen, Tabellen anlegen.
- Tabellenansicht: Filtern (WHERE), Sortieren, Blättern, Zeilen anlegen, bearbeiten und löschen, CSV-Export,
  Tabelle leeren oder löschen, Speicherstatistik je Spalte.
- SQL-Konsole: mehrere Anweisungen mit `;`, Abbruch beim ersten Fehler, `BEGIN` trägt über mehrere Ausführungen.

Tabellen haben keinen Primärschlüssel. Bearbeiten und Löschen einer Zeile treffen deshalb alle Zeilen mit
identischen Werten; die Oberfläche meldet die Anzahl.

Die Oberfläche blendet aus, was die Rolle nicht darf; entschieden wird aber immer auf dem Server.

## Benutzer und Rechte

Außer `GET /health`, `GET /api/v1/health` und den Anmeldeseiten verlangt jede Route eine Anmeldung.

| Rolle | Rechte |
|---|---|
| `viewer` | `SELECT`, Tabellen und Statistik lesen |
| `editor` | zusätzlich `INSERT`, `UPDATE`, `DELETE`, Transaktionen |
| `admin` | zusätzlich `CREATE`, `DROP`, Merge, Checkpoint, Benutzerverwaltung (`/admin/users`) |

Rechte gelten für die ganze Datenbank, nicht je Tabelle. Rollenänderungen wirken sofort, auch in laufenden Sitzungen.
Eine offene Transaktion kann nur ihr Besitzer verwenden. Der letzte aktive Administrator lässt sich nicht entfernen.

Erster Start: Gibt es keine Benutzer, wird `ADMIN_USER` (Standard `admin`) mit `ADMIN_PASSWORD` angelegt. Ohne
Passwort wird eines erzeugt und einmalig ins Log geschrieben; bitte unter `/admin/account` ändern. Danach werden beide
Variablen ignoriert. Administrator-Passwort verloren: `USERS_FILE` löschen und neu starten (alle Benutzer sind dann weg).

    TOKEN=$(curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"user":"admin","password":"..."}' | jq -r .token)
    curl localhost:8080/sql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT * FROM orders"}'

- Anmeldung: `/admin` nutzt ein Cookie (HttpOnly, SameSite=Strict), alle REST-Routen nur Bearer-Tokens. Tokens gelten
  12 Stunden, liegen nur als Hash im Speicher und enden bei Neustart, Passwortwechsel, Deaktivieren oder Löschen.
- Passwörter: mindestens 12 Zeichen, PBKDF2-HMAC-SHA256 mit 600 000 Runden. Nach 5 Fehlversuchen ist der Name 1 Minute
  gesperrt, auch wenn er nicht existiert. Dadurch kann ein Angreifer die Anmeldung eines Namens zeitweise blockieren.
- Benutzer liegen in `USERS_FILE` (Standard `data/hdb-users.json`, Rechte 0600), nicht im Anweisungsprotokoll.
  Eine beschädigte Datei bricht den Start ab. Sicherungen müssen die Datei einschließen.
- Das Log enthält weiterhin alle Daten im Klartext; die Rechte gelten nur für den Zugriff über HTTP.
- Tokens, Cookies und Passwörter gehen im Klartext über HTTP: im Netz nur hinter TLS betreiben. Das Cookie erhält
  `Secure`, wenn der Proxy `X-Forwarded-Proto: https` setzt.

Durchgesetzt wird an einer Stelle: `SecuredSqlUseCase` umschließt den Kern, alle eingehenden Adapter sehen nur ihn.
`SecurityGate` setzt je Anfrage die Identität und lässt nur die öffentlichen Pfade ohne Anmeldung durch.

## Tabellenspeicher

    CREATE TABLE klein (id INTEGER, name VARCHAR) USING JSON

Beim Anlegen wählt man im Admin-Formular, per `USING` oder im Feld `storage` von `POST /api/v1/tables`, wo eine Tabelle
liegt. Ohne Angabe gilt `MEMORY`. Abfragen laufen immer im Hauptspeicher, der Unterschied betrifft nur die Dauerhaftigkeit.
Der Speicher lässt sich später nicht ändern; dafür Tabelle neu anlegen und Daten kopieren.

| Speicher | Repository | Dauerhaft durch | Schreiben kostet |
|---|---|---|---|
| `MEMORY` | `MemoryTableRepository` | Anweisungsprotokoll (siehe Persistenz) | eine Zeile im Log |
| `FILE` | `FileTableRepository` | `TABLES_DIR/file/<name>.tbl` (Text, tabulatorgetrennt) | ganze Datei neu |
| `JSON` | `JsonTableRepository` | `TABLES_DIR/json/<name>.json` | ganze Datei neu |

`TABLES_DIR` ist standardmäßig `data/tables`. `RoutingTableRepository` verteilt die Tabellen, Namen sind über alle Speicher
eindeutig. `GET /stats` und `GET /api/v1/stats` zeigen `storage`.

- `FILE`- und `JSON`-Tabellen stehen nie im Anweisungsprotokoll: jede Tabelle hat genau eine dauerhafte Quelle.
- Geschrieben wird am Commit-Punkt, also nach jeder Anweisung oder beim `COMMIT`; `ROLLBACK` erreicht die Datei nie.
  Dateien werden per temporärer Datei, `fsync` und `rename` ersetzt, es liegt also der alte oder der neue Stand vor.
- Bei jeder Änderung wird die ganze Datei neu geschrieben. Für große oder oft geänderte Tabellen ist `MEMORY` die bessere Wahl.
- Eine Transaktion über mehrere Dateien oder über Datei und Log ist bei einem Absturz mitten im `COMMIT` nicht atomar:
  Dateien werden nacheinander geschrieben, das Log zuletzt.
- Eine beschädigte Datei, oder derselbe Tabellenname in zwei Speichern, bricht den Start ab.
- Die Dateien sind Klartext. Sicherungen müssen `TABLES_DIR` einschließen.

## Persistenz

Command-Log (Write-Ahead-Log) über den Port `IStatementLog`, Adapter `FileStatementLog`.
Jede erfolgreiche Änderung an `MEMORY`-Tabellen (`CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`) wird angehängt, beim Start spielt `recover()` das Log ein.
Nach 1000 Anweisungen oder per `POST /checkpoint` wird das Log kompakt neu geschrieben.
Datei: Umgebungsvariable `DATA_FILE` (Standard `data/hana-lite.log`).

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
