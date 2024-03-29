/*********************************************************************************************************
	Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        
	License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  
	Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      
**********************************************************************************************************/module uim.databases;

@safe:
import uim.databases;

module uim.databases;

import uim.datasources.IConnection;

/**
 * Defines the interface for a fixture that needs to manage constraints.
 *
 * If an implementation of `Cake\Datasource\IFixture` also implements
 * this interface, the FixtureManager will use these methods to manage
 * a fixtures constraints.
 */
interface IConstraints
{
    /**
     * Build and execute SQL queries necessary to create the constraints for the
     * fixture
     *
     * @param uim.Datasource\IConnection connection An instance of the database
     *  into which the constraints will be created.
     * @return bool on success or if there are no constraints to create, or false on failure
     */
    bool createConstraints(IConnection aConnection);

    /**
     * Build and execute SQL queries necessary to drop the constraints for the
     * fixture
     *
     * @param uim.Datasource\IConnection connection An instance of the database
     *  into which the constraints will be dropped.
     * @return bool on success or if there are no constraints to drop, or false on failure
     */
    bool dropConstraints(IConnection aConnection);
}
