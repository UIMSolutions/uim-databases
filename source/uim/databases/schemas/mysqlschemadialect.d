module uim.databases.schemas;

use Cake\Database\IDTBDriver;
use Cake\Database\Exception\DatabaseException;

/**
 * Schema generation/reflection features for MySQL
 *
 * @internal
 */
class MysqlSchemaDialect : SchemaDialect
{
    /**
     * The driver instance being used.
     *
     * @var \Cake\Database\Driver\Mysql
     */
    protected _driver;

    /**
     * Generate the SQL to list the tables and views.
     *
     * @param array<string, mixed> $config The connection configuration to use for
     *    getting tables from.
     * @return array<mixed> An array of (sql, params) to execute.
     */
    function listTablesSql(array aConfig): array
    {
        return ["SHOW FULL TABLES FROM " . this._driver.quoteIdentifier($config["database"]), []];
    }

    /**
     * Generate the SQL to list the tables, excluding all views.
     *
     * @param array<string, mixed> $config The connection configuration to use for
     *    getting tables from.
     * @return array<mixed> An array of (sql, params) to execute.
     */
    function listTablesWithoutViewsSql(array aConfig): array
    {
        return [
            "SHOW FULL TABLES FROM " . this._driver.quoteIdentifier($config["database"])
            . " WHERE TABLE_TYPE = "BASE TABLE""
        , []];
    }


    function describeColumnSql(string $tableName, array aConfig): array
    {
        return ["SHOW FULL COLUMNS FROM " . this._driver.quoteIdentifier($tableName), []];
    }


    function describeIndexSql(string $tableName, array aConfig): array
    {
        return ["SHOW INDEXES FROM " . this._driver.quoteIdentifier($tableName), []];
    }


    function describeOptionsSql(string $tableName, array aConfig): array
    {
        return ["SHOW TABLE STATUS WHERE Name = ?", [$tableName]];
    }


    void convertOptionsDescription(TableSchema aSchema, array aRow)
    {
        $schema.setOptions([
            "engine" : aRow["Engine"],
            "collation" : aRow["Collation"],
        ]);
    }

    /**
     * Convert a MySQL column type into an abstract type.
     *
     * The returned type will be a type that Cake\Database\TypeFactory can handle.
     *
     * @param string $column The column type + length
     * @return array<string, mixed> Array of column information.
     * @throws \Cake\Database\Exception\DatabaseException When column type cannot be parsed.
     */
    protected function _convertColumn(string $column): array
    {
        preg_match("/([a-z]+)(?:\(([0-9,]+)\))?\s*([a-z]+)?/i", $column, $matches);
        if (empty($matches)) {
            throw new DatabaseException(sprintf("Unable to parse column type from "%s"", $column));
        }

        $col = strtolower($matches[1]);
        $length = $precision = $scale = null;
        if (isset($matches[2]) && strlen($matches[2])) {
            $length = $matches[2];
            if (strpos($matches[2], ",") != false) {
                [$length, $precision] = explode(",", $length);
            }
            $length = (int)$length;
            $precision = (int)$precision;
        }

        $type = this._applyTypeSpecificColumnConversion(
            $col,
            compact("length", "precision", "scale")
        );
        if ($type != null) {
            return $type;
        }

        if (in_array($col, ["date", "time"])) {
            return ["type" : $col, "length" : null];
        }
        if (in_array($col, ["datetime", "timestamp"])) {
            $typeName = $col;
            if ($length > 0) {
                $typeName = $col . "fractional";
            }

            return ["type" : $typeName, "length" : null, "precision" : $length];
        }

        if (($col == "tinyint" && $length == 1) || $col == "boolean") {
            return ["type" : TableSchema::TYPE_BOOLEAN, "length" : null];
        }

        $unsigned = (isset($matches[3]) && strtolower($matches[3]) == "unsigned");
        if (strpos($col, "bigint") != false || $col == "bigint") {
            return ["type" : TableSchema::TYPE_BIGINTEGER, "length" : null, "unsigned" : $unsigned];
        }
        if ($col == "tinyint") {
            return ["type" : TableSchema::TYPE_TINYINTEGER, "length" : null, "unsigned" : $unsigned];
        }
        if ($col == "smallint") {
            return ["type" : TableSchema::TYPE_SMALLINTEGER, "length" : null, "unsigned" : $unsigned];
        }
        if (in_array($col, ["int", "integer", "mediumint"])) {
            return ["type" : TableSchema::TYPE_INTEGER, "length" : null, "unsigned" : $unsigned];
        }
        if ($col == "char" && $length == 36) {
            return ["type" : TableSchema::TYPE_UUID, "length" : null];
        }
        if ($col == "char") {
            return ["type" : TableSchema::TYPE_CHAR, "length" : $length];
        }
        if (strpos($col, "char") != false) {
            return ["type" : TableSchema::TYPE_STRING, "length" : $length];
        }
        if (strpos($col, "text") != false) {
            $lengthName = substr($col, 0, -4);
            $length = TableSchema::$columnLengths[$lengthName] ?? null;

            return ["type" : TableSchema::TYPE_TEXT, "length" : $length];
        }
        if ($col == "binary" && $length == 16) {
            return ["type" : TableSchema::TYPE_BINARY_UUID, "length" : null];
        }
        if (strpos($col, "blob") != false || in_array($col, ["binary", "varbinary"])) {
            $lengthName = substr($col, 0, -4);
            $length = TableSchema::$columnLengths[$lengthName] ?? $length;

            return ["type" : TableSchema::TYPE_BINARY, "length" : $length];
        }
        if (strpos($col, "float") != false || strpos($col, "double") != false) {
            return [
                "type" : TableSchema::TYPE_FLOAT,
                "length" : $length,
                "precision" : $precision,
                "unsigned" : $unsigned,
            ];
        }
        if (strpos($col, "decimal") != false) {
            return [
                "type" : TableSchema::TYPE_DECIMAL,
                "length" : $length,
                "precision" : $precision,
                "unsigned" : $unsigned,
            ];
        }

        if (strpos($col, "json") != false) {
            return ["type" : TableSchema::TYPE_JSON, "length" : null];
        }

        return ["type" : TableSchema::TYPE_STRING, "length" : null];
    }


