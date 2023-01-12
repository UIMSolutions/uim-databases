module uim.cake.databases.Statement;

import uim.cake.databases.IDriver;
import uim.cake.databases.IStatement;
import uim.cake.databases.TypeConverterTrait;
use Countable;
use IteratorAggregate;

/**
 * Represents a database statement. Statements contains queries that can be
 * executed multiple times by binding different values on each call. This class
 * also helps convert values to their valid representation for the corresponding
 * types.
 *
 * This class is but a decorator of an actual statement implementation, such as
 * PDOStatement.
 *
 * @property-read string $queryString
 */
class StatementDecorator : IStatement, Countable, IteratorAggregate
{
    use TypeConverterTrait;

    /**
     * Statement instance implementation, such as PDOStatement
     * or any other custom implementation.
     *
     * @var DDBIStatement
     */
    protected _statement;

    /**
     * Reference to the driver object associated to this statement.
     *
     * @var DDBIDriver
     */
    protected _driver;

    /**
     * Whether this statement has already been executed
     */
    protected bool _hasExecuted = false;

    /**
     * Constructor
     *
     * @param uim.cake.databases.IStatement $statement Statement implementation
     *  such as PDOStatement.
     * @param uim.cake.databases.IDriver aDriver Driver instance
     */
    this(IStatement $statement, IDriver aDriver) {
        _statement = $statement;
        _driver = $driver;
    }

    /**
     * Magic getter to return $queryString as read-only.
     *
     * @param string $property internal property to get
     */
    Nullable!string __get(string $property) {
        if ($property == "queryString") {
            /** @psalm-suppress NoInterfaceProperties */
            return _statement.queryString;
        }

        return null;
    }

    /**
     * Assign a value to a positional or named variable in prepared query. If using
     * positional variables you need to start with index one, if using named params then
     * just use the name in any order.
     *
     * It is not allowed to combine positional and named variables in the same statement.
     *
     * ### Examples:
     *
     * ```
     * $statement.bindValue(1, "a title");
     * $statement.bindValue("active", true, "boolean");
     * $statement.bindValue(5, new \DateTime(), "date");
     * ```
     *
     * @param string|int $column name or param position to be bound
     * @param mixed $value The value to bind to variable in query
     * @param string|int|null $type name of configured Type class
     */
    void bindValue($column, $value, $type = "string") {
        _statement.bindValue($column, $value, $type);
    }

    /**
     * Closes a cursor in the database, freeing up any resources and memory
     * allocated to it. In most cases you don"t need to call this method, as it is
     * automatically called after fetching all results from the result set.
     */
    void closeCursor() {
        _statement.closeCursor();
    }

    /**
     * Returns the number of columns this statement"s results will contain.
     *
     * ### Example:
     *
     * ```
     * $statement = $connection.prepare("SELECT id, title from articles");
     * $statement.execute();
     * echo $statement.columnCount(); // outputs 2
     * ```
     */
    int columnCount() {
        return _statement.columnCount();
    }

    /**
     * Returns the error code for the last error that occurred when executing this statement.
     *
     * @return string|int
     */
    function errorCode() {
        return _statement.errorCode();
    }

    /**
     * Returns the error information for the last error that occurred when executing
     * this statement.
     */
    array errorInfo() {
        return _statement.errorInfo();
    }

    /**
     * Executes the statement by sending the SQL query to the database. It can optionally
     * take an array or arguments to be bound to the query variables. Please note
     * that binding parameters from this method will not perform any custom type conversion
     * as it would normally happen when calling `bindValue`.
     *
     * @param array|null $params list of values to be bound to query
     * @return bool true on success, false otherwise
     */
    bool execute(?array $params = null) {
        _hasExecuted = true;

        return _statement.execute($params);
    }

