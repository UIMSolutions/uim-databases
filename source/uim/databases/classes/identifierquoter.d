module uim.databases;

import uim.databases;

@safe:

/*
/**
 * Contains all the logic related to quoting identifiers in a Query object
 *
 * @internal
 */
class IdentifierQuoter {
    /**
     * Constructor
     * Params:
     * string astartQuote String used to start a database identifier quoting to make it safe.
     * @param string aendQuote String used to end a database identifier quoting to make it safe.
     */
    this(
        protected string astartQuote,
        protected string aendQuote
    ) {
    }
    
    /**
     * Quotes a database identifier (a column name, table name, etc..) to
     * be used safely in queries without the risk of using reserved words
     * Params:
     * string myIdentifier The identifier to quote.
     */
    string quoteIdentifier(string anIdentifier) {
        auto myIdentifier = anIdentifier.strip;

        if (myIdentifier == "*" || myIdentifier == "") {
            return myIdentifier;
        }
        // string
        if (preg_match("/^[\w-]+$/u", myIdentifier)) {
            return this.startQuote ~ myIdentifier ~ this.endQuote;
        }
        // string.string
        if (preg_match("/^[\w-]+\.[^ \*]*$/u", myIdentifier)) {
             someItems = split(".", myIdentifier);

            return this.startQuote ~ join(this.endQuote ~ "." ~ this.startQuote,  someItems) ~ this.endQuote;
        }
        // string.*
        if (preg_match("/^[\w-]+\.\*$/u", myIdentifier)) {
            return this.startQuote ~ myIdentifier.replace(".*", this.endQuote ~ ".*");
        }
        // Functions
        if (preg_match("/^([\w-]+)\((.*)\)$/", myIdentifier,  matches)) {
            return  matches[1] ~ "(" ~ this.quoteIdentifier( matches[2]) ~ ")";
        }
        // Alias.field AS thing
        if (preg_match("/^([\w-]+(\.[\w\s-]+|\(.*\))*)\s+AS\s*([\w-]+)$/ui", myIdentifier,  matches)) {
            return this.quoteIdentifier( matches[1]) ~ " AS " ~ this.quoteIdentifier( matches[3]);
        }
        // string.string with spaces
        if (preg_match("/^([\w-]+\.[\w][\w\s-]*[\w])(.*)/u", myIdentifier,  matches)) {
            
            string[] someItems =  matches[1].split(".");
            field = join(this.endQuote ~ "." ~ this.startQuote,  someItems);

            return this.startQuote ~ field ~ this.endQuote ~  matches[2];
        }
        if (preg_match("/^[\w\s-]*[\w-]+/u", myIdentifier)) {
            return this.startQuote ~ myIdentifier ~ this.endQuote;
        }
        return myIdentifier;
    }
    
    /**
     * Iterates over each of the clauses in a query looking for identifiers and
     * quotes them
     * Params:
     * \UIM\Database\Query aQuery The query to have its identifiers quoted
     */
    Query quote(Query aQuery) {
        aBinder = aQuery.getValueBinder();
        aQuery.setValueBinder(null);

        match (true) {
            cast(InsertQuery)aQuery: _quoteInsert(aQuery),
            cast(SelectQuery)aQuery: _quoteSelect(aQuery),
            cast(UpdateQuery)aQuery: _quoteUpdate(aQuery),
            cast(DeleteQuery)aQuery: _quoteDelete(aQuery),
            default =>
                throw new DatabaseException(
                    "Instance of SelectQuery, UpdateQuery, InsertQuery, DeleteQuery expected. Found `%s` instead."
                    .format(get_debug_type(aQuery)
                ))
        };

        aQuery.traverseExpressions(this.quoteExpression(...));
        aQuery.setValueBinder(aBinder);

        return aQuery;
    }
    
    /**
     * Quotes identifiers inside expression objects
     * Params:
     * \UIM\Database\IExpression expressionToQuote The expression object to walk and quote.
     */
    void quoteExpression(IExpression expressionToQuote) {
        match (true) {
            cast(IField)expressionToQuote: _quoteComparison(expressionToQuote),
            cast(OrderByExpression)expressionToQuote: _quoteOrderBy(expressionToQuote),
            cast(IdentifierExpression)expressionToQuote: _quoteIdentifierExpression(expressionToQuote),
            default: null // Nothing to do if there is no match
        };
    }
    
    /**
     * Quotes all identifiers in each of the clauses/parts of a query
     * Params:
     * \UIM\Database\Query aQuery The query to quote.
     * @param array someParts Query clauses.
     */
    protected void _quoteParts(Query aQuery, array someParts) {
        foreach (part; someParts) {
            contents = aQuery.clause(part);

            if (!isArray(contents)) {
                continue;
            }
            result = _basicQuoter(contents);
            if (!empty(result)) {
                aQuery.{part}(result, true);
            }
        }
    }
    