    void convertColumnDescription(TableSchema aSchema, array aRow)
    {
        $field = this._convertColumn(aRow["Type"]);
        $field += [
            "null" : aRow["Null"] == "YES",
            "default" : aRow["Default"],
            "collate" : aRow["Collation"],
            "comment" : aRow["Comment"],
        ];
        if (isset(aRow["Extra"]) && aRow["Extra"] == "auto_increment") {
            $field["autoIncrement"] = true;
        }
        $schema.addColumn(aRow["Field"], $field);
    }


    void convertIndexDescription(TableSchema aSchema, array aRow)
    {
        $type = null;
        $columns = $length = [];

        $name = aRow["Key_name"];
        if ($name == "PRIMARY") {
            $name = $type = TableSchema::CONSTRAINT_PRIMARY;
        }

        if (!empty(aRow["Column_name"])) {
            $columns[] = aRow["Column_name"];
        }

        if (aRow["Index_type"] == "FULLTEXT") {
            $type = TableSchema::INDEX_FULLTEXT;
        } elseif ((int)aRow["Non_unique"] == 0 && $type != "primary") {
            $type = TableSchema::CONSTRAINT_UNIQUE;
        } elseif ($type != "primary") {
            $type = TableSchema::INDEX_INDEX;
        }

        if (!empty(aRow["Sub_part"])) {
            $length[aRow["Column_name"]] = aRow["Sub_part"];
        }
        $isIndex = (
            $type == TableSchema::INDEX_INDEX ||
            $type == TableSchema::INDEX_FULLTEXT
        );
        if ($isIndex) {
            $existing = $schema.getIndex($name);
        } else {
            $existing = $schema.getConstraint($name);
        }

        // MySQL multi column indexes come back as multiple rows.
        if (!empty($existing)) {
            $columns = array_merge($existing["columns"], $columns);
            $length = array_merge($existing["length"], $length);
        }
        if ($isIndex) {
            $schema.addIndex($name, [
                "type" : $type,
                "columns" : $columns,
                "length" : $length,
            ]);
        } else {
            $schema.addConstraint($name, [
                "type" : $type,
                "columns" : $columns,
                "length" : $length,
            ]);
        }
    }


    function describeForeignKeySql(string $tableName, array aConfig): array
    {
        mySql = "SELECT * FROM information_schema.key_column_usage AS kcu
            INNER JOIN information_schema.referential_constraints AS rc
            ON (
                kcu.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
                AND kcu.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA
            )
            WHERE kcu.TABLE_SCHEMA = ? AND kcu.TABLE_NAME = ? AND rc.TABLE_NAME = ?
            ORDER BY kcu.ORDINAL_POSITION ASC";

        return [mySql, [$config["database"], $tableName, $tableName]];
    }


