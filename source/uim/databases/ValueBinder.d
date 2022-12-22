/*********************************************************************************************************
*	Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        *
*	License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  *
*	Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      *
**********************************************************************************************************/
module uim.cake;

@safe:
import uim.cake;

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
     *
     * @var array
     */
    protected _bindings = [];

    // _bindingsCount - A counter of the number of parameters bound in this expression object
    protected int _bindingsCount = 0;

    /**
     * Associates a query placeholder to a value and a type
     *
     * @param string|int $param placeholder to be replaced with quoted version
     * of $value
     * @param mixed $value The value to be bound
     * @param string|int|null $type the mapped type name, used for casting when sending
     * to database
     * @return void
     */
    void bind(string aParameter, param, aValue, aType = null) {
        _bindings[aParameter] = ["value": aValue, "type":aType];
        _bindings[aParameter]["placeholder"] = isInt(aParameter) ? aParameter : substr(aParameter, 1);
    }

    /**
     * Creates a unique placeholder name if the token provided does not start with ":"
     * otherwise, it will return the same string and internally increment the number
     * of placeholders generated by this object.
     *
     * @param string aToken string from which the placeholder will be derived from,
     * if it starts with a colon, then the same string is returned
     * @return string to be used as a placeholder in a query expression
     */
    string placeholder(string aToken) {
      auto myNumber = _bindingsCount++;
      if (aToken[0] != ":" && aToken != "?") {
        aToken = ":%s%s".format(aToken, myNumber);
      }

      return aToken;
    }

    /**
     * Creates unique named placeholders for each of the passed values
     * and binds them with the specified type.
     *
     * @param iterable $values The list of values to be bound
     * @param string|int|null $type The type with which all values will be bound
     * @return array with the placeholders to insert in the query
     */
    function generateManyNamed(iterable $values, $type = null): array {
        $placeholders = [];
        foreach (key, value; $values) {
            $param = this.placeholder("c");
            _bindings[$param] = [
                "value": value,
                "type": $type,
                "placeholder": substr($param, 1),
            ];
            $placeholders[key] = $param;
        }

        return $placeholders;
    }

    /**
     * Returns all values bound to this expression object at this nesting level.
     * Subexpression bound values will not be returned with this function.
     */
    auto bindings() {
      return _bindings;
    }

    // Clears any bindings that were previously registered
    void reset() {
      _bindings = [];
      _bindingsCount = 0;
    }

    // Resets the bindings count without clearing previously bound values
    void resetCount() {
      _bindingsCount = 0;
    }

    /**
     * Binds all the stored values in this object to the passed statement.
     *
     * @param \Cake\Database\IStatement aStatement The statement to add parameters to.
     */
    void attachTo(IStatement aStatement) {
      auto myBindings = this.bindings();
      if (empty(myBindings)) {
          return;
      }

      foreach (myBinding; myBindings) {
          $statement->bindValue(myBinding["placeholder"], myBinding["value"], myBinding["type"]);
      }
    }
}
