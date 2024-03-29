/*********************************************************************************************************
	Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        
	License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  
	Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      
**********************************************************************************************************/
module uim.databases.expressions;

@safe:
import uim.databases;

use Closure;

/**
 * An expression object that represents an expression with only a single operand.
 */
class UnaryExpression : IDBAExpression
{
    /**
     * Indicates that the operation is in pre-order
     *
     * @var int
     */
    const PREFIX = 0;

    /**
     * Indicates that the operation is in post-order
     *
     * @var int
     */
    const POSTFIX = 1;

    /**
     * The operator this unary expression represents
     */
    protected string _operator;

    /**
     * Holds the value which the unary expression operates
     *
     * @var mixed
     */
    protected _value;

    /**
     * Where to place the operator
     */
    protected int position;

    /**
     * Constructor
     *
     * @param string  operator The operator to used for the expression
     * @param mixed value the value to use as the operand for the expression
     * @param int position either UnaryExpression::PREFIX or UnaryExpression::POSTFIX
     */
    this(string  operator, value, position = self::PREFIX) {
        _operator =  operator;
        _value = value;
        this.position = position;
    }


    string sql(ValueBinder aBinder) {
         operand = _value;
        if ( operand instanceof IDBAExpression) {
             operand =  operand.sql( binder);
        }

        if (this.position == self::POSTFIX) {
            return "(" ~  operand ~ ") " ~ _operator;
        }

        return _operator ~ " (" ~  operand ~ ")";
    }


    O traverse(this O)(Closure callback) {
        if (_value instanceof IDBAExpression) {
            callback(_value);
            _value.traverse(callback);
        }

        return this;
    }

    /**
     * Perform a deep clone of the inner expression.
     */
    void __clone() {
        if (_value instanceof IDBAExpression) {
            _value = clone _value;
        }
    }
}