    void convertForeignKeyDescription(TableSchema aSchema, array aRow)
    {
        $data = [
            "type" : TableSchema::CONSTRAINT_FOREIGN,
            "columns" : [aRow["COLUMN_NAME"]],
            "references" : [aRow["REFERENCED_TABLE_NAME"], aRow["REFERENCED_COLUMN_NAME"]],
            "update" : this._convertOnClause(aRow["UPDATE_RULE"]),
            "delete" : this._convertOnClause(aRow["DELETE_RULE"]),
        ];
        $name = aRow["CONSTRAINT_NAME"];
        $schema.addConstraint($name, $data);
    }


    function truncateTableSql(TableSchema aSchema): array
    {
        return [sprintf("TRUNCATE TABLE `%s`", $schema.name())];
    }


    function createTableSql(TableSchema aSchema, array $columns, array $constraints, array $indexes): array
    {
        $content = implode(",\n", array_merge($columns, $constraints, $indexes));
        $temporary = $schema.isTemporary() ? " TEMPORARY " : " ";
        $content = sprintf("CREATE%sTABLE `%s` (\n%s\n)", $temporary, $schema.name(), $content);
        $options = $schema.getOptions();
        if (isset($options["engine"])) {
            $content ~= sprintf(" ENGINE=%s", $options["engine"]);
        }
        if (isset($options["charset"])) {
            $content ~= sprintf(" DEFAULT CHARSET=%s", $options["charset"]);
        }
        if (isset($options["collate"])) {
            $content ~= sprintf(" COLLATE=%s", $options["collate"]);
        }

        return [$content];
    }


