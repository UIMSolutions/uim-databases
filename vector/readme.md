# vector

A vector database for exact k-nearest-neighbour search, with a vibe.d 0.10.3 REST API. It is built as a
hexagonal / Clean Architecture. All code is `@safe`, and the domain and application layers depend on Phobos only.

Class and component diagrams: [uml.md](uml.md).

## Setup

```bash
dub test                    # unit tests of every layer
dub run -c executable       # REST server on http://127.0.0.1:8087
```

The `library` configuration (the default) embeds the database in another program without HTTP. Wire
`InMemoryCollectionRepository` to the interactors yourself, the way `source/app.d` does.

## Configuration

Values are resolved from four sources. A later source overrides an earlier one:

| Source | Keys / variables |
|---|---|
| 1. Built-in defaults | `AppConfig` in `infrastructure/configuration/settings.d` |
| 2. `config/default.json`, or the file named by `VECTOR_CONFIG_FILE` | `databaseName`, `host`, `port`, `logLevel` |
| 3. Environment | `PORT` (set by Cloud Foundry), then `VECTOR_DATABASE_NAME`, `VECTOR_HOST`, `VECTOR_PORT`, `VECTOR_LOG_LEVEL` |
| 4. `VCAP_SERVICES` | `credentials` of the service instance named or tagged `vector-config` |

An invalid value stops the server at startup with exit code 1. On Cloud Foundry, set `VECTOR_HOST=0.0.0.0`.

## Architecture

```
source/
  app.d                         composition root: the only place that wires adapters to the core
  uim/databases/vector/
    domain/                     business rules (Phobos only)
      entities/                 VectorCollection (aggregate root), VectorRecord, SearchHit
      types/                    Embedding, Metadata, identifier rules
      enumerations/             DistanceMetric
      services/                 distance functions (euclidean, cosine, manhattan, dot product, normalize)
      exceptions/               Validation (400), NotFound (404), Conflict (409) families
    application/                use cases (depends on domain and ports)
      usecases/                 CollectionInteractor, VectorInteractor, SearchInteractor
      services/                 DatabaseInfoService
      dtos/                     commands and results crossing the ports
    ports/                      interfaces
      usecases/                 ICollectionUseCase, IVectorUseCase, ISearchUseCase  (driving)
      services/                 IDatabaseInfoService                               (driving)
      repositories/             ICollectionRepository                              (driven)
    persistence/repositories/   InMemoryCollectionRepository (driven adapter)
    infrastructure/             configuration (file, env, VCAP_SERVICES), logging
    presentation/               driving adapters (vibe.d)
      rest/                     REST interface, models, controller
      http/                     routes, error handler, 404
```

Dependencies only point inwards. Presentation depends on the driving ports. Interactors depend on the
driven ports. Persistence implements the driven ports. Only `app.d` sees every layer.

Layers that the skill defines but this module doesn't need yet are not created. Add them when needed:
- `ports/storages`, `ports/messaging` and `ports/gateways` (for example an embedding-model gateway)
- `persistence/storages`, `persistence/mappers` and `persistence/records`
- `infrastructure/security`, `infrastructure/clients` and `infrastructure/workers`
- `presentation/odata`, `presentation/web`, `presentation/cli` and `presentation/gui`

## REST API

| Method | Path | Body / result |
|---|---|---|
| GET | `/health` | `{status, type, collectionCount}` |
| GET | `/stats` | `{name, collectionCount, vectorCount, collections}` |
| GET | `/collections` | `{collections:[{name, dimension, metric, count}], count}` |
| POST | `/collections` | `{name, dimension, metric?}`, returns 201 |
| GET / DELETE | `/collections/:name` | collection info; DELETE removes the collection and its vectors |
| GET | `/collections/:name/vectors` | `{ids, count}` |
| POST | `/collections/:name/vectors` | `{id, values, metadata?}`, returns 201 |
| POST | `/collections/:name/vectors/batch` | `{vectors:[...]}`, all-or-nothing, returns 201 |
| GET / PUT / DELETE | `/collections/:name/vectors/:id` | PUT `{values?, metadata?}`; an absent field is kept |
| POST | `/collections/:name/filter` | `{metadata:{key: value}}`, returns the vectors that contain every pair |
| POST | `/collections/:name/search` | `{vector, k?=10, filter?, includeValues?}`, returns `{results:[{id, distance, metadata, values}], count}` |
| POST | `/collections/:name/vectors/:id/similar` | `{k?=10, filter?, includeValues?}`; same result, without the vector itself |

The metrics are `EUCLIDEAN` (the default), `COSINE` (1 − cosine similarity), `MANHATTAN` and `DOT_PRODUCT`
(the negative dot product). For every metric, a smaller distance means more similar. Results are ordered
nearest first, and ties are broken by id.

Errors return `{"statusMessage": "..."}` with one of these codes:
- **400:** invalid input
- **404:** unknown collection or vector
- **409:** duplicate name or id

## Limits and semantics

- **Values:** a dimension is between 1 and 65536. Values must be finite, so NaN and infinity are rejected.
- **Vector ids:** 1 to 256 characters, without `/` or control characters.
- **Search cost:** search is exact (brute force), which is O(n · dimension) per query. There is no approximate index yet.
- **Metadata:** metadata is text key/value pairs. A filter matches when every given pair is present.
- **Storage:** data lives in memory only. `ICollectionRepository` is the extension point for durable storage.
