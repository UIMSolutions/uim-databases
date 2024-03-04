module uim.databases;
/**
 * Value binder class manages list of values bound to conditions.
 *
 * @internal
 */
class ValueBinder {
    /**
     * Array containing a list of bound values to the conditions on this
     * object. Each array entry is another array structure containing the actual
     * bound value, its type and the placeholder it is bound to.
     */
    protected array _bindings = [];

    // A counter of the number of parameters bound in this expression object
    protected int _bindingsCount = 0;

    /**
     * Associates a query placeholder to a value and a type
     * Params:
     * string|int param placeholder to be replaced with quoted version
     * of aValue
     * valueToBind - The value to be bound
     * @param string|int type the mapped type name, used for casting when sending
     * to database
     */
    void bind(string|int param, Json valueToBind, string|int type = null) {
       _bindings[param] = compact("value", "type") ~ [
            "placeholder": isInt(param) ? param : substr(param, 1),
        ];
    }
    
    /**
     * Creates a unique placeholder name if the token provided does not start with ":"
     * otherwise, it will return the same string and internally increment the number
     * of placeholders generated by this object.
     * Params:
     * string atoken string from which the placeholder will be derived from,
     * if it starts with a colon, then the same string is returned
     */
    string placeholder(string atoken) {
        auto myNumber = _bindingsCount++;
        if (token[0] != ":" && token != "?") {
            token = ":%s%s".format(token, myNumber);
        }
        return token;
    }
    
    /**
     * Creates unique named placeholders for each of the passed values
     * and binds them with the specified type.
     * Params:
     * iterable  someValues The list of values to be bound
     * @param string|int type The type with which all values will be bound
     */
    array generateManyNamed(iterable  someValues, string|int type = null) {
        auto placeholders = [];
        foreach (someValues as myKey: aValue) {
            param = this.placeholder("c");
           _bindings[param] = [
                'value": aValue,
                'type": type,
                'placeholder": substr(param, 1),
            ];
            placeholders[myKey] = param;
        }
        return placeholders;
    }
    
    /**
     * Returns all values bound to this expression object at this nesting level.
     * Subexpression bound values will not be returned with this function.
     */
    array bindings() {
        return _bindings;
    }
    
    // Clears any bindings that were previously registered
    void reset() {
       _bindings = [];
       _bindingsCount = 0;
    }
    
    /**
     * Resets the bindings count without clearing previously bound values
     */
    void resetCount() {
       _bindingsCount = 0;
    }
    
    /**
     * Binds all the stored values in this object to the passed statement.
     * Params:
     * \UIM\Database\IStatement $statement The statement to add parameters to.
     */
    void attachTo(IStatement targetStatement) {
        auto bindings = this.bindings();
        if (isEmpty(bindings)) {
            return;
        }
        bindings
            .each!(binding => targetStatement.bindValue(binding["placeholder"], binding["value"], binding["type"]));
    }
    
    // Get verbose debugging data.
    IData[string] debugInfo() {
        return [
            "bindings": this.bindings(),
        ];
    }
}
