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

## Administrationsoberfläche

`http://localhost:8080/admin` (Adapter `adapters/inbound/admin_web.d`, Templates in `views/`, Skript in `public/admin.js`).

- Dashboard: Kennzahlen je Tabelle, Delta-Merge und Checkpoint auslösen, Tabellen anlegen.
- Tabellenansicht: Filtern (WHERE), Sortieren, Blättern, Zeilen anlegen, bearbeiten und löschen, CSV-Export,
  Tabelle leeren oder löschen, Speicherstatistik je Spalte.
- SQL-Konsole: mehrere Anweisungen mit `;`, Abbruch beim ersten Fehler, `BEGIN` trägt über mehrere Ausführungen.

Tabellen haben keinen Primärschlüssel. Bearbeiten und Löschen einer Zeile treffen deshalb alle Zeilen mit
identischen Werten; die Oberfläche meldet die Anzahl.

Zugriff: Mit `ADMIN_PASSWORD` (Benutzer `ADMIN_USER`, Standard `admin`) gilt HTTP Basic Auth, ohne Passwort ist
`/admin` nur von localhost erreichbar. Basic Auth überträgt das Passwort unverschlüsselt, daher im Netz nur hinter
TLS betreiben. Hinter einem Reverse-Proxy auf demselben Host erscheinen alle Clients als localhost: dort immer ein
Passwort setzen. Schreibende Anfragen von fremden Origins werden abgewiesen. Die REST-Endpunkte (`/sql` usw.) sind
davon nicht betroffen und bleiben ungeschützt.

## Persistenz

Command-Log (Write-Ahead-Log) über den Port `IStatementLog`, Adapter `FileStatementLog`.
Jede erfolgreiche Änderung (`CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`) wird angehängt, beim Start spielt `recover()` das Log ein.
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