    /**
     * A generic identifier quoting auto used for various parts of the query
     *
     * @param IData[string] part the part of the query to quote
     */
    protected IData[string] _basicQuoter(array part) {
        result = [];
        foreach (part as alias: value) {
            value = !isString(value) ? value : this.quoteIdentifier(value);
            alias = isNumeric(alias) ? alias : this.quoteIdentifier(alias);
            result[alias] = aValue;
        }
        return result;
    }
    
    /**
     * Quotes both the table and alias for an array of joins as stored in a Query object
     * Params:
     * array  joins The joins to quote.
     */
    protected array[string] _quoteJoins(array  joins) {
        auto result;
         joins.each!((value) {
            string alias = "";
            if (!empty(value["alias"])) {
                alias = this.quoteIdentifier(value["alias"]);
                value["alias"] = alias;
            }
            if (isString(value["table"])) {
                value["table"] = this.quoteIdentifier(value["table"]);
            }
            result[alias] = value;
        });
        return result;
    }
    
    /**
     * Quotes all identifiers in each of the clauses of a SELECT query
     * Params:
     * \UIM\Database\Query\SelectQuery<mixed> aQuery The query to quote.
     */
    protected void _quoteSelect(SelectQuery queryToQuote) {
       _quoteParts(queryToQuote, ["select", "distinct", "from", "group"]);

        auto  joins = queryToQuote.clause("join");
        if ( joins) {
             joins = _quoteJoins( joins);
            queryToQuote.join( joins, [], true);
        }
    }
    
    /**
     * Quotes all identifiers in each of the clauses of a DELETE query
     * Params:
     * \UIM\Database\Query\DeleteQuery aQuery The query to quote.
     */
    protected void _quoteDelete(DeleteQuery queryToQuote) {
       _quoteParts(queryToQuote, ["from"]);

         joins = queryToQuote.clause("join");
        if ( joins) {
             joins = _quoteJoins( joins);
            queryToQuote.join( joins, [], true);
        }
    }
    
    /**
     * Quotes the table name and columns for an insert query
     * Params:
     * \UIM\Database\Query\InsertQuery aQuery The insert query to quote.
     */
    protected void _quoteInsert(InsertQuery queryToQuote) {
        auto anInsert = queryToQuote.clause("insert");
        if (!isSet(anInsert[0]) || !isSet(anInsert[1])) {
            return;
        }
        [aTable, someColumns] =  anInsert;
        aTable = this.quoteIdentifier(aTable);
        foreach (&column; someColumns ) {
            if (isScalar(column)) {
                column = this.quoteIdentifier((string)column);
            }
        }
        queryToQuote.insert(someColumns).into(aTable);
    }
    
    // Quotes the table name for an update query
    protected void _quoteUpdate(UpdateQuery aQuery) {
        auto aTable = aQuery.clause("update")[0];

        if (isString(aTable)) {
            aQuery.update(this.quoteIdentifier(aTable));
        }
    }
    
    /**
     * Quotes identifiers in expression objects implementing the field interface
     * Params:
     * \UIM\Database\Expression\IField expressionToQuote The expression to quote.
     */
    protected void _quoteComparison(IField expressionToQuote) {
        auto fields = expressionToQuote.getFieldNames();
        if (isString(fields)) {
            expressionToQuote.setFieldNames(this.quoteIdentifier(fields));
        } elseif (isArray(fields)) {
            string[] quotedFields = fields
                .map!(field => this.quoteIdentifier(field)).array;
            expressionToQuote.setFieldNames(quotedFields);
        } else {
            this.quoteExpression(fields);
        }
    }
    
    /**
     * Quotes identifiers in "order by" expression objects
     *
     * Strings with spaces are treated as literal expressions
     * and will not have identifiers quoted.
     * Params:
     * \UIM\Database\Expression\OrderByExpression expressionToQuote The expression to quote.
     */
    protected void _quoteOrderBy(OrderByExpression expressionToQuote) {
        expressionToQuote.iterateParts(function (part, &field) {
            if (isString(field)) {
                field = this.quoteIdentifier(field);

                return part;
            }
            if (isString(part) && !part.has(" ")) {
                return this.quoteIdentifier(part);
            }
            return part;
        });
    }
    
    /**
     * Quotes identifiers in "order by" expression objects
     * Params:
     * \UIM\Database\Expression\IdentifierExpression expressionToQuote The identifiers to quote.
     */
    protected void _quoteIdentifierExpression(IdentifierExpression expressionToQuote) {
        expressionToQuote.setIdentifier(
            this.quoteIdentifier(expressionToQuote.getIdentifier())
        );
    }
}
