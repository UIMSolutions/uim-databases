# relational

An in-memory relational database with a vibe.d 0.10.3 REST API, built as a hexagonal / Clean Architecture.
All code is `@safe`; the domain and application layers depend on Phobos only.

Class and component diagrams: [uml.md](uml.md).

## Setup

```bash
dub test                    # unit tests of every layer
dub run -c executable       # REST server on http://127.0.0.1:8082
```

Use the `library` configuration (the default) to embed the database in another program without HTTP.

## Configuration

Values are resolved from four sources. A later source overrides an earlier one:

| Source | Keys / variables |
|---|---|
| 1. Built-in defaults | `AppConfig` in `infrastructure/configuration/settings.d` |
| 2. `config/default.json`, or the file named by `RELATIONAL_CONFIG_FILE` | `databaseName`, `host`, `port`, `logLevel` |
| 3. Environment | `PORT` (set by Cloud Foundry), then `RELATIONAL_DATABASE_NAME`, `RELATIONAL_HOST`, `RELATIONAL_PORT`, `RELATIONAL_LOG_LEVEL` |
| 4. `VCAP_SERVICES` | `credentials` of the service instance named or tagged `relational-config` |

An invalid value stops the server at startup with exit code 1. On Cloud Foundry, set `RELATIONAL_HOST=0.0.0.0`.

## Architecture

```
source/
  app.d                         composition root: the only place that wires adapters to the core
  uim/databases/relational/
    domain/                     business rules (Phobos only)
      entities/                 Table (aggregate root: rows, unique indexes, all-or-nothing changes)
      types/                    Value, ColumnDefinition, TableSchema, ForeignKey, Condition, Query, QueryResult
      enumerations/             ColumnType, ComparisonOperator, SortDirection
      services/                 comparison, predicates (incl. LIKE), literals, innerJoin
      exceptions/               Validation (400), NotFound (404), Conflict (409) families
    application/                use cases (depends on domain and ports)
      usecases/                 TableCatalogInteractor, RowInteractor, JoinInteractor
      services/                 DatabaseInfoService
      dtos/                     commands and results crossing the ports
    ports/                      interfaces
      usecases/                 ITableCatalogUseCase, IRowUseCase, IJoinUseCase   (driving)
      services/                 IDatabaseInfoService                              (driving)
      repositories/             ITableRepository                                  (driven)
    persistence/repositories/   InMemoryTableRepository (driven adapter)
    infrastructure/             configuration (file, env, VCAP_SERVICES), logging
    presentation/               driving adapters (vibe.d)
      rest/                     REST interface, models, JSON <-> Value conversions, controller
      http/                     routes, error handler, 404
```

Dependencies only point inwards. Presentation depends on the driving ports. Interactors depend on the
driven ports. Persistence implements the driven ports. Only `app.d` sees every layer.

Layers that the skill defines but this module doesn't need yet are not created. Add them when needed:
- `ports/storages`, `ports/messaging` and `ports/gateways`
- `persistence/storages`, `persistence/mappers` and `persistence/records` (for a durable store)
- `infrastructure/security` (XSUAA/JWT), `infrastructure/clients` and `infrastructure/workers`
- `presentation/odata`, `presentation/web`, `presentation/cli` and `presentation/gui`

## REST API

| Method | Path | Body / result |
|---|---|---|
| GET | `/health` | `{status, type, tableCount}` |
| GET | `/stats` | `{name, tableCount, tables:[{name, rowCount, columnCount}]}` |
| GET | `/tables` | `{tables, count}` |
| POST | `/tables` | `{name, columns:[{name, type, nullable?, primaryKey?, unique?, default?}], foreignKeys?:[{column, refTable, refColumn}]}`, returns 201 |
| DELETE | `/tables/:name` | refused (409) while another table references it |
| GET | `/tables/:name/schema` | `{tableName, primaryKey, columns, foreignKeys}` |
| GET | `/tables/:name/count` | `{count}` |
| POST | `/tables/:name/insert` | one row object, or `{rows:[...]}`; returns 201 `{inserted, rowIds}` |
| POST | `/tables/:name/select` | `{columns?, where?, orderBy?, ascending?, limit?, offset?}`, returns `{columns, rows, count}` |
| POST | `/tables/:name/update` | `{set, where?}`, returns `{updated}` |
| POST | `/tables/:name/delete` | `{where}` (required), returns `{deleted}` |
| GET | `/tables/:name/rows/:pk` | `{row}`; the key is parsed by the primary key's type |
| POST | `/join` | `{leftTable, rightTable, leftColumn, rightColumn, leftWhere?, rightWhere?}`, returns rows with `table.column` keys |

A condition is `{column, op, value}`. The operator `op` is one of `=`, `!=`/`<>`, `>`, `<`, `>=`, `<=`, `LIKE` (`%`, `_`), `IN` (with `value` as an array), `IS NULL` and `IS NOT NULL`. Several conditions are combined with AND.

Column types are `INTEGER`, `FLOAT`, `STRING`, `BOOLEAN`, `DATE` (an ISO 8601 date or date-time) and `JSON` (any value). SQL aliases such as `int`, `varchar` and `double` are also accepted.

Errors return `{"statusMessage": "..."}` with one of these codes:
- **400:** invalid input
- **404:** unknown table or row
- **409:** duplicate key, duplicate name or a referenced table

## Semantics

- **All-or-nothing changes:** a bulk insert or update either changes every row or none.
- **Rejected input:** unknown columns and values of the wrong type are rejected.
- **Primary keys:** a primary key column is always `NOT NULL` and `UNIQUE`.
- **NULL in unique columns:** unique constraints allow several NULLs.
- **Comparisons with NULL:** as in SQL, `= NULL` never matches. Use `IS NULL`. Join keys that are NULL never match.
- **Number comparisons:** integers and floats compare numerically, so `1 = 1.0`.
- **Sorting:** ORDER BY puts NULLs last in both directions. Ties keep insertion order.
- **Foreign keys:**
  - When a table is created, each foreign key must reference an existing table and column.
  - A table that another table references cannot be dropped.
  - Row values are not checked against the referenced table yet.
- **Storage:** data lives in memory only. `ITableRepository` is the extension point for durable storage.