    function columnSql(TableSchema aSchema, string $name): string
    {
        /** @var array $data */
        $data = $schema.getColumn($name);

        mySql = this._getTypeSpecificColumnSql($data["type"], $schema, $name);
        if (mySql != null) {
            return mySql;
        }

        $out = this._driver.quoteIdentifier($name);
        $nativeJson = this._driver.supports(IDTBDriver::FEATURE_JSON);

        $typeMap = [
            TableSchema::TYPE_TINYINTEGER : " TINYINT",
            TableSchema::TYPE_SMALLINTEGER : " SMALLINT",
            TableSchema::TYPE_INTEGER : " INTEGER",
            TableSchema::TYPE_BIGINTEGER : " BIGINT",
            TableSchema::TYPE_BINARY_UUID : " BINARY(16)",
            TableSchema::TYPE_BOOLEAN : " BOOLEAN",
            TableSchema::TYPE_FLOAT : " FLOAT",
            TableSchema::TYPE_DECIMAL : " DECIMAL",
            TableSchema::TYPE_DATE : " DATE",
            TableSchema::TYPE_TIME : " TIME",
            TableSchema::TYPE_DATETIME : " DATETIME",
            TableSchema::TYPE_DATETIME_FRACTIONAL : " DATETIME",
            TableSchema::TYPE_TIMESTAMP : " TIMESTAMP",
            TableSchema::TYPE_TIMESTAMP_FRACTIONAL : " TIMESTAMP",
            TableSchema::TYPE_TIMESTAMP_TIMEZONE : " TIMESTAMP",
            TableSchema::TYPE_CHAR : " CHAR",
            TableSchema::TYPE_UUID : " CHAR(36)",
            TableSchema::TYPE_JSON : $nativeJson ? " JSON" : " LONGTEXT",
        ];
        $specialMap = [
            "string" : true,
            "text" : true,
            "char" : true,
            "binary" : true,
        ];
        if (isset($typeMap[$data["type"]])) {
            $out ~= $typeMap[$data["type"]];
        }
        if (isset($specialMap[$data["type"]])) {
            switch ($data["type"]) {
                case TableSchema::TYPE_STRING:
                    $out ~= " VARCHAR";
                    if (!isset($data["length"])) {
                        $data["length"] = 255;
                    }
                    break;
                case TableSchema::TYPE_TEXT:
                    $isKnownLength = in_array($data["length"], TableSchema::$columnLengths);
                    if (empty($data["length"]) || !$isKnownLength) {
                        $out ~= " TEXT";
                        break;
                    }

                    /** @var string $length */
                    $length = array_search($data["length"], TableSchema::$columnLengths);
                    $out ~= " " . strtoupper($length) . "TEXT";

                    break;
                case TableSchema::TYPE_BINARY:
                    $isKnownLength = in_array($data["length"], TableSchema::$columnLengths);
                    if ($isKnownLength) {
                        /** @var string $length */
                        $length = array_search($data["length"], TableSchema::$columnLengths);
                        $out ~= " " . strtoupper($length) . "BLOB";
                        break;
                    }

                    if (empty($data["length"])) {
                        $out ~= " BLOB";
                        break;
                    }

                    if ($data["length"] > 2) {
                        $out ~= " VARBINARY(" . $data["length"] . ")";
                    } else {
                        $out ~= " BINARY(" . $data["length"] . ")";
                    }
                    break;
            }
        }
        $hasLength = [
            TableSchema::TYPE_INTEGER,
            TableSchema::TYPE_CHAR,
            TableSchema::TYPE_SMALLINTEGER,
            TableSchema::TYPE_TINYINTEGER,
            TableSchema::TYPE_STRING,
        ];
        if (in_array($data["type"], $hasLength, true) && isset($data["length"])) {
            $out ~= "(" . $data["length"] . ")";
        }

        $lengthAndPrecisionTypes = [TableSchema::TYPE_FLOAT, TableSchema::TYPE_DECIMAL];
        if (in_array($data["type"], $lengthAndPrecisionTypes, true) && isset($data["length"])) {
            if (isset($data["precision"])) {
                $out ~= "(" . (int)$data["length"] . "," . (int)$data["precision"] . ")";
            } else {
                $out ~= "(" . (int)$data["length"] . ")";
            }
        }

        $precisionTypes = [TableSchema::TYPE_DATETIME_FRACTIONAL, TableSchema::TYPE_TIMESTAMP_FRACTIONAL];
        if (in_array($data["type"], $precisionTypes, true) && isset($data["precision"])) {
            $out ~= "(" . (int)$data["precision"] . ")";
        }

        $hasUnsigned = [
            TableSchema::TYPE_TINYINTEGER,
            TableSchema::TYPE_SMALLINTEGER,
            TableSchema::TYPE_INTEGER,
            TableSchema::TYPE_BIGINTEGER,
            TableSchema::TYPE_FLOAT,
            TableSchema::TYPE_DECIMAL,
        ];
        if (
            in_array($data["type"], $hasUnsigned, true) &&
            isset($data["unsigned"]) &&
            $data["unsigned"] == true
        ) {
            $out ~= " UNSIGNED";
        }

        $hasCollate = [
            TableSchema::TYPE_TEXT,
            TableSchema::TYPE_CHAR,
            TableSchema::TYPE_STRING,
        ];
        if (in_array($data["type"], $hasCollate, true) && isset($data["collate"]) && $data["collate"] != "") {
            $out ~= " COLLATE " . $data["collate"];
        }

        if (isset($data["null"]) && $data["null"] == false) {
            $out ~= " NOT NULL";
        }
        $addAutoIncrement = (
            $schema.getPrimaryKey() == [$name] &&
            !$schema.hasAutoincrement() &&
            !isset($data["autoIncrement"])
        );
        if (
            in_array($data["type"], [TableSchema::TYPE_INTEGER, TableSchema::TYPE_BIGINTEGER]) &&
            (
                $data["autoIncrement"] == true ||
                $addAutoIncrement
            )
        ) {
            $out ~= " AUTO_INCREMENT";
        }

        $timestampTypes = [
            TableSchema::TYPE_TIMESTAMP,
            TableSchema::TYPE_TIMESTAMP_FRACTIONAL,
            TableSchema::TYPE_TIMESTAMP_TIMEZONE,
        ];
        if (isset($data["null"]) && $data["null"] == true && in_array($data["type"], $timestampTypes, true)) {
            $out ~= " NULL";
            unset($data["default"]);
        }

        $dateTimeTypes = [
            TableSchema::TYPE_DATETIME,
            TableSchema::TYPE_DATETIME_FRACTIONAL,
            TableSchema::TYPE_TIMESTAMP,
            TableSchema::TYPE_TIMESTAMP_FRACTIONAL,
            TableSchema::TYPE_TIMESTAMP_TIMEZONE,
        ];
        if (
            isset($data["default"]) &&
            in_array($data["type"], $dateTimeTypes) &&
            strpos(strtolower($data["default"]), "current_timestamp") != false
        ) {
            $out ~= " DEFAULT CURRENT_TIMESTAMP";
            if (isset($data["precision"])) {
                $out ~= "(" . $data["precision"] . ")";
            }
            unset($data["default"]);
        }
        if (isset($data["default"])) {
            $out ~= " DEFAULT " . this._driver.schemaValue($data["default"]);
            unset($data["default"]);
        }
        if (isset($data["comment"]) && $data["comment"] != "") {
            $out ~= " COMMENT " . this._driver.schemaValue($data["comment"]);
        }

        return $out;
    }


