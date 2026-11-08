# relational – UML

## Components and dependency direction

```mermaid
flowchart LR
  subgraph presentation["presentation (vibe.d)"]
    routes[http/routes]
    rest[rest/RelationalRestController]
  end
  subgraph ports
    pu[usecases: ITableCatalogUseCase<br/>IRowUseCase, IJoinUseCase]
    ps[services: IDatabaseInfoService]
    pr[repositories: ITableRepository]
  end
  subgraph application
    uc[usecases: TableCatalogInteractor<br/>RowInteractor, JoinInteractor]
    as[services: DatabaseInfoService]
    dto[dtos]
  end
  subgraph domain["domain (Phobos only)"]
    ent[entities: Table]
    typ[types: Value, TableSchema, ...]
    dsv[services: predicates, comparison, join, literals]
    exc[exceptions]
  end
  subgraph persistence
    mem[repositories/InMemoryTableRepository]
  end
  subgraph infrastructure
    cfg[configuration: AppConfig, loader]
    log[logging]
  end
  app([app.d composition root])

  routes --> rest --> pu & ps
  uc -. implements .-> pu
  as -. implements .-> ps
  uc & as --> pr
  mem -. implements .-> pr
  uc & as --> domain
  pu & ps --> dto
  app --> presentation & application & persistence & infrastructure
```

## Domain model

```mermaid
classDiagram
  class Table {
    <<aggregate root>>
    +name() string
    +schema() TableSchema
    +rowCount() size_t
    +insert(RowData) ulong
    +insertAll(RowData[]) ulong[]
    +select(Query) QueryResult
    +rowsWhere(Condition[]) RowData[]
    +update(RowData, Condition[]) size_t
    +remove(Condition[]) size_t
    +count(Condition[]) size_t
    +findByPrimaryKey(Value) Nullable~RowData~
    -StoredRow[] rows
    -uniqueIndex : column → Value → rowId
  }
  class TableSchema {
    <<value>>
    +tableName() string
    +columns() ColumnDefinition[]
    +foreignKeys() ForeignKey[]
    +primaryKey() string
    +conformRow(RowData) RowData
    +conformChanges(RowData) RowData
  }
  class ColumnDefinition {
    <<value>>
    +name, type, nullable, primaryKey, unique
    +defaultValue() Nullable~Value~
    +conform(Value) Value
  }
  class ForeignKey {
    <<value>>
    +column, referencedTable, referencedColumn
  }
  class Value {
    <<value>>
    +kind() ValueKind
    +opEquals / toHash
  }
  class Condition {
    <<value>>
    +column, op, operand, candidates
  }
  class Query {
    <<value>>
    +columns, where, orderBy, limit, offset
  }
  class QueryResult {
    +columns string[]
    +rows RowData[]
  }
  class ColumnType {
    <<enumeration>>
    INTEGER FLOAT STRING BOOLEAN DATE JSON
  }
  class ComparisonOperator {
    <<enumeration>>
    equal notEqual greater less ... like in_ isNull isNotNull
  }

  Table *-- TableSchema
  TableSchema *-- "1..*" ColumnDefinition
  TableSchema *-- "*" ForeignKey
  ColumnDefinition --> ColumnType
  Table ..> Query
  Table ..> QueryResult
  Query *-- "*" Condition
  Condition --> ComparisonOperator
  Condition *-- Value
  Table o-- "*" Value : rows
```

## Ports and adapters

```mermaid
classDiagram
  class ITableCatalogUseCase {
    <<interface>>
    +createTable(CreateTableCommand) TableSchemaView
    +dropTable(string)
    +listTables() string[]
    +describeTable(string) TableSchemaView
  }
  class IRowUseCase {
    <<interface>>
    +insert(string, RowData[]) ulong[]
    +select(string, SelectRequest) QueryResult
    +update(string, UpdateCommand) size_t
    +remove(string, DeleteCommand) size_t
    +count(string) size_t
    +findByPrimaryKey(string, string) RowData
  }
  class IJoinUseCase {
    <<interface>>
    +innerJoin(JoinRequest) QueryResult
  }
  class IDatabaseInfoService {
    <<interface>>
    +health() HealthStatus
    +statistics() DatabaseStatistics
  }
  class ITableRepository {
    <<interface>>
    +save(Table)
    +find(string) Table
    +remove(string) bool
    +exists(string) bool
    +names() string[]
    +all() Table[]
  }

  TableCatalogInteractor ..|> ITableCatalogUseCase
  RowInteractor ..|> IRowUseCase
  JoinInteractor ..|> IJoinUseCase
  DatabaseInfoService ..|> IDatabaseInfoService
  InMemoryTableRepository ..|> ITableRepository
  TableCatalogInteractor --> ITableRepository
  RowInteractor --> ITableRepository
  JoinInteractor --> ITableRepository
  DatabaseInfoService --> ITableRepository
  RelationalRestController --> ITableCatalogUseCase
  RelationalRestController --> IRowUseCase
  RelationalRestController --> IJoinUseCase
  RelationalRestController --> IDatabaseInfoService
```

## Request flow: `POST /tables/users/insert`

```mermaid
sequenceDiagram
  participant C as Client
  participant R as RelationalRestController
  participant I as RowInteractor
  participant Repo as ITableRepository
  participant T as Table

  C->>R: {"rows":[...]}
  R->>R: Json → RowData (conversions)
  R->>I: insert("users", rows)
  I->>Repo: find("users")
  Repo-->>I: Table
  I->>T: insertAll(rows)
  T->>T: conform to schema, check unique/PK
  T-->>I: row ids (or exception, nothing changed)
  I->>Repo: save(table)
  I-->>R: ids
  R-->>C: 201 {inserted, rowIds}
  Note over R: Validation→400, NotFound→404, Conflict→409
```
