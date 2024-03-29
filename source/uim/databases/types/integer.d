/*********************************************************************************************************
* Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        *
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  *
* Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      *
**********************************************************************************************************/
module uim.databases.types.integer;

@safe:
import uim.databases;

/**
 * Integer type converter.
 * Use to convert integer data between D and the database types.
 */
class IntegerType : BaseType, IBatchCasting {
  /**
    * Checks if the value is not a numeric value
    *
    * @throws \InvalidArgumentException
    * @param mixed aValue Value to check
    * @return void
    */
  protected void checkNumeric(DValue aValue) {
    if (!is_numeric(DValue aValue)) {
        throw new InvalidArgumentException(sprintf(
            "Cannot convert value of type `%s` to integer",
            getTypeName(DValue aValue)
        ));
    }
  }

  /**
    * Convert integer data into the database format.
    *
    * @param mixed aValue The value to convert.
    * @param uim.databases.IDBADriver aDriver The driver instance to convert with.
    * @return int|null
    */
  function toDatabase(DValue aValue, IDBADriver aDriver): ?int
  {
      if (DValue aValue == null || aValue == "") {
          return null;
      }

      this.checkNumeric(DValue aValue);

      return (int)aValue;
  }

  /**
    * {@inheritDoc}
    *
    * @param mixed aValue The value to convert.
    * @param uim.databases.IDBADriver aDriver The driver instance to convert with.
    * @return int|null
    */
  function toD(DValue aValue, IDBADriver aDriver): ?int
  {
      if (DValue aValue == null) {
          return null;
      }

      return (int)aValue;
  }


  function manytoD(array someValues, string[] someFields, IDBADriver aDriver): array
  {
      foreach (fields as field) {
          if (!isset(someValues[field])) {
              continue;
          }

          this.checkNumeric(someValues[field]);

          someValues[field] = (int)someValues[field];
      }

      return someValues;
  }

  /**
    * Get the correct PDO binding type for integer data.
    *
    * @param mixed aValue The value being bound.
    * @param uim.databases.IDBADriver aDriver The driver.
    * @return int
    */
  function toStatement(DValue aValue, IDBADriver aDriver): int
  {
      return PDO::PARAM_INT;
  }

  /**
    * Marshals request data into D integers.
    *
    * @param mixed aValue The value to convert.
    * @return int|null Converted value.
    */
  Nullable!int marshal(DValue aValue) {
    Nullable!int result;
    if (DValue aValue == null || aValue == "") {
      return result;
    }
    if (is_numeric(DValue aValue)) {
        return (int)aValue;
    }

    return null;
  }
}