    function constraintSql(TableSchema aSchema, string $name): string
    {
        /** @var array $data */
        $data = $schema.getConstraint($name);
        if ($data["type"] == TableSchema::CONSTRAINT_PRIMARY) {
            $columns = array_map(
                [this._driver, "quoteIdentifier"],
                $data["columns"]
            );

            return sprintf("PRIMARY KEY (%s)", implode(", ", $columns));
        }

        $out = "";
        if ($data["type"] == TableSchema::CONSTRAINT_UNIQUE) {
            $out = "UNIQUE KEY ";
        }
        if ($data["type"] == TableSchema::CONSTRAINT_FOREIGN) {
            $out = "CONSTRAINT ";
        }
        $out ~= this._driver.quoteIdentifier($name);

        return this._keySql($out, $data);
    }


    function addConstraintSql(TableSchema aSchema): array
    {
        mySqlPattern = "ALTER TABLE %s ADD %s;";
        mySql = [];

        foreach ($schema.constraints() as $name) {
            /** @var array $constraint */
            $constraint = $schema.getConstraint($name);
            if ($constraint["type"] == TableSchema::CONSTRAINT_FOREIGN) {
                $tableName = this._driver.quoteIdentifier($schema.name());
                mySql[] = sprintf(mySqlPattern, $tableName, this.constraintSql($schema, $name));
            }
        }

        return mySql;
    }


    function dropConstraintSql(TableSchema aSchema): array
    {
        mySqlPattern = "ALTER TABLE %s DROP FOREIGN KEY %s;";
        mySql = [];

        foreach ($schema.constraints() as $name) {
            /** @var array $constraint */
            $constraint = $schema.getConstraint($name);
            if ($constraint["type"] == TableSchema::CONSTRAINT_FOREIGN) {
                $tableName = this._driver.quoteIdentifier($schema.name());
                $constraintName = this._driver.quoteIdentifier($name);
                mySql[] = sprintf(mySqlPattern, $tableName, $constraintName);
            }
        }

        return mySql;
    }


    function indexSql(TableSchema aSchema, string $name): string
    {
        /** @var array $data */
        $data = $schema.getIndex($name);
        $out = "";
        if ($data["type"] == TableSchema::INDEX_INDEX) {
            $out = "KEY ";
        }
        if ($data["type"] == TableSchema::INDEX_FULLTEXT) {
            $out = "FULLTEXT KEY ";
        }
        $out ~= this._driver.quoteIdentifier($name);

        return this._keySql($out, $data);
    }

    /**
     * Helper method for generating key SQL snippets.
     *
     * @param string $prefix The key prefix
     * @param array $data Key data.
     * @return string
     */
    protected function _keySql(string $prefix, array $data): string
    {
        $columns = array_map(
            [this._driver, "quoteIdentifier"],
            $data["columns"]
        );
        foreach ($data["columns"] as $i : $column) {
            if (isset($data["length"][$column])) {
                $columns[$i] ~= sprintf("(%d)", $data["length"][$column]);
            }
        }
        if ($data["type"] == TableSchema::CONSTRAINT_FOREIGN) {
            return $prefix . sprintf(
                " FOREIGN KEY (%s) REFERENCES %s (%s) ON UPDATE %s ON DELETE %s",
                implode(", ", $columns),
                this._driver.quoteIdentifier($data["references"][0]),
                this._convertConstraintColumns($data["references"][1]),
                this._foreignOnClause($data["update"]),
                this._foreignOnClause($data["delete"])
            );
        }

        return $prefix . " (" . implode(", ", $columns) . ")";
    }
}

// phpcs:disable
// Add backwards compatible alias.
class_alias("Cake\Database\Schema\MysqlSchemaDialect", "Cake\Database\Schema\MysqlSchema");
// phpcs:enable