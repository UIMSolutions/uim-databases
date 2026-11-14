# object

An object / document database: JSON documents in named collections, with queries, sorting, paging and
equality indexes, served by a vibe.d 0.10.3 REST API. It is built as a hexagonal / Clean Architecture.
All code is `@safe`. The domain and application layers depend on Phobos only (documents are `std.json.JSONValue`).

Class and component diagrams: [uml.md](uml.md).

## Setup

```bash
dub test                    # unit tests of every layer
dub run -c executable       # REST server on http://127.0.0.1:8081
```

The `library` configuration (the default) embeds the database in another program without HTTP. Wire
`InMemoryCollectionRepository` to the interactors yourself, the way `source/app.d` does.

## Configuration

Values are resolved from four sources. A later source overrides an earlier one:

| Source | Keys / variables |
|---|---|
| 1. Built-in defaults | `AppConfig` in `infrastructure/configuration/settings.d` |
| 2. `config/default.json`, or the file named by `OBJECT_CONFIG_FILE` | `databaseName`, `host`, `port`, `logLevel`, `defaultCollection` |
| 3. Environment | `PORT` (set by Cloud Foundry), then `OBJECT_DATABASE_NAME`, `OBJECT_HOST`, `OBJECT_PORT`, `OBJECT_LOG_LEVEL`, `OBJECT_DEFAULT_COLLECTION` |
| 4. `VCAP_SERVICES` | `credentials` of the service instance named or tagged `object-config` |

`defaultCollection` (default `default`) is created at startup and cannot be dropped; set it to an empty
string for none. An invalid value stops the server at startup with exit code 1. On Cloud Foundry, set
`OBJECT_HOST=0.0.0.0`.

## Architecture

```
source/
  app.d                         composition root: the only place that wires adapters to the core
  uim/databases/object/
    domain/                     business rules (Phobos only)
      entities/                 DocumentCollection (aggregate root), Document, FieldIndex
      types/                    FieldPath, Condition, SortOrder, DocumentQuery, identifier rules
      enumerations/             QueryOperator, SortDirection
      services/                 jsonvalues: equality, ordering, index keys, deep copies
      exceptions/               Validation (400), NotFound (404), Conflict (409) families
    application/                use cases (depends on domain and ports)
      usecases/                 CollectionInteractor, DocumentInteractor, QueryInteractor, IndexInteractor
      services/                 DatabaseInfoService
      dtos/                     commands and results crossing the ports
    ports/                      interfaces
      usecases/                 ICollectionUseCase, IDocumentUseCase, IQueryUseCase, IIndexUseCase  (driving)
      services/                 IDatabaseInfoService                                              (driving)
      repositories/             ICollectionRepository                                             (driven)
    persistence/repositories/   InMemoryCollectionRepository (driven adapter)
    infrastructure/             configuration (file, env, VCAP_SERVICES), logging
    presentation/               driving adapters (vibe.d)
      rest/                     REST interface, wire models, Json <-> JSONValue mappers, controller
      http/                     routes, error handler, 404
```

Dependencies only point inwards. Presentation depends on the driving ports. Interactors depend on the
driven ports. Persistence implements the driven ports. Only `app.d` sees every layer.

Layers that the skill defines but this module doesn't need yet are not created. Add them when needed:
- `ports/storages`, `ports/messaging` and `ports/gateways`
- `persistence/storages`, `persistence/mappers` and `persistence/records` (for a durable store)
- `infrastructure/security`, `infrastructure/clients` and `infrastructure/workers`
- `presentation/odata`, `presentation/web`, `presentation/cli` and `presentation/gui`

## REST API

| Method | Path | Body / result |
|---|---|---|
| GET | `/health` | `{status, type, collectionCount}` |
| GET | `/stats` | `{name, collectionCount, documentCount, collections}` |
| GET | `/collections` | `{collections:[{name, documentCount, indexCount, indexes}], count}` |
| POST | `/collections/:name` | no body, returns 201 and the collection |
| GET | `/collections/:name` and `/collections/:name/stats` | the collection |
| DELETE | `/collections/:name` | removes the collection, its documents and indexes |
| DELETE | `/collections/:name/clear` | removes every document; indexes stay defined |
| POST | `/collections/:name/documents` | any JSON object; a string `_id` sets the id (otherwise a UUID), returns 201 |
| POST | `/collections/:name/bulk` | `{documents:[...]}`, all-or-nothing, returns 201 and `{inserted, ids}` |
| GET | `/collections/:name/documents` and `/collections/:name/all` | `{documents, count}` in insertion order |
| GET / PUT / DELETE | `/collections/:name/documents/:id` | PUT replaces the data; `_id` in the body is optional but must match |
| POST | `/collections/:name/find` | `{where?:[{field, op?="==", value}], sort?:{field, ascending?=true}, skip?, limit?}` |
| POST | `/collections/:name/count` | `{where?}`, returns `{count}` |
| GET / POST | `/collections/:name/indexes` | POST `{field}`, returns 201 |
| DELETE | `/collections/:name/indexes/:field` | drops the index |

A document is returned as `{_id, data, createdAt, updatedAt}` (ISO 8601, UTC).

Errors return `{"statusMessage": "..."}` with one of these codes:
- **400:** invalid input, an unknown operator, or dropping the default collection
- **404:** unknown collection, document or index
- **409:** duplicate collection name, document id or index

## Query semantics

- **Fields** are dot paths into nested objects (`address.city`); there is no array indexing.
- **Operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `in`, `exists`. The short forms `eq`, `ne`,
  `gt`, `lt`, `gte` and `lte` also work. An unknown operator is an error (400).
- **Equality** is deep, and numbers compare by value, so `1` equals `1.0`. Objects are equal in any member order.
- **Ranges** (`>`, `<`, `>=`, `<=`) compare numbers with numbers and strings with strings. Any other pair never matches.
- **`!=`** also matches documents that don't have the field. `contains` matches a substring of a string field
  or an element of an array field. `in` needs an array value. `exists` takes `true` (the default) or `false`.
- **Sorting:** documents missing the sort field come last in both directions. Ties keep insertion order.
  Without `sort`, results are in insertion order.
- **Indexes** speed up `==` conditions on the indexed field. Results are the same with or without them.
- **Storage:** data lives in memory only. `ICollectionRepository` is the extension point for durable storage.
