

/**
 * CakePHP(tm) : Rapid Development Framework (https://cakephp.org)
 * Copyright (c) Cake Software Foundation, Inc. (https://cakefoundation.org)
 *
 * Licensed under The MIT License
 * For full copyright and license information, please see the LICENSE.txt
 * Redistributions of files must retain the above copyright notice.
 *
 * @copyright     Copyright (c) Cake Software Foundation, Inc. (https://cakefoundation.org)
 * @link          https://cakephp.org CakePHP(tm) Project
 * @since         3.2.14
 * @license       https://opensource.org/licenses/mit-license.php MIT License
 */
module uim.databases;

/**
 * Encapsulates all conversion functions for values coming from a database into D and
 * going from D into a database.
 */
interface TypeInterface
{
    /**
     * Casts given value from a D type to one acceptable by a database.
     *
     * @param mixed aValue Value to be converted to a database equivalent.
     * @param uim.databases.IDBADriver aDriver Object from which database preferences and configuration will be extracted.
     * @return mixed Given D type casted to one acceptable by a database.
     */
    function toDatabase(DValue aValue, IDBADriver aDriver);

    /**
     * Casts given value from a database type to a D equivalent.
     *
     * @param mixed aValue Value to be converted to D equivalent
     * @param uim.databases.IDBADriver aDriver Object from which database preferences and configuration will be extracted
     * @return mixed Given value casted from a database to a D equivalent.
     */
    function toD(DValue aValue, IDBADriver aDriver);

    /**
     * Casts given value to its Statement equivalent.
     *
     * @param mixed aValue Value to be converted to PDO statement.
     * @param uim.databases.IDBADriver aDriver Object from which database preferences and configuration will be extracted.
     * @return mixed Given value casted to its Statement equivalent.
     */
    function toStatement(DValue aValue, IDBADriver aDriver);

    /**
     * Marshals flat data into D objects.
     *
     * Most useful for converting request data into D objects,
     * that make sense for the rest of the ORM/Database layers.
     *
     * @param mixed aValue The value to convert.
     * @return mixed Converted value.
     */
    function marshal(DValue aValue);

    /**
     * Returns the base type name that this class is inheriting.
     *
     * This is useful when extending base type for adding extra functionality,
     * but still want the rest of the framework to use the same assumptions it would
     * do about the base type it inherits from.
     *
     * @return string|null The base type name that this class is inheriting.
     */
    function getBaseType(): ?string;

    /**
     * Returns type identifier name for this object.
     *
     * @return string|null The type identifier name for this object.
     */
    function getName(): ?string;

    /**
     * Generate a new primary key value for a given type.
     *
     * This method can be used by types to create new primary key values
     * when entities are inserted.
     *
     * @return mixed A new primary key value.
     * @see uim.databases.Type\UuidType
     */
    function newId();
}
