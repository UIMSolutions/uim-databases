/*********************************************************************************************************
	Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        
	License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  
	Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      
**********************************************************************************************************/
module uim.databases.Statement;

use uim.databases.IDBADriver;
use uim.databases.statementsInterface;
use uim.databases.TypeConverterTrait;
use Iterator;

/**
 * A statement decorator that : buffered results.
 *
 * This statement decorator will save fetched results in memory, allowing
 * the iterator to be rewound and reused.
 */
class BufferedStatement : Iterator, StatementInterface
{
    use TypeConverterTrait;

    /**
     * If true, all rows were fetched
     *
     * @var bool
     */
    protected _allFetched = false;

    /**
     * The decorated statement
     *
     * @var uim.databases.StatementInterface
     */
    protected statement;

    /**
     * The driver for the statement
     *
     * @var uim.databases.IDBADriver
     */
    protected _driver;

    /**
     * The in-memory cache containing results from previous iterators
     *
     * @var array<int, array>
     */
    protected buffer = [];

    /**
     * Whether this statement has already been executed
     *
     * @var bool
     */
    protected _hasExecuted = false;

    /**
     * The current iterator index.
     *
     * @var int
     */
    protected index = 0;

    /**
     * Constructor
     *
     * @param uim.databases.StatementInterface statement Statement implementation such as PDOStatement
     * @param uim.databases.IDBADriver aDriver Driver instance
     */
    public this(StatementInterface statement, IDBADriver aDriver)
    {
        this.statement = statement;
        this._driver = driver;
    }

    /**
     * Magic getter to return queryString as read-only.
     *
     * @param string property internal property to get
     * @return string|null
     */
    function __get(string property)
    {
        if (property == "queryString") {
            /** @psalm-suppress NoInterfaceProperties */
            return this.statement.queryString;
        }

        return null;
    }


    function bindValue(column, DValue aValue, type = "string"): void
    {
        this.statement.bindValue(column, DValue aValue, type);
    }


    function closeCursor(): void
    {
        this.statement.closeCursor();
    }


    function columnCount(): int
    {
        return this.statement.columnCount();
    }


    function errorCode()
    {
        return this.statement.errorCode();
    }


    function errorInfo(): array
    {
        return this.statement.errorInfo();
    }


    function execute(?array params = null): bool
    {
        this._reset();
        this._hasExecuted = true;

        return this.statement.execute(params);
    }


    function fetchColumn(int position)
    {
        result = this.fetch(FETCH_TYPE_NUM);
        if (result != false && isset(result[position])) {
            return result[position];
        }

        return false;
    }

    /**
     * Statements can be passed as argument for count() to return the number
     * for affected rows from last execution.
     *
     * @return int
     */
    function count(): int
    {
        return this.rowCount();
    }


    function bind(array params, array types): void
    {
        this.statement.bind(params, someTypes);
    }


    function lastInsertId(?string table = null, ?string column = null)
    {
        return this.statement.lastInsertId(table, column);
    }

    /**
     * {@inheritDoc}
     *
     * @param string|int type The type to fetch.
     * @return array|false
     */
    function fetch(type = self::FETCH_TYPE_NUM)
    {
        if (this._allFetched) {
            aRow = false;
            if (isset(this.buffer[this.index])) {
                aRow = this.buffer[this.index];
            }
            this.index += 1;

            if (aRow && type == FETCH_TYPE_NUM) {
                return array_values(aRow);
            }

            return aRow;
        }

        record = this.statement.fetch(type);
        if (record == false) {
            this._allFetched = true;
            this.statement.closeCursor();

            return false;
        }
        this.buffer[] = record;

        return record;
    }

    /**
     * @return array
     */
    function fetchAssoc(): array
    {
        result = this.fetch(FETCH_TYPE_ASSOC);

        return result ?: [];
    }


    function fetchAll(type = self::FETCH_TYPE_NUM)
    {
        if (this._allFetched) {
            return this.buffer;
        }
        results = this.statement.fetchAll(type);
        if (results != false) {
            this.buffer = array_merge(this.buffer, results);
        }
        this._allFetched = true;
        this.statement.closeCursor();

        return this.buffer;
    }


    function rowCount(): int
    {
        if (!this._allFetched) {
            this.fetchAll(FETCH_TYPE_ASSOC);
        }

        return count(this.buffer);
    }

    /**
     * Reset all properties
     *
     * @return void
     */
    protected function _reset(): void
    {
        this.buffer = [];
        this._allFetched = false;
        this.index = 0;
    }

    /**
     * Returns the current key in the iterator
     *
     * @return mixed
     */
    #[\ReturnTypeWillChange]
    function key()
    {
        return this.index;
    }

    /**
     * Returns the current record in the iterator
     *
     * @return mixed
     */
    #[\ReturnTypeWillChange]
    function current()
    {
        return this.buffer[this.index];
    }

    /**
     * Rewinds the collection
     *
     * @return void
     */
    function rewind(): void
    {
        this.index = 0;
    }

    /**
     * Returns whether the iterator has more elements
     *
     * @return bool
     */
    function valid(): bool
    {
        old = this.index;
        aRow = this.fetch(self::FETCH_TYPE_ASSOC);

        // Restore the index as fetch() increments during
        // the cache scenario.
        this.index = old;

        return aRow != false;
    }

    /**
     * Advances the iterator pointer to the next element
     *
     * @return void
     */
    function next(): void
    {
        this.index += 1;
    }

    /**
     * Get the wrapped statement
     *
     * @return uim.databases.StatementInterface
     */
    function getInnerStatement(): StatementInterface
    {
        return this.statement;
    }
}