    /**
     * Returns the next row for the result set after executing this statement.
     * Rows can be fetched to contain columns as names or positions. If no
     * rows are left in result set, this method will return false.
     *
     * ### Example:
     *
     * ```
     * $statement = $connection.prepare("SELECT id, title from articles");
     * $statement.execute();
     * print_r($statement.fetch("assoc")); // will show ["id": 1, "title": "a title"]
     * ```
     *
     * @param string|int $type "num" for positional columns, assoc for named columns
     * @return mixed Result array containing columns and values or false if no results
     * are left
     */
    function fetch($type = self::FETCH_TYPE_NUM) {
        return _statement.fetch($type);
    }

    /**
     * Returns the next row in a result set as an associative array. Calling this bool is the same as calling
     * $statement.fetch(StatementDecorator::FETCH_TYPE_ASSOC). If no results are found an empty array is returned.
     */
    array fetchAssoc() {
        $result = this.fetch(static::FETCH_TYPE_ASSOC);

        return $result ?: [];
    }

    /**
     * Returns the value of the result at position.
     *
     * @param int $position The numeric position of the column to retrieve in the result
     * @return mixed Returns the specific value of the column designated at $position
     */
    function fetchColumn(int $position) {
        $result = this.fetch(static::FETCH_TYPE_NUM);
        if ($result && isset($result[$position])) {
            return $result[$position];
        }

        return false;
    }

    /**
     * Returns an array with all rows resulting from executing this statement.
     *
     * ### Example:
     *
     * ```
     * $statement = $connection.prepare("SELECT id, title from articles");
     * $statement.execute();
     * print_r($statement.fetchAll("assoc")); // will show [0: ["id": 1, "title": "a title"]]
     * ```
     *
     * @param string|int $type num for fetching columns as positional keys or assoc for column names as keys
     * @return array|false List of all results from database for this statement. False on failure.
     */
    function fetchAll($type = self::FETCH_TYPE_NUM) {
        return _statement.fetchAll($type);
    }

    /**
     * Returns the number of rows affected by this SQL statement.
     *
     * ### Example:
     *
     * ```
     * $statement = $connection.prepare("SELECT id, title from articles");
     * $statement.execute();
     * print_r($statement.rowCount()); // will show 1
     * ```
     */
    int rowCount() {
        return _statement.rowCount();
    }

    /**
     * Statements are iterable as arrays, this method will return
     * the iterator object for traversing all items in the result.
     *
     * ### Example:
     *
     * ```
     * $statement = $connection.prepare("SELECT id, title from articles");
     * foreach ($statement as $row) {
     *   //do stuff
     * }
     * ```
     *
     * @return uim.cake.databases.IStatement
     * @psalm-suppress ImplementedReturnTypeMismatch
     */
    #[\ReturnTypeWillChange]
    function getIterator() {
        if (!_hasExecuted) {
            this.execute();
        }

        return _statement;
    }

    /**
     * Statements can be passed as argument for count() to return the number
     * for affected rows from last execution.
     */
    size_t count() {
        return this.rowCount();
    }

    /**
     * Binds a set of values to statement object with corresponding type.
     *
     * @param array $params list of values to be bound
     * @param array $types list of types to be used, keys should match those in $params
     */
    void bind(array $params, array $types) {
        if (empty($params)) {
            return;
        }

        $anonymousParams = is_int(key($params));
        $offset = 1;
        foreach ($params as $index: $value) {
            $type = $types[$index] ?? null;
            if ($anonymousParams) {
                /** @psalm-suppress InvalidOperand */
                $index += $offset;
            }
            /** @psalm-suppress InvalidScalarArgument */
            this.bindValue($index, $value, $type);
        }
    }

    /**
     * Returns the latest primary inserted using this statement.
     *
     * @param string|null $table table name or sequence to get last insert value from
     * @param string|null $column the name of the column representing the primary key
     * @return string|int
     */
    function lastInsertId(Nullable!string $table = null, Nullable!string $column = null) {
        if ($column && this.columnCount()) {
            $row = this.fetch(static::FETCH_TYPE_ASSOC);

            if ($row && isset($row[$column])) {
                return $row[$column];
            }
        }

        return _driver.lastInsertId($table, $column);
    }

    /**
     * Returns the statement object that was decorated by this class.
     *
     * @return uim.cake.databases.IStatement
     */
    function getInnerStatement() {
        return _statement;
    }
}