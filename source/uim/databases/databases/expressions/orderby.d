module uim.cake.databases.Expression;

import uim.cake;

@safe:

/**
 * An expression object for ORDER BY clauses
 */
class OrderByExpression : QueryExpression {
    /**
     * Constructor
     * Params:
     * \UIM\Database\IExpression|string[] aconditions The sort columns
     * @param \UIM\Database\TypeMap|STRINGAA types The types for each column.
     * @param string aconjunction The glue used to join conditions together.
     */
    this(
        IExpression|string[] aconditions = [],
        TypeMap|array types = [],
        string aConjunction = ""
    ) {
        super(conditions, types, aConjunction);
    }
    string sql(ValueBinder aBinder) {
        string[] sqlOrders;
        foreach (myKey: direction; _conditions) {
            if (cast(IExpression) direction ) {
                direction = direction.sql(aBinder);
            }
            sqlOrders ~= isNumeric(myKey) ? direction : "%s %s".format(myKey, direction);
        }
        return "ORDER BY %s".format(sqlOrders.join(", "));
    }
    
    /**
     * Auxiliary auto used for decomposing a nested array of conditions and
     * building a tree structure inside this object to represent the full SQL expression.
     *
     * New order by expressions are merged to existing ones
     * Params:
     * array conditions list of order by expressions
     * @param array types list of types associated on fields referenced in conditions
     */
    protected void _addConditions(array conditions, array types) {
        auto conditions.byKeyValue
            .each!((kv) {
                if (
                    isString(kv.key) && isString(kv.value) &&
                    !in_array(strtoupper(kv.value), ["ASC", "DESC"], true)
                ) {
                    throw new InvalidArgumentException(
                        "Passing extra expressions by associative array (`\'%s\": \'%s\'`) " ~
                        "is not allowed to avoid potential SQL injection. " ~
                        "Use QueryExpression or numeric array instead."
                        .format(kv.key, kv.value)
                    );
                }
            });

       _conditions = chain(_conditions, conditions);
    }
}
