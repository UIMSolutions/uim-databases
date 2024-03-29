module uim.databases.drivers;

@safe:
import uim.databases;

use PDO;

/**
 * MySQL Driver
 */
class MysqlDriver : Driver {
    use SqlDialectTrait;

    protected const MAX_ALIAS_LENGTH = 256;

    // Server type MySQL
    protected const string SERVER_TYPE_MYSQL = "mysql";

    /**
     * Server type MariaDB
     *
     * @var string
     */
    protected const SERVER_TYPE_MARIADB = "mariadb";

    /**
     * Base configuration settings for MySQL driver
     *
     * @var array<string, mixed>
     */
    protected _baseConfig = [
        "persistent": true,
        "host": "localhost",
        "username": "root",
        "password": "",
        "database": "cake",
        "port": "3306",
        "flags": [],
        "encoding": "utf8mb4",
        "timezone": null,
        "init": [],
    ];

    /**
     * The schema dialect for this driver
     *
     * @var DDBSchema\MysqlSchemaDialect|null
     */
    protected _schemaDialect;

    /**
     * String used to start a database identifier quoting to make it safe
     */
    protected string _startQuote = "`";

    /**
     * String used to end a database identifier quoting to make it safe
     */
    protected string _endQuote = "`";

    /**
     * Server type.
     *
     * If the underlying server is MariaDB, its value will get set to `"mariadb"`
     * after `version()` method is called.
     */
    protected string serverType = self::SERVER_TYPE_MYSQL;

    /**
     * Mapping of feature to db server version for feature availability checks.
     *
     * @var array<string, array<string, string>>
     */
    protected featureVersions = [
        "mysql": [
            "json": "5.7.0",
            "cte": "8.0.0",
            "window": "8.0.0",
        ],
        "mariadb": [
            "json": "10.2.7",
            "cte": "10.2.1",
            "window": "10.2.0",
        ],
    ];

    /**
     * Establishes a connection to the database server
     *
     * @return bool true on success
     */
    bool connect() {
        if (_connection) {
            return true;
        }
        aConfig = _config;

        if (aConfig["timezone"] == "UTC") {
            aConfig["timezone"] = "+0:00";
        }

        if (!empty(aConfig["timezone"])) {
            aConfig["init"][] = sprintf("SET time_zone = '%s'", aConfig["timezone"]);
        }

        aConfig["flags"] += [
            PDO::ATTR_PERSISTENT: aConfig["persistent"],
            PDO::MYSQL_ATTR_USE_BUFFERED_QUERY: true,
            PDO::ATTR_ERRMODE: PDO::ERRMODE_EXCEPTION,
        ];

        if (!empty(aConfig["ssl_key"]) && !empty(aConfig["ssl_cert"])) {
            aConfig["flags"][PDO::MYSQL_ATTR_SSL_KEY] = aConfig["ssl_key"];
            aConfig["flags"][PDO::MYSQL_ATTR_SSL_CERT] = aConfig["ssl_cert"];
        }
        if (!empty(aConfig["ssl_ca"])) {
            aConfig["flags"][PDO::MYSQL_ATTR_SSL_CA] = aConfig["ssl_ca"];
        }

        if (empty(aConfig["unix_socket"])) {
            dsn = "mysql:host={aConfig["host"]};port={aConfig["port"]};dbname={aConfig["database"]}";
        } else {
            dsn = "mysql:unix_socket={aConfig["unix_socket"]};dbname={aConfig["database"]}";
        }

        if (!empty(aConfig["encoding"])) {
            dsn ~= ";charset={aConfig["encoding"]}";
        }

        _connect(dsn, aConfig);

        if (!empty(aConfig["init"])) {
            connection = this.getConnection();
            foreach ((array)aConfig["init"] as command) {
                connection.exec(command);
            }
        }

        return true;
    }

    /**
     * Returns whether D is able to use this driver for connecting to database
     *
     * @return bool true if it is valid to use this driver
     */
    bool enabled() {
        return hasAllValues("mysql", PDO::getAvailableDrivers(), true);
    }

    /**
     * Prepares a sql statement to be executed
     *
     * @param uim.databases.Query|string query The query to prepare.
     * @return uim.databases.IStatement
     */
    function prepare(query): IStatement
    {
        this.connect();
        isObject = query instanceof Query;
        /**
         * @psalm-suppress PossiblyInvalidMethodCall
         * @psalm-suppress PossiblyInvalidArgument
         */
        statement = _connection.prepare(isObject ? query.sql() : query);
        result = new MysqlStatement(statement, this);
        /** @psalm-suppress PossiblyInvalidMethodCall */
        if (isObject && query.isBufferedResultsEnabled() == false) {
            result.bufferResults(false);
        }

        return result;
    }


    function schemaDialect(): SchemaDialect
    {
        if (_schemaDialect == null) {
            _schemaDialect = new MysqlSchemaDialect(this);
        }

        return _schemaDialect;
    }


    string schema() {
        return _config["database"];
    }


    string disableForeignKeySQL() {
        return "SET foreign_key_checks = 0";
    }


    string enableForeignKeySQL() {
        return "SET foreign_key_checks = 1";
    }


    bool supports(string feature) {
        switch (feature) {
            case FEATURE_CTE:
            case FEATURE_JSON:
            case FEATURE_WINDOW:
                return version_compare(
                    this.version(),
                    this.featureVersions[this.serverType][feature],
                    ">="
                );
        }

        return super.supports(feature);
    }


    bool supportsDynamicConstraints() {
        return true;
    }

    /**
     * Returns true if the connected server is MariaDB.
     */
    bool isMariadb() {
        this.version();

        return this.serverType == SERVER_TYPE_MARIADB;
    }

    /**
     * Returns connected server version.
     */
    string version() {
        if (_version == null) {
            this.connect();
            _version = (string)_connection.getAttribute(PDO::ATTR_SERVER_VERSION);

            if (strpos(_version, "MariaDB") != false) {
                this.serverType = SERVER_TYPE_MARIADB;
                preg_match("/^(?:5\.5\.5-)?(\d+\.\d+\.\d+.*-MariaDB[^:]*)/", _version,  matches);
                _version =  matches[1];
            }
        }

        return _version;
    }
}
